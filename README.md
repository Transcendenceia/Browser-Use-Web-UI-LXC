# Browser-Use-Web-UI-LXC

Deploy **browser-use/web-ui** in an unprivileged Debian 12 LXC container on Proxmox VE with a single command.

## 🚀 Quick Installation

```bash
bash <(curl -sL https://raw.githubusercontent.com/Transcendenceia/Browser-Use-Web-UI-LXC/main/create-webui-user-lxc.sh)
```

Accept the default values or customize them when the script prompts you.

### Silent Mode

```bash
bash <(curl -sL https://raw.githubusercontent.com/Transcendenceia/Browser-Use-Web-UI-LXC/main/create-webui-user-lxc.sh) -q
```

## 🔧 Common Parameters

| Flag | Description                    | Example                                  |
| ---- | ------------------------------ | ---------------------------------------- |
| `-c` | Explicit CTID                  | `-c 105`                                 |
| `-i` | Network bridge                 | `-i vmbr1`                               |
| `-p` | Root/VNC password              | `-p MySecretPass`                        |
| `-k` | API keys (comma-separated)     | `-k OPENAI=sk-XXX,GOOGLE=AIYYY`          |
| `-4` | Static IPv4 (`ip/mask,gw,dns`) | `-4 192.168.1.50/24,192.168.1.1,1.1.1.1` |
| `-6` | Static IPv6 (`ip/prefix,gw`)   | `-6 2001:db8::50/64,2001:db8::1`         |

## ✅ Post-Installation

After the script completes, you should see output similar to:

```
✅  Browser-Use Web UI deployed!
   • Gradio : http://192.168.1.37:7788
   • noVNC  : http://192.168.1.37:6080/vnc.html
   • VNC pwd: vncpassword
   • CTID   : 105 (web-ui)
```

### Modify Environment Variables Inside the Container

Enter the container created during installation as `root`, using the password you defined, and run:

```bash
nano /opt/web-ui/.env
```

Here you can add or edit any environment variables required by **browser-use/web-ui**.

## 🔄 Update

On the Proxmox node, run:

```bash
bash <(curl -sL https://raw.githubusercontent.com/Transcendenceia/Browser-Use-Web-UI-LXC/main/update-webui.sh)
```

## 🌐 Original Project

[https://github.com/browser-use/web-ui](https://github.com/browser-use/web-ui)

---

# Browser-Use-Web-UI-LXC (Español)

Despliega **browser-use/web-ui** en un contenedor LXC *no privilegiado* Debian 12 sobre Proxmox VE con un solo comando.

## 🚀 Instalación Rápida

```bash
bash <(curl -sL https://raw.githubusercontent.com/Transcendenceia/Browser-Use-Web-UI-LXC/main/create-webui-user-lxc.sh)
```

Acepta los valores por defecto o personalízalos cuando el script te lo solicite.

### Modo Silencioso

```bash
bash <(curl -sL https://raw.githubusercontent.com/Transcendenceia/Browser-Use-Web-UI-LXC/main/create-webui-user-lxc.sh) -q
```

## 🔧 Parámetros Frecuentes

| Flag | Descripción                      | Ejemplo                                  |
| ---- | -------------------------------- | ---------------------------------------- |
| `-c` | CTID explícito                   | `-c 105`                                 |
| `-i` | Bridge de red                    | `-i vmbr1`                               |
| `-p` | Contraseña root/VNC              | `-p MiClave123`                          |
| `-k` | API Keys (separadas por comas)   | `-k OPENAI=sk-XXX,GOOGLE=AIYYY`          |
| `-4` | IPv4 estática (`ip/mask,gw,dns`) | `-4 192.168.1.50/24,192.168.1.1,1.1.1.1` |
| `-6` | IPv6 estática (`ip/prefix,gw`)   | `-6 2001:db8::50/64,2001:db8::1`         |

## ✅ Post-Instalación

Al finalizar, verás algo como:

```
✅  Browser-Use Web UI deployed!
   • Gradio : http://192.168.1.37:7788
   • noVNC  : http://192.168.1.37:6080/vnc.html
   • VNC pwd: vncpassword
   • CTID   : 105 (web-ui)
```

### Modificar Variables de Entorno dentro del Contenedor

Accede al contenedor con usuario `root` y la contraseña definida durante la instalación y ejecuta:

```bash
nano /opt/web-ui/.env
```

Aquí podrás agregar o modificar las variables de entorno que necesites.

## 🔄 Actualización

En el nodo Proxmox, ejecuta:

```bash
bash <(curl -sL https://raw.githubusercontent.com/Transcendenceia/Browser-Use-Web-UI-LXC/main/update-webui.sh)
```

## 🌐 Proyecto Original

[https://github.com/browser-use/web-ui](https://github.com/browser-use/web-ui)
