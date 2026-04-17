#!/usr/bin/env bash
# =============================================================================
# paipermc — install-ollintzin.sh
# Instala el CLI de paipermc en ollintzin (cliente macOS)
#
# Opciones:
#   bash install-ollintzin.sh sysimage   instala con sysimage (Julia requerido)
#   bash install-ollintzin.sh app        instala app standalone
#   bash install-ollintzin.sh dev        modo desarrollo (sin compilar)
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[paipermc]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()    { echo -e "\n${BOLD}=== $* ===${NC}"; }

# ── Configuración ─────────────────────────────────────────────────────────────
XOLOTL_IP="100.64.0.22"
XOLOTL_USER="mech"
XOLOTL_PROJECT="/home/mech/Projects/PAIperMC/paipermc"
LOCAL_LIB="${HOME}/.local/lib/paipermc"
LOCAL_BIN="${HOME}/.local/bin"
MODE="${1:-sysimage}"

# ── Verificaciones ────────────────────────────────────────────────────────────
step "Verificando prerequisitos"

# Verificar acceso a xolotl
ssh -q "${XOLOTL_USER}@${XOLOTL_IP}" "echo ok" &>/dev/null \
    && success "SSH a xolotl OK" \
    || error "No puedo conectar a xolotl via SSH"

# Verificar acceso a LiteLLM
curl -sf "http://${XOLOTL_IP}:8088/v1/models" \
    -H "Authorization: Bearer sk-phaimat-local" > /dev/null \
    && success "LiteLLM accesible en ${XOLOTL_IP}:8088" \
    || warn "LiteLLM no responde — verifica que xolotl esté corriendo"

mkdir -p "${LOCAL_BIN}" "${LOCAL_LIB}"

# ── Modo: sysimage ────────────────────────────────────────────────────────────
if [[ "$MODE" == "sysimage" ]]; then
    step "Instalando CLI con sysimage"

    # Verificar Julia local
    command -v julia &>/dev/null \
        || error "Julia no instalado. Instala con: brew install julia"

    info "Compilando sysimage en xolotl (esto tarda ~10 min)..."
    ssh "${XOLOTL_USER}@${XOLOTL_IP}" \
        "cd ${XOLOTL_PROJECT} && julia build.jl sysimage"

    info "Descargando sysimage desde xolotl..."
    scp "${XOLOTL_USER}@${XOLOTL_IP}:${XOLOTL_PROJECT}/paipermc.so" \
        "${LOCAL_LIB}/paipermc.so"

    info "Copiando código fuente..."
    rsync -av --delete \
        "${XOLOTL_USER}@${XOLOTL_IP}:${XOLOTL_PROJECT}/src/" \
        "${LOCAL_LIB}/src/"
    rsync -av \
        "${XOLOTL_USER}@${XOLOTL_IP}:${XOLOTL_PROJECT}/Project.toml" \
        "${LOCAL_LIB}/"

    # Instalar dependencias localmente
    julia --project="${LOCAL_LIB}" -e 'using Pkg; Pkg.instantiate()'

    # Wrapper script
    cat > "${LOCAL_BIN}/paipermc" << WRAPPER
#!/usr/bin/env bash
# paipermc CLI — con sysimage para arranque rápido
JULIA_BIN="$(julia -e 'print(joinpath(Sys.BINDIR, "julia"))')"
exec "\$JULIA_BIN" \\
    --sysimage="${LOCAL_LIB}/paipermc.so" \\
    --project="${LOCAL_LIB}" \\
    -e 'using Paipermc; exit(Paipermc.julia_main())' -- "\$@"
WRAPPER
    chmod +x "${LOCAL_BIN}/paipermc"
    success "paipermc instalado con sysimage"

# ── Modo: app standalone ──────────────────────────────────────────────────────
elif [[ "$MODE" == "app" ]]; then
    step "Instalando CLI como app standalone"

    info "Compilando app en xolotl (esto tarda ~20-30 min)..."
    ssh "${XOLOTL_USER}@${XOLOTL_IP}" \
        "cd ${XOLOTL_PROJECT} && julia build.jl app"

    info "Descargando app desde xolotl..."
    rsync -av --delete \
        "${XOLOTL_USER}@${XOLOTL_IP}:${XOLOTL_PROJECT}/build/paipermc_app/" \
        "${LOCAL_LIB}/"

    # Symlink
    ln -sf "${LOCAL_LIB}/bin/paipermc" "${LOCAL_BIN}/paipermc"
    success "paipermc instalado como app standalone"

# ── Modo: dev (sin compilar) ──────────────────────────────────────────────────
elif [[ "$MODE" == "dev" ]]; then
    step "Instalando CLI en modo desarrollo"

    info "Copiando código fuente desde xolotl..."
    rsync -av --delete \
        "${XOLOTL_USER}@${XOLOTL_IP}:${XOLOTL_PROJECT}/" \
        "${LOCAL_LIB}/" \
        --exclude=".git" \
        --exclude="build/" \
        --exclude="*.so" \
        --exclude=".lake/"

    command -v julia &>/dev/null \
        || error "Julia no instalado. Instala con: brew install julia"

    julia --project="${LOCAL_LIB}" -e 'using Pkg; Pkg.instantiate()'

    # Wrapper sin sysimage — lento pero útil para desarrollo
    cat > "${LOCAL_BIN}/paipermc" << WRAPPER
#!/usr/bin/env bash
# paipermc CLI — modo desarrollo (sin sysimage, lento al arrancar)
exec julia --project="${LOCAL_LIB}" \\
    -e 'using Paipermc; exit(Paipermc.julia_main())' -- "\$@"
WRAPPER
    chmod +x "${LOCAL_BIN}/paipermc"
    warn "Modo desarrollo: arranque lento (~5-8s). Compila con: bash install-ollintzin.sh sysimage"

else
    error "Modo desconocido: $MODE. Usa: sysimage | app | dev"
fi

# ── Configuración de entorno ──────────────────────────────────────────────────
step "Configurando variables de entorno"

ENV_BLOCK="
# paipermc
export PAIPERMC_LITELLM_HOST=\"http://${XOLOTL_IP}:8088\"
export PAIPERMC_LITELLM_KEY=\"sk-phaimat-local\"
export PAIPERMC_LITERATURE_HOST=\"http://${XOLOTL_IP}:8081\"
export PAIPERMC_AGENT_KEY=\"sk-phaimat-agent\"
export PAIPERMC_AGENT_HOST=\"${XOLOTL_IP}\"
export PAIPERMC_AGENT_PORT=\"9000\"
export PATH=\"\${HOME}/.local/bin:\${PATH}\""

# Detectar shell
SHELL_RC="${HOME}/.zshrc"
[[ "$SHELL" == *"bash"* ]] && SHELL_RC="${HOME}/.bashrc"

if grep -q "PAIPERMC_LITELLM_HOST" "$SHELL_RC" 2>/dev/null; then
    warn "Variables de entorno ya configuradas en $SHELL_RC"
else
    echo "$ENV_BLOCK" >> "$SHELL_RC"
    success "Variables agregadas a $SHELL_RC"
fi

# ── Verificación ──────────────────────────────────────────────────────────────
step "Verificación"

success "paipermc instalado en ${LOCAL_BIN}/paipermc"
info "Carga el entorno: source $SHELL_RC"
info "Luego prueba:"
echo ""
echo "  paipermc --version"
echo "  paipermc status"
echo "  paipermc \"escribe una oración de prueba\""
echo ""
