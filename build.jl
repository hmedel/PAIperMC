#!/usr/bin/env julia
# =============================================================================
# paipermc — build.jl
# Compila paipermc usando PackageCompiler
#
# Uso:
#   julia build.jl sysimage    → crea paipermc.so (para xolotl, rápido)
#   julia build.jl app         → crea build/paipermc ejecutable standalone
#   julia build.jl install     → compila + instala en ~/.local/bin/paipermc
#   julia build.jl clean       → elimina artefactos de compilación
#
# La sysimage es para desarrollo rápido (Julia requerido).
# El app es para distribución (no requiere Julia instalado).
# =============================================================================

using Pkg

# ── Verificar que estamos en el directorio correcto ──────────────────────────
isfile("Project.toml") ||
    error("Ejecuta este script desde el directorio raíz del proyecto paipermc")

# ── Instalar PackageCompiler si no está ──────────────────────────────────────
try
    using PackageCompiler
catch
    println("Instalando PackageCompiler...")
    Pkg.add("PackageCompiler")
    using PackageCompiler
end

# ── Instalar dependencias del proyecto ───────────────────────────────────────
println("Verificando dependencias...")
Pkg.instantiate()

# ── Configuración ─────────────────────────────────────────────────────────────
const PROJECT_DIR   = pwd()
const BUILD_DIR     = joinpath(PROJECT_DIR, "build")
const SYSIMAGE_PATH = joinpath(PROJECT_DIR, "paipermc.so")
const APP_DIR       = joinpath(BUILD_DIR, "paipermc_app")
const PRECOMPILE    = joinpath(PROJECT_DIR, "precompile_paipermc.jl")
const INSTALL_DIR   = expanduser("~/.local/bin")

# ── Helpers ───────────────────────────────────────────────────────────────────
function print_step(msg::String)
    println("\n\033[1m=== $msg ===\033[0m")
end

function print_ok(msg::String)
    println("\033[32m[OK]\033[0m $msg")
end

function print_info(msg::String)
    println("\033[34m[info]\033[0m $msg")
end

function elapsed_str(t::Float64) :: String
    t < 60 ? "$(round(t, digits=1))s" : "$(round(t/60, digits=1))min"
end

# ── Sysimage ──────────────────────────────────────────────────────────────────
"""
Crea paipermc.so — sysimage para uso local en xolotl.
Requiere Julia instalado para ejecutar.
Arranque: ~0.3s en lugar de 5-8s.

Uso después de compilar:
  julia --sysimage paipermc.so -e 'using Paipermc; Paipermc.julia_main()'
  # o con el wrapper script generado:
  ./paipermc-sysimage "mejora la introduccion"
"""
function build_sysimage()
    print_step "Compilando sysimage (paipermc.so)"
    print_info "Esto tarda ~5-10 minutos la primera vez"
    print_info "Sysimage: $SYSIMAGE_PATH"

    t_start = time()

    PackageCompiler.create_sysimage(
        [:Paipermc];
        sysimage_path            = SYSIMAGE_PATH,
        project                  = PROJECT_DIR,
        precompile_execution_file = isfile(PRECOMPILE) ? PRECOMPILE : nothing,
        cpu_target               = "native",   # optimiza para la CPU actual
    )

    elapsed = time() - t_start
    print_ok "Sysimage creada en $(elapsed_str(elapsed)): $SYSIMAGE_PATH"
    print_info "Tamaño: $(round(filesize(SYSIMAGE_PATH)/1024^2, digits=1)) MB"

    # Generar wrapper script
    wrapper = joinpath(PROJECT_DIR, "paipermc-sysimage")
    write(wrapper, """#!/usr/bin/env bash
# paipermc wrapper — usa sysimage para arranque rápido
JULIA_BIN=$(julia -e 'print(joinpath(Sys.BINDIR, "julia"))')
SYSIMAGE="$(SYSIMAGE_PATH)"
PROJECT="$(PROJECT_DIR)"
exec "\$JULIA_BIN" --sysimage="\$SYSIMAGE" --project="\$PROJECT" \\
    -e 'using Paipermc; exit(Paipermc.julia_main())' -- "\$@"
""")
    chmod(wrapper, 0o755)
    print_ok "Wrapper script: $wrapper"

    println("""
\033[1mUso:\033[0m
  $(wrapper) \"mejora la introducción\"
  $(wrapper) serve
  $(wrapper) --help
""")
end

# ── App standalone ────────────────────────────────────────────────────────────
"""
Crea un ejecutable standalone en build/paipermc_app/bin/paipermc.
No requiere Julia instalado en la máquina destino.
El bundle incluye Julia y todas las dependencias.
Tamaño típico: 150-300 MB.
"""
function build_app()
    print_step "Compilando app standalone"
    print_info "Esto tarda ~15-30 minutos"
    print_info "Destino: $APP_DIR"

    mkpath(BUILD_DIR)
    isdir(APP_DIR) && rm(APP_DIR, recursive=true)

    t_start = time()

    PackageCompiler.create_app(
        PROJECT_DIR,
        APP_DIR;
        precompile_execution_file = isfile(PRECOMPILE) ? PRECOMPILE : nothing,
        force                     = true,
        cpu_target                = "generic",  # portable entre máquinas similares
    )

    elapsed = time() - t_start
    exe = joinpath(APP_DIR, "bin", "paipermc")
    print_ok "App compilada en $(elapsed_str(elapsed))"
    print_ok "Ejecutable: $exe"

    # Tamaño del bundle
    total = 0
    for (root, dirs, files) in walkdir(APP_DIR)
        for f in files
            total += filesize(joinpath(root, f))
        end
    end
    print_info "Tamaño total: $(round(total/1024^2, digits=1)) MB"

    println("""
\033[1mUso:\033[0m
  $exe \"mejora la introducción\"
  $exe serve
  $exe --help

\033[1mDistribuir a ollintzin:\033[0m
  rsync -av $APP_DIR/ hector@ollintzin:~/.local/lib/paipermc/
  ln -sf ~/.local/lib/paipermc/bin/paipermc ~/.local/bin/paipermc
""")
end

# ── Install ───────────────────────────────────────────────────────────────────
"""
Compila app y la instala en ~/.local/bin/paipermc.
"""
function build_and_install()
    build_app()

    print_step "Instalando en $INSTALL_DIR"
    mkpath(INSTALL_DIR)

    lib_dir = expanduser("~/.local/lib/paipermc")
    isdir(lib_dir) && rm(lib_dir, recursive=true)

    cp(APP_DIR, lib_dir)

    # Symlink al ejecutable
    exe_link = joinpath(INSTALL_DIR, "paipermc")
    isfile(exe_link) && rm(exe_link)
    symlink(joinpath(lib_dir, "bin", "paipermc"), exe_link)

    print_ok "Instalado: $exe_link"
    println("\nVerifica: paipermc --version")
end

# ── Clean ─────────────────────────────────────────────────────────────────────
function clean()
    print_step "Limpiando artefactos de compilación"
    for path in [SYSIMAGE_PATH, APP_DIR,
                 joinpath(PROJECT_DIR, "paipermc-sysimage")]
        if ispath(path)
            rm(path, recursive=true)
            println("  removed: $path")
        end
    end
    print_ok "Limpieza completa"
end

# ── Benchmark de arranque ─────────────────────────────────────────────────────
function benchmark()
    print_step "Benchmark de tiempo de arranque"

    julia_bin = joinpath(Sys.BINDIR, "julia")
    project   = PROJECT_DIR

    # Sin sysimage
    t1 = @elapsed run(`$julia_bin --project=$project -e 'using Paipermc; println("loaded")'`)
    println("  Sin sysimage:  $(round(t1, digits=2))s")

    # Con sysimage (si existe)
    if isfile(SYSIMAGE_PATH)
        t2 = @elapsed run(`$julia_bin --sysimage=$SYSIMAGE_PATH --project=$project -e 'using Paipermc; println("loaded")'`)
        println("  Con sysimage:  $(round(t2, digits=2))s")
        println("  Speedup:       $(round(t1/t2, digits=1))x")
    else
        println("  Con sysimage:  (no compilada — ejecuta: julia build.jl sysimage)")
    end

    # Con app (si existe)
    exe = joinpath(APP_DIR, "bin", "paipermc")
    if isfile(exe)
        t3 = @elapsed run(`$exe --version`)
        println("  App standalone: $(round(t3, digits=2))s")
    end
end

# ── Dispatch ──────────────────────────────────────────────────────────────────
const cmd = length(ARGS) > 0 ? ARGS[1] : "help"

if cmd == "sysimage"
    build_sysimage()
elseif cmd == "app"
    build_app()
elseif cmd == "install"
    build_and_install()
elseif cmd == "clean"
    clean()
elseif cmd == "benchmark"
    benchmark()
elseif cmd == "help"
    println("""
paipermc build.jl — compilación con PackageCompiler

Comandos:
  julia build.jl sysimage    Crea paipermc.so (~5-10 min, requiere Julia)
  julia build.jl app         Crea ejecutable standalone (~15-30 min)
  julia build.jl install     Compila + instala en ~/.local/bin/paipermc
  julia build.jl benchmark   Mide tiempos de arranque
  julia build.jl clean       Elimina artefactos compilados
  julia build.jl help        Muestra esta ayuda

Recomendación:
  En xolotl (servidor):  julia build.jl sysimage
  En ollintzin (cliente): julia build.jl install
""")
else
    println("Comando desconocido: $cmd")
    println("Usa: julia build.jl help")
    exit(1)
end
