#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# ─────────────  Colores y helpers  ──────────────────────────────────────────────
C_RED='\e[31m'; C_CYAN='\e[36m'; C_GRN='\e[32m'; C_RST='\e[0m'
info() { echo -e "${C_CYAN}➤ $*${C_RST}"; }
die()  { echo -e "${C_RED}✘ $*${C_RST}" >&2; exit 1; }
ask()  { local __var=$1 __def=$2 __q=$3
         read -rp "$__q [$__def]: " _v
         printf -v "$__var" '%s' "${_v:-$__def}"; }

# ─────────────  Variables por defecto  ─────────────────────────────────────────
CTID=$(pvesh get /cluster/nextid)
HOSTNAME="web-ui"
USERNAME="webui"
CORES=4        MEM=4096   DISK=20
TEMPLATE_STORAGE="local"  ROOTFS_STORAGE="local-lvm"
BRIDGE="vmbr0" PASSWORD="vncpassword"
STATIC4="" STATIC6=""
API_OPENAI="" API_GOOGLE="" API_ANTHROPIC=""
QUIET=0

usage() { grep -E "^# " "$0" | cut -c5-; exit 0; }

# ─────────────  Flags  ──────────────────────────────────────────────────────────
while getopts "qc:n:s:r:d:t:f:i:p:u:4:6:k:h" opt; do
  case $opt in
    q) QUIET=1;;
    c) CTID=$OPTARG;;            s) CORES=$OPTARG;;
    r) MEM=$OPTARG;;             d) DISK=$OPTARG;;
    t) TEMPLATE_STORAGE=$OPTARG; f) ROOTFS_STORAGE=$OPTARG;;
    i) BRIDGE=$OPTARG;;          p) PASSWORD=$OPTARG;;
    u) USERNAME=$OPTARG;;
    4) STATIC4=$OPTARG;;         6) STATIC6=$OPTARG;;
    k) IFS=',' read -ra KVS <<<"$OPTARG"
       for kv in "${KVS[@]}"; do
         case $kv in
           OPENAI=*)    API_OPENAI=${kv#OPENAI=};;
           GOOGLE=*)    API_GOOGLE=${kv#GOOGLE=};;
           ANTHROPIC=*) API_ANTHROPIC=${kv#ANTHROPIC=};;
         esac
       done;;
    h) usage;;
    *) usage;;
  esac
done
shift $((OPTIND-1))

# ─────────────  Preguntas interactivas  ─────────────────────────────────────────
if (( QUIET==0 )); then
  ask CTID "$CTID" "CTID";                ask CORES "$CORES" "vCPUs"
  ask MEM "$MEM" "RAM MB";                ask DISK "$DISK" "Disk GB"
  ask TEMPLATE_STORAGE "$TEMPLATE_STORAGE" "Template storage"
  ask ROOTFS_STORAGE "$ROOTFS_STORAGE"     "RootFS storage"
  ask BRIDGE "$BRIDGE" "Bridge"
  read -rsp "Root/VNC password [hidden, default '$PASSWORD']: " pw; echo
  [[ -n $pw ]] && PASSWORD=$pw
  ask USERNAME "$USERNAME" "Username"
  ask STATIC4 "$STATIC4" "Static IPv4 (ip/mask,gw,dns)"
  ask STATIC6 "$STATIC6" "Static IPv6 (ip/prefix,gw)"
  ask API_OPENAI   "$API_OPENAI"   "OpenAI API key"
  ask API_GOOGLE   "$API_GOOGLE"   "Google API key"
  ask API_ANTHROPIC "$API_ANTHROPIC" "Anthropic API key"
  echo
  info "Resumen ➜ CT $CTID • $CORES CPU • $MEM MB • ${DISK}G • $BRIDGE • user=$USERNAME"
  read -rp "¿Continuar? [Y/n] " yn
  [[ ${yn:-Y} =~ ^[Yy]$ ]] || { echo "Abortado"; exit 0; }
fi

# ─────────────  Plantilla Debian 12  ────────────────────────────────────────────
LATEST=$(pveam available | awk '/debian-12-standard_.*amd64/ {print $2}' | sort -Vr | head -n1)
[[ -n $LATEST ]] || die "No se encontró plantilla Debian 12 en pveam."
TEMPLATE="$TEMPLATE_STORAGE:vztmpl/$LATEST"
if ! pveam list "$TEMPLATE_STORAGE" | grep -q "$LATEST"; then
  info "Descargando plantilla $LATEST…"
  pveam download "$TEMPLATE_STORAGE" "$LATEST"
fi

# ─────────────  Red  ────────────────────────────────────────────────────────────
NET0="name=eth0,bridge=$BRIDGE"
if [[ -n $STATIC4 ]]; then
  IFS=',' read -r IP4 GW4 DNS4 <<<"$STATIC4"; NET0+=",ip=$IP4,gw=$GW4"
fi
if [[ -n $STATIC6 ]]; then
  IFS=',' read -r IP6 GW6     <<<"$STATIC6"; NET0+=",ip6=$IP6,gw6=$GW6"
fi
[[ -z $STATIC4 ]] && NET0+=",ip=dhcp"

# ─────────────  Crear CT  ──────────────────────────────────────────────────────
info "Creando CT $CTID ($HOSTNAME)…"
pct create "$CTID" "$TEMPLATE" \
  --unprivileged 1 --ostype debian --hostname "$HOSTNAME" \
  --memory "$MEM" --cores "$CORES" --rootfs "$ROOTFS_STORAGE:${DISK}" \
  --net0 "$NET0" --password "$PASSWORD" --features nesting=1 --start 1

ct_exec() { pct exec "$CTID" -- bash -ceu "$*"; }

# ─────────────  Paquetes base + Chrome  ─────────────────────────────────────────
info "Instalando paquetes base y Google Chrome…"
ct_exec "apt-get update -qq && \
  apt-get install -y --no-install-recommends \
  sudo git curl wget unzip supervisor xvfb x11vnc tigervnc-tools websockify \
  python3 python3-venv python3-pip fonts-liberation \
  libgtk-3-0 libnss3 libxss1 libasound2 libgbm1 libatk-bridge2.0-0 gnupg -qq"

ct_exec "wget -qO- https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor >/usr/share/keyrings/google-linux-signing-keyring.gpg"
ct_exec "echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/google-linux-signing-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main' > /etc/apt/sources.list.d/google-chrome.list"
ct_exec "apt-get update -qq && apt-get install -y google-chrome-stable -qq"

# ─────────────  Usuario de la app  ─────────────────────────────────────────────
info "Creando usuario $USERNAME…"
ct_exec "useradd -m -s /bin/bash $USERNAME"
ct_exec "echo '$USERNAME:$PASSWORD' | chpasswd"
ct_exec "adduser $USERNAME sudo"

# ─────────────  Playwright & Web-UI  ────────────────────────────────────────────
info "Preparando directorio de browsers Playwright…"
ct_exec "mkdir -p /ms-playwright && chown $USERNAME:$USERNAME /ms-playwright"

info "Clonando browser-use/web-ui…"
ct_exec "sudo -u $USERNAME -H bash -c '
  cd ~ &&
  git clone https://github.com/browser-use/web-ui.git web-ui &&
  cd web-ui &&
  python3 -m venv venv &&
  . venv/bin/activate &&
  pip install --upgrade pip -q &&
  pip install -r requirements.txt -q &&
  PLAYWRIGHT_BROWSERS_PATH=/ms-playwright playwright install --force chrome
'"

# ─────────────  Ajustar rutas tmp→data  ────────────────────────────────────────
info "Ajustando carpetas por defecto…"
ct_exec "sudo -u $USERNAME mkdir -p /home/$USERNAME/web-ui/data"
ct_exec "sudo -u $USERNAME bash -c '
  cd /home/$USERNAME/web-ui &&
  find src -type f -name \"*.py\" -exec sed -i \"s|./tmp/|./data/|g\" {} +
'"

# ─────────────  noVNC & resoluciones  ──────────────────────────────────────────
info "Clonando noVNC…"
ct_exec "sudo -u $USERNAME -H git clone https://github.com/novnc/noVNC.git /home/$USERNAME/web-ui/noVNC"

info "Parchando resolución por defecto…"
ct_exec "sudo -u $USERNAME sed -i 's/value=1280/value=1920/' /home/$USERNAME/web-ui/src/webui/components/browser_settings_tab.py"
ct_exec "sudo -u $USERNAME sed -i 's/value=1100/value=1080/' /home/$USERNAME/web-ui/src/webui/components/browser_settings_tab.py"

# ─────────────  .env  ───────────────────────────────────────────────────────────
info "Generando .env…"
ct_exec "cat > /home/$USERNAME/web-ui/.env <<EOF
OPENAI_API_KEY=$API_OPENAI
GOOGLE_API_KEY=$API_GOOGLE
ANTHROPIC_API_KEY=$API_ANTHROPIC
EOF
chown $USERNAME:$USERNAME /home/$USERNAME/web-ui/.env"

# ─────────────  Supervisor  ────────────────────────────────────────────────────
info "Creando servicio supervisor…"
ct_exec "cat > /etc/supervisor/conf.d/web-ui.conf <<'EOF'
[program:xvfb]
command=/usr/bin/Xvfb :0 -screen 0 1920x1080x24
autorestart=true
priority=10

[program:x11vnc]
command=/usr/bin/x11vnc -display :0 -forever -passwd ${PASSWORD}
autorestart=true
priority=20

[program:web-ui]
directory=/home/${USERNAME}/web-ui
command=/home/${USERNAME}/web-ui/venv/bin/python -m fastchat.serve.controller
user=${USERNAME}
environment=DISPLAY=:0
autorestart=true
priority=30

[program:websockify]
command=/usr/bin/websockify --web=/home/${USERNAME}/web-ui/noVNC 6080 localhost:5900
autorestart=true
priority=40
EOF"

info "Recargando Supervisor…"
ct_exec "supervisorctl reread && supervisorctl update"

# ─────────────  Listo  ─────────────────────────────────────────────────────────
info "✔ Instalación terminada.
   - Web-UI      : http://<IP-del-CT>:7860
   - noVNC (VNC) : http://<IP-del-CT>:6080  (pass VNC: ${PASSWORD})"

exit 0
