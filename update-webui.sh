#!/usr/bin/env bash
set -Eeuo pipefail

# ----------------------------------------------------------------------------
# update-webui.sh – Actualiza automáticamente browser-use/web-ui dentro del CT
# ----------------------------------------------------------------------------
# Detecta el CT que contiene /opt/web-ui y ejecuta:
#  - git pull
#  - pip install -r requirements.txt
#  - playwright install chrome
#  - reinicia servicios supervisor (webui, novnc)
# ----------------------------------------------------------------------------

C_RED='\e[31m'; C_CYAN='\e[36m'; C_GRN='\e[32m'; C_RST='\e[0m'
info(){ echo -e "${C_CYAN}➤ $*${C_RST}"; }
die(){  echo -e "${C_RED}✘ $*${C_RST}" >&2; exit 1; }

# Buscar CT con /opt/web-ui
info "Buscando CT con web-ui instalado..."
CTID=""
for id in $(pct list | tail -n +2 | awk '{print $1}'); do
  if pct exec "$id" -- test -d /opt/web-ui; then
    CTID="$id"
    break
  fi
done

[[ -n "$CTID" ]] || die "No se encontró ningún CT con /opt/web-ui"
info "CT detectado: $CTID"

# Ejecutar actualización dentro del CT
info "Actualizando repositorio y dependencias..."
pct exec "$CTID" -- bash -Eeuo pipefail <<'EOF'
  set -Eeuo pipefail
  cd /opt/web-ui
  # Actualizar código
  git pull --ff-only
  # Activar entorno
  . venv/bin/activate
  # Instalar nuevas dependencias
  pip install -r requirements.txt -q
  # Actualizar Playwright
  PLAYWRIGHT_BROWSERS_PATH=/ms-playwright playwright install chrome
  find /opt/web-ui/src -type f -name '*.py' -exec sed -i 's|./tmp/|./data/|g' {} +
  # Reiniciar servicios
  supervisorctl restart webui novnc
EOF

info "✅  Web-UI actualizada en CT $CTID"
