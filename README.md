# Browser-Use-Web-UI-LXC
Despliega **browser-use/web-ui** en un contenedor LXC *no privilegiado* Debian 12 sobre Proxmox VE  con un solo comando.


## 🚀 Instalación rápida

```bash
bash <(curl -sL https://raw.githubusercontent.com/Transcendenceia/Browser-Use-Web-UI-LXC/main/create-webui-lxc.sh)

```
Acepta los valores por defecto o personalízalos cuando el script te los pregunte.

## Modo silencioso:
```bash
bash <(curl -sL https://raw.githubusercontent.com/Transcendenceia/Browser-Use-Web-UI-LXC/main/create-webui-lxc.sh) -q

```
## Parámetros frecuentes:
| Flag | Descripción                      | Ejemplo                                  |
| ---- | -------------------------------- | ---------------------------------------- |
| `-c` | CTID explícito                   | `-c 105`                                 |
| `-i` | Bridge de red                    | `-i vmbr1`                               |
| `-p` | Contraseña root/VNC              | `-p MiClave123`                          |
| `-k` | API Keys (coma-separadas)        | `-k OPENAI=sk-XXX,GOOGLE=AIYYY`          |
| `-4` | IPv4 estática (`ip/mask,gw,dns`) | `-4 192.168.1.50/24,192.168.1.1,1.1.1.1` |
| `-6` | IPv6 estática (`ip/prefix,gw`)   | `-6 2001:db8::50/64,2001:db8::1`         |

### Al finalizar verás algo como:
```
✅  Browser-Use Web UI deployed!
   • Gradio : http://192.168.1.37:7788
   • noVNC  : http://192.168.1.37:6080/vnc.html
   • VNC pwd: vncpassword
   • CTID   : 105 (web-ui)
```
## Modificar variables de entorno dentro del contenedor
Entra al contenedor que se creo despues de la instalacion, con usuario root y la contraseña que definiste en la instalacion y ejecuta este comando:
```bash
nano /opt/web-ui/.env
```
Aqui podras agregar o modificar las variables que hagan falta.

## 🔄 Actualización
Dentro del nodo Proxmox:
```bash
bash <(curl -sL https://raw.githubusercontent.com/Transcendenceia/Browser-Use-Web-UI-LXC/main/update-webui.sh)

```
## Proyecto Original
<https://github.com/browser-use/web-ui>
