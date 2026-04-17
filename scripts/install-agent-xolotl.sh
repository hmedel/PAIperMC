#!/usr/bin/env bash
# paipermc — instalar el agent server (Fase B) en xolotl
set -euo pipefail

PAIPERMC_ROOT="/home/mech/Projects/PAIperMC/paipermc"
JULIA_BIN="$HOME/.julia/bin"

echo "=== Instalando paipermc agent server (Fase B) ==="

# 1. Instalar Julia si no está
if ! command -v julia &>/dev/null; then
    echo "Instalando Julia..."
    curl -fsSL https://install.julialang.org | sh -s -- -y
    source ~/.bashrc
fi

echo "Julia: $(julia --version)"

# 2. Copiar código fuente
echo "Copiando código fuente..."
mkdir -p "${PAIPERMC_ROOT}"
# El código se copia desde el repositorio — ajusta la ruta si clonas desde git
# Por ahora asumimos que los archivos ya están en xolotl

# 3. Instalar dependencias Julia
echo "Instalando dependencias Julia..."
cd "${PAIPERMC_ROOT}"
julia --project=. -e '
    using Pkg
    Pkg.instantiate()
    Pkg.precompile()
    println("Dependencias OK")
'

# 4. Instalar servicio systemd
echo "Instalando servicio systemd..."
sudo cp services/paipermc-agent.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable paipermc-agent.service
sudo systemctl start paipermc-agent.service

sleep 3
sudo systemctl is-active --quiet paipermc-agent.service \
    && echo "[OK] paipermc-agent.service activo en :9000" \
    || echo "[WARN] Revisa: journalctl -u paipermc-agent -n 20"

# 5. Verificar WebSocket
echo ""
echo "Verificando agent server..."
julia -e '
    using WebSockets, JSON3
    try
        WebSockets.open("ws://localhost:9000") do ws
            send(ws, JSON3.write(Dict("type"=>"ping")))
            resp = JSON3.read(receive(ws), Dict)
            println("Server response: ", resp["type"])
        end
    catch e
        println("Error: ", e)
    end
' && echo "[OK] WebSocket responde" || echo "[WARN] WebSocket no disponible aún"

echo ""
echo "=== Fase B completa ==="
echo ""
echo "Prueba desde ollintzin:"
echo "  paipermc status"
echo "  paipermc 'hello'"
