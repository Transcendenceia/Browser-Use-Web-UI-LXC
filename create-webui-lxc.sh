#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s inherit_errexit 2>/dev/null || true

C_RED='\e[31m'; C_CYAN='\e[36m'; C_GRN='\e[32m'; C_RST='\e[0m'
info(){ echo -e "${C_CYAN}➤ $*${C_RST}"; }
die(){  echo -e "${C_RED}✘ $*${C_RST}" >&2; exit 1; }
ask(){ local __var=$1 __def=$2 __q=$3; read -rp "$__q [$__def]: " _v; printf -v "$__var" '%s' "${_v:-$__def}"; }

CTID=$(pvesh get /cluster/nextid)
HOSTNAME="web-ui"
CORES=4
MEM=4096
DISK=20
TEMPLATE_STORAGE="local"
ROOTFS_STORAGE="local-lvm"
BRIDGE="vmbr0"
PASSWORD="vncpassword"
STATIC4=""
STATIC6=""
API_OPENAI=""
API_GOOGLE=""
API_ANTHROPIC=""
QUIET=0

usage(){ grep -E "^# " "$0" | cut -c5-; exit 0; }
while getopts "qc:n:s:r:d:t:f:i:p:4:6:k:h" opt; do
  case $opt in
    q) QUIET=1;;
    c) CTID=$OPTARG;;
   # n) HOSTNAME=$OPTARG;;
    s) CORES=$OPTARG;;
    r) MEM=$OPTARG;;
    d) DISK=$OPTARG;;
    t) TEMPLATE_STORAGE=$OPTARG;;
    f) ROOTFS_STORAGE=$OPTARG;;
    i) BRIDGE=$OPTARG;;
    p) PASSWORD=$OPTARG;;
    4) STATIC4=$OPTARG;;
    6) STATIC6=$OPTARG;;
    k) IFS=',' read -ra KVS <<<"$OPTARG"; for kv in "${KVS[@]}"; do
         case $kv in
           OPENAI=*)      API_OPENAI=${kv#OPENAI=}      ;;
           GOOGLE=*)      API_GOOGLE=${kv#GOOGLE=}      ;;
           ANTHROPIC=*)   API_ANTHROPIC=${kv#ANTHROPIC=} ;;
         esac
       done;;
    h) usage;;
    *) usage;;
  esac
done
shift $((OPTIND-1))

if (( QUIET==0 )); then
  ask CTID        "$CTID"        "CTID"
  #ask HOSTNAME    "$HOSTNAME"    "Hostname"
  ask CORES       "$CORES"       "vCPUs"
  ask MEM         "$MEM"         "RAM MB"
  ask DISK        "$DISK"        "Disk GB"
  ask TEMPLATE_STORAGE "$TEMPLATE_STORAGE" "Template storage"
  ask ROOTFS_STORAGE  "$ROOTFS_STORAGE"  "RootFS storage"
  ask BRIDGE      "$BRIDGE"      "Bridge"
  read -rsp "Root/VNC password [hidden, default '$PASSWORD']: " pw; echo
  [[ -n $pw ]] && PASSWORD=$pw
  ask STATIC4     "$STATIC4"     "Static IPv4 (ip/mask,gw,dns)"
  ask STATIC6     "$STATIC6"     "Static IPv6 (ip/prefix,gw)"
  ask API_OPENAI      "$API_OPENAI"      "OpenAI API key"
  ask API_GOOGLE      "$API_GOOGLE"      "Google API key"
  ask API_ANTHROPIC   "$API_ANTHROPIC"   "Anthropic API key"
  echo
  info "Resumen ➜ CT $CTID • $CORES CPU • $MEM MB • ${DISK}G • $BRIDGE • pw='******'"
  read -rp "¿Continuar? [Y/n] " yn
  [[ ${yn:-Y} =~ ^[Yy]$ ]] || { echo "Abortado"; exit 0; }
fi

LATEST=$(pveam available | awk '/debian-12-standard_.*amd64/ {print $2}' | sort -Vr | head -n1)
[[ -n $LATEST ]] || die "No hay plantilla Debian 12 en pveam."
TEMPLATE="$TEMPLATE_STORAGE:vztmpl/$LATEST"
if ! pveam list "$TEMPLATE_STORAGE" | grep -q "$LATEST"; then
  info "Descargando plantilla $LATEST en $TEMPLATE_STORAGE…"
  pveam download "$TEMPLATE_STORAGE" "$LATEST"
fi

NET0="name=eth0,bridge=$BRIDGE"
if [[ -n $STATIC4 ]]; then
  IFS=',' read -r IP4 GW4 DNS4 <<<"$STATIC4"
  NET0+=",ip=$IP4,gw=$GW4"
fi
if [[ -n $STATIC6 ]]; then
  IFS=',' read -r IP6 GW6 <<<"$STATIC6"
  NET0+=",ip6=$IP6,gw6=$GW6"
fi
[[ -z $STATIC4 ]] && NET0+=",ip=dhcp"

info "Creando CT $CTID ($HOSTNAME)…"
pct create "$CTID" "$TEMPLATE" \
  --unprivileged 1 --ostype debian --hostname "$HOSTNAME" \
  --memory "$MEM" --cores "$CORES" --rootfs "$ROOTFS_STORAGE:${DISK}" \
  --net0 "$NET0" --password "$PASSWORD" --features nesting=1 --start 1

ct_exec(){ pct exec "$CTID" -- bash -ceu "$*"; }

info "Instalando paquetes base…"
ct_exec "apt-get update -qq && apt-get install -y --no-install-recommends \
  git curl wget unzip supervisor xvfb x11vnc tigervnc-tools websockify \
  python3 python3-venv python3-pip fonts-liberation libgtk-3-0 libnss3 \
  libxss1 libasound2 libgbm1 libatk-bridge2.0-0 -qq"

info "Clonando browser-use/web-ui y Playwright…"
ct_exec "cd /opt && git clone https://github.com/browser-use/web-ui.git && \
  cd /opt/web-ui && python3 -m venv venv && . venv/bin/activate && \
  pip install --upgrade pip -q && pip install -r requirements.txt \
  playwright lxml_html_clean -q && \
  PLAYWRIGHT_BROWSERS_PATH=/ms-playwright playwright install chrome"

info "Adjusting default directories…"
ct_exec "mkdir -p /opt/web-ui/data"
ct_exec "find /opt/web-ui/src -type f -name '*.py' -exec sed -i 's|./tmp/|./data/|g' {} +"

ct_exec "git clone https://github.com/novnc/noVNC.git /opt/web-ui/noVNC"

if [[ -n ${DNS4:-} ]]; then
  ct_exec "echo 'nameserver $DNS4' > /etc/resolv.conf"
fi

info "Generando .env…"
ct_exec "cat > /opt/web-ui/.env <<EOF
OPENAI_ENDPOINT=https://api.openai.com/v1
OPENAI_API_KEY=$API_OPENAI

ANTHROPIC_API_KEY=$API_ANTHROPIC
ANTHROPIC_ENDPOINT=https://api.anthropic.com

GOOGLE_API_KEY=$API_GOOGLE

AZURE_OPENAI_ENDPOINT=
AZURE_OPENAI_API_KEY=

DEEPSEEK_ENDPOINT=https://openrouter.ai/api/v1
DEEPSEEK_API_KEY=

MISTRAL_API_KEY=
MISTRAL_ENDPOINT=https://api.mistral.ai/v1

OLLAMA_ENDPOINT=http://localhost:11434

ANONYMIZED_TELEMETRY=true
BROWSER_USE_LOGGING_LEVEL=info

CHROME_PATH=/usr/bin/google-chrome
CHROME_USER_DATA=/app/data/chrome_data
CHROME_DEBUGGING_PORT=9222
CHROME_DEBUGGING_HOST=localhost
CHROME_PERSISTENT_SESSION=true

RESOLUTION=1920x1080x24
RESOLUTION_WIDTH=1920
RESOLUTION_HEIGHT=1080

VNCPASSWORD=$PASSWORD
EOF"

info "Creando programas de Supervisor…"
ct_exec "cat > /etc/supervisor/conf.d/web-ui.conf <<EOF
[program:xvfb]
command=/usr/bin/Xvfb :1 -screen 0 1920x1080x24
autostart=true
autorestart=true

[program:x11vnc]
command=/usr/bin/x11vnc -display :1 -rfbport 5901 -nopw -forever -passwd $PASSWORD
autostart=true
autorestart=true

[program:novnc]
command=/usr/bin/websockify --web=/opt/web-ui/noVNC 6080 localhost:5901
directory=/opt/web-ui
autostart=true
autorestart=true

[program:webui]
command=/opt/web-ui/venv/bin/python /opt/web-ui/webui.py --ip 0.0.0.0 --port 7788
directory=/opt/web-ui
environment=DISPLAY=\":1\",PLAYWRIGHT_BROWSERS_PATH=\"/ms-playwright\"
autostart=true
autorestart=true
EOF"

ct_exec "grep -q '\[unix_http_server\]' /etc/supervisor/supervisord.conf || cat >> /etc/supervisor/supervisord.conf <<EOF
[unix_http_server]
file=/var/run/supervisor.sock

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///var/run/supervisor.sock
EOF"

ct_exec "systemctl enable --now supervisor"
ct_exec "sleep 2 && supervisorctl reread && supervisorctl update"

IP=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')
cat <<EOF

✅  Browser-Use Web UI deployed!
   • Gradio : http://$IP:7788
   • noVNC  : http://$IP:6080/vnc.html
   • VNC pwd: $PASSWORD
   • CTID   : $CTID ($HOSTNAME)
EOF
