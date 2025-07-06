#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s inherit_errexit 2>/dev/null || true

C_RED='\e[31m'; C_CYAN='\e[36m'; C_GRN='\e[32m'; C_RST='\e[0m'
info(){ echo -e "${C_CYAN}➤ $*${C_RST}"; }
die(){  echo -e "${C_RED}✘ $*${C_RST}" >&2; exit 1; }
ask(){ local __var=$1 __def=$2 __q=$3; read -rp "$__q [$__def]: " _v; printf -v "$__var" '%s' "${_v:-$__def}"; }

CTID=$(pvesh get /cluster/nextid)
HOSTNAME="web-ui"
USERNAME="webui"
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
while getopts "qc:n:s:r:d:t:f:i:p:u:4:6:k:h" opt; do
  case $opt in
    q) QUIET=1;;
    c) CTID=$OPTARG;;
    s) CORES=$OPTARG;;
    r) MEM=$OPTARG;;
    d) DISK=$OPTARG;;
    t) TEMPLATE_STORAGE=$OPTARG;;
    f) ROOTFS_STORAGE=$OPTARG;;
    i) BRIDGE=$OPTARG;;
    p) PASSWORD=$OPTARG;;
    u) USERNAME=$OPTARG;;
    4) STATIC4=$OPTARG;;
    6) STATIC6=$OPTARG;;
    k) IFS=',' read -ra KVS <<<"$OPTARG"; for kv in "${KVS[@]}"; do
         case $kv in
           OPENAI=*)    API_OPENAI=${kv#OPENAI=}    ;;
           GOOGLE=*)    API_GOOGLE=${kv#GOOGLE=}    ;;
           ANTHROPIC=*) API_ANTHROPIC=${kv#ANTHROPIC=} ;;
         esac
       done;;
    h) usage;;
    *) usage;;
  esac
done
shift $((OPTIND-1))

if (( QUIET==0 )); then
  ask CTID        "$CTID"        "CTID"
  ask CORES       "$CORES"       "vCPUs"
  ask MEM         "$MEM"         "RAM MB"
  ask DISK        "$DISK"        "Disk GB"
  ask TEMPLATE_STORAGE "$TEMPLATE_STORAGE" "Template storage"
  ask ROOTFS_STORAGE  "$ROOTFS_STORAGE"  "RootFS storage"
  ask BRIDGE      "$BRIDGE"      "Bridge"
  read -rsp "Root/VNC password [hidden, default '$PASSWORD']: " pw; echo
  [[ -n $pw ]] && PASSWORD=$pw
  ask USERNAME    "$USERNAME"    "Username"
  ask STATIC4     "$STATIC4"     "Static IPv4 (ip/mask,gw,dns)"
  ask STATIC6     "$STATIC6"     "Static IPv6 (ip/prefix,gw)"
  ask API_OPENAI      "$API_OPENAI"      "OpenAI API key"
  ask API_GOOGLE      "$API_GOOGLE"      "Google API key"
  ask API_ANTHROPIC   "$API_ANTHROPIC"   "Anthropic API key"
  echo
  info "Summary ➜ CT $CTID • $CORES CPU • $MEM MB • ${DISK}G • $BRIDGE • user=$USERNAME"
  read -rp "Continue? [Y/n] " yn
  [[ ${yn:-Y} =~ ^[Yy]$ ]] || { echo "Aborted"; exit 0; }
fi

LATEST=$(pveam available | awk '/debian-12-standard_.*amd64/ {print $2}' | sort -Vr | head -n1)
[[ -n $LATEST ]] || die "No Debian 12 template found in pveam."
TEMPLATE="$TEMPLATE_STORAGE:vztmpl/$LATEST"
if ! pveam list "$TEMPLATE_STORAGE" | grep -q "$LATEST"; then
  info "Downloading template $LATEST to $TEMPLATE_STORAGE…"
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

info "Creating CT $CTID ($HOSTNAME)…"
pct create "$CTID" "$TEMPLATE" \
  --unprivileged 1 --ostype debian --hostname "$HOSTNAME" \
  --memory "$MEM" --cores "$CORES" --rootfs "$ROOTFS_STORAGE:${DISK}" \
  --net0 "$NET0" --password "$PASSWORD" --features nesting=1 --start 1

ct_exec(){ pct exec "$CTID" -- bash -ceu "$*"; }

info "Installing base packages and Google Chrome…"
ct_exec "apt-get update -qq && apt-get install -y --no-install-recommends sudo git curl wget unzip supervisor xvfb x11vnc tigervnc-tools websockify openbox procps python3 python3-venv python3-pip fonts-liberation libgtk-3-0 libnss3 libxss1 libasound2 libgbm1 libatk-bridge2.0-0 gnupg google-chrome-stable -qq"

info "Creating user $USERNAME…"
ct_exec "useradd -m -s /bin/bash $USERNAME"
ct_exec "echo '$USERNAME:$PASSWORD' | chpasswd"
ct_exec "adduser $USERNAME sudo"

# No necesitamos /ms-playwright ni descargar otro Chrome
info "Cloning browser-use/web-ui…"
ct_exec "sudo -u $USERNAME -H bash -c 'cd ~ && git clone https://github.com/browser-use/web-ui.git web-ui && cd web-ui && python3 -m venv venv && . venv/bin/activate && pip install --upgrade pip -q && pip install -r requirements.txt -q'"

info "Adjusting default directories…"
ct_exec "sudo -u $USERNAME mkdir -p /home/$USERNAME/web-ui/data"
ct_exec "sudo -u $USERNAME bash -c 'cd /home/$USERNAME/web-ui && find src -type f -name \"*.py\" -exec sed -i \"s|./tmp/|./data/|g\" {} +'"

info "Cloning noVNC…"
ct_exec "sudo -u $USERNAME -H git clone https://github.com/novnc/noVNC.git /home/$USERNAME/web-ui/noVNC"

info "Patching default resolution…"
ct_exec "sudo -u $USERNAME sed -i 's/value=1280/value=1920/' /home/$USERNAME/web-ui/src/webui/components/browser_settings_tab.py"
ct_exec "sudo -u $USERNAME sed -i 's/value=1100/value=1080/' /home/$USERNAME/web-ui/src/webui/components/browser_settings_tab.py"

info "Generating .env…"
ct_exec "cat > /home/$USERNAME/web-ui/.env <<EOFINNER
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
CHROME_USER_DATA=/home/$USERNAME/chrome_data
CHROME_DEBUGGING_PORT=9222
CHROME_DEBUGGING_HOST=0.0.0.0
CHROME_PERSISTENT_SESSION=true

RESOLUTION=1920x1080x24
RESOLUTION_WIDTH=1920
RESOLUTION_HEIGHT=1080

VNCPASSWORD=$PASSWORD
EOFINNER"

info "Setting permissions…"
ct_exec "chown -R $USERNAME:$USERNAME /home/$USERNAME/web-ui"

info "Creating Supervisor programs…"
ct_exec "cat > /etc/supervisor/conf.d/web-ui.conf <<EOFINNER
[program:xvfb]
command=/usr/bin/Xvfb :1 -screen 0 1920x1080x24
autostart=true
autorestart=true

[program:openbox]
command=/usr/bin/openbox-session
environment=DISPLAY=\":1\"
user=$USERNAME
autostart=true
autorestart=true

[program:chrome]
command=/usr/bin/google-chrome --no-sandbox --no-first-run --disable-features=Translate --disable-translate --disable-infobars --remote-debugging-port=9222 --remote-debugging-address=0.0.0.0 --user-data-dir=/home/$USERNAME/chrome_data http://google.com
environment=DISPLAY=\":1\"
user=$USERNAME
autostart=true
autorestart=true

[program:x11vnc]
command=/usr/bin/x11vnc -display :1 -rfbport 5901 -nopw -forever -passwd $PASSWORD
autostart=true
autorestart=true

[program:novnc]
command=/usr/bin/websockify --web=/home/$USERNAME/web-ui/noVNC 6080 localhost:5901
directory=/home/$USERNAME/web-ui
autostart=true
autorestart=true

[program:webui]
command=/home/$USERNAME/web-ui/venv/bin/python /home/$USERNAME/web-ui/webui.py --ip 0.0.0.0 --port 7788
directory=/home/$USERNAME/web-ui
environment=DISPLAY=\":1\"
user=$USERNAME
autostart=true
autorestart=true
EOFINNER"

ct_exec "grep -q '\\[unix_http_server\\]' /etc/supervisor/supervisord.conf || cat >> /etc/supervisor/supervisord.conf <<EOFINNER
[unix_http_server]
file=/var/run/supervisor.sock

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///var/run/supervisor.sock
EOFINNER"

ct_exec "systemctl enable --now supervisor"
ct_exec "sleep 2 && supervisorctl reread && supervisorctl update"

IP=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')
cat <<EOFINNER

✅  Browser-Use Web UI deployed!
   • Gradio : http://$IP:7788
   • noVNC  : http://$IP:6080/vnc.html
   • VNC pwd: $PASSWORD
   • User   : $USERNAME
   • CTID   : $CTID ($HOSTNAME)
EOFINNER
