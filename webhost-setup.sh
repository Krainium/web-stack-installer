#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  🌐  webhost-setup  —  Full web stack installer & host toolkit
#  Built by krainium
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ─── Colours ──────────────────────────────────────────────────────────────────
R="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
RED="\033[31m"
GRN="\033[32m"
YLW="\033[33m"
BLU="\033[34m"
MAG="\033[35m"
CYN="\033[36m"
WHT="\033[97m"
BG_BLU="\033[44m"
BG_GRN="\033[42m"

# ─── Logging helpers ──────────────────────────────────────────────────────────
info()    { echo -e "${BLU}${BOLD}  ℹ  ${R}${WHT}$*${R}"; }
ok()      { echo -e "${GRN}${BOLD}  ✔  ${R}${GRN}$*${R}"; }
skip()    { echo -e "${CYN}${BOLD}  ↷  ${R}${CYN}$*  — already installed, skipping${R}"; }
warn()    { echo -e "${YLW}${BOLD}  ⚠  ${R}${YLW}$*${R}"; }
err()     { echo -e "${RED}${BOLD}  ✖  ${R}${RED}$*${R}"; }
step()    { echo -e "\n${CYN}${BOLD}  ▶  $*${R}"; }
divider() { echo -e "${DIM}  ──────────────────────────────────────────────────${R}"; }
installing() { echo -e "${MAG}${BOLD}  ⬇  ${R}${MAG}Installing $*...${R}"; }

# ─── Root check ───────────────────────────────────────────────────────────────
require_root() {
    if [[ "$EUID" -ne 0 ]]; then
        err "This action requires root. Re-run with: sudo $0"
        exit 1
    fi
}

# ─── OS + package manager detection ──────────────────────────────────────────
detect_os() {
    OS="unknown"
    PKG=""
    PKG_UPDATE=""
    PKG_INSTALL=""
    SVC_CMD=""

    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        OS="${ID:-unknown}"
    fi

    if command -v apt-get &>/dev/null; then
        PKG="apt"
        PKG_UPDATE="apt-get update -qq"
        PKG_INSTALL="apt-get install -y -qq"
    elif command -v dnf &>/dev/null; then
        PKG="dnf"
        PKG_UPDATE="dnf check-update -q || true"
        PKG_INSTALL="dnf install -y -q"
    elif command -v yum &>/dev/null; then
        PKG="yum"
        PKG_UPDATE="yum check-update -q || true"
        PKG_INSTALL="yum install -y -q"
    elif command -v pacman &>/dev/null; then
        PKG="pacman"
        PKG_UPDATE="pacman -Sy --noconfirm --quiet"
        PKG_INSTALL="pacman -S --noconfirm --quiet"
    elif command -v apk &>/dev/null; then
        PKG="apk"
        PKG_UPDATE="apk update -q"
        PKG_INSTALL="apk add -q"
    else
        PKG="unknown"
    fi

    if command -v systemctl &>/dev/null; then
        SVC_CMD="systemctl"
    elif command -v service &>/dev/null; then
        SVC_CMD="service"
    fi
}

# ─── Granular dependency checker ─────────────────────────────────────────────
# Usage: is_installed <command>  → returns 0 if found, 1 if not
# Prints nothing — callers decide what to say.
is_installed() {
    command -v "$1" &>/dev/null
}

# get_version <command> <version-args>
# Returns version string or "?" on failure. Never errors out.
get_version() {
    local cmd="$1"; shift
    "$cmd" "$@" 2>/dev/null | head -1 || echo "?"
}

# ─── Service helpers ──────────────────────────────────────────────────────────
svc_enable_start() {
    local svc="$1"
    if [[ "$SVC_CMD" == "systemctl" ]]; then
        systemctl enable "$svc" &>/dev/null || true
        systemctl start  "$svc" &>/dev/null || true
        systemctl is-active --quiet "$svc" \
            && ok "$svc is running" \
            || warn "$svc may not have started — check: systemctl status $svc"
    elif [[ "$SVC_CMD" == "service" ]]; then
        service "$svc" start &>/dev/null || true
        ok "$svc started"
    else
        warn "No service manager found — start $svc manually"
    fi
}

svc_status() {
    local svc="$1"
    if [[ "$SVC_CMD" == "systemctl" ]]; then
        systemctl is-active --quiet "$svc" 2>/dev/null && echo "running" || echo "stopped"
    else
        echo "unknown"
    fi
}

# ─── Firewall helper ─────────────────────────────────────────────────────────
open_port() {
    local port="$1"
    local proto="${2:-tcp}"
    if command -v ufw &>/dev/null; then
        ufw allow "${port}/${proto}" &>/dev/null || true
        ok "ufw: port $port/$proto opened"
    elif command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port="${port}/${proto}" &>/dev/null || true
        firewall-cmd --reload &>/dev/null || true
        ok "firewalld: port $port/$proto opened"
    else
        warn "No firewall manager found — open port $port manually if needed"
    fi
}

# ─── Banner ───────────────────────────────────────────────────────────────────
banner() {
    clear 2>/dev/null || true
    detect_os

    echo ""
    echo -e "${BLU}${BOLD}  ╔══════════════════════════════════════════════════════╗${R}"
    echo -e "${BLU}${BOLD}  ║${WHT}${BOLD}   🌐  webhost-setup  —  Web Stack Installer         ${BLU}${BOLD}║${R}"
    echo -e "${BLU}${BOLD}  ║${DIM}      Installs everything your server needs to go live  ${BLU}${BOLD}║${R}"
    echo -e "${BLU}${BOLD}  ╚══════════════════════════════════════════════════════╝${R}"
    echo ""
    echo -e "  ${DIM}OS: ${OS}  |  Package manager: ${PKG}${R}"
    echo ""
    echo -e "  ${BG_BLU}${WHT}${BOLD}  Component Status  ${R}"
    echo ""

    _badge() {
        local label="$1" cmd="$2" ver_flag="${3:---version}"
        if is_installed "$cmd"; then
            local ver
            ver="$("$cmd" "$ver_flag" 2>&1 | grep -o '[0-9][0-9.]*' | head -1 || echo "?")"
            echo -e "  ${GRN}${BOLD}  ✔  ${R}${GRN}${label}${R}${DIM}  v${ver}${R}"
        else
            echo -e "  ${DIM}  ○  ${label}  —  not installed${R}"
        fi
    }

    _badge "Python 3  " "python3"  "--version"
    _badge "pip3      " "pip3"     "--version"
    _badge "Apache    " "apache2"  "-v"
    _badge "Nginx     " "nginx"    "-v"
    _badge "PHP       " "php"      "--version"
    _badge "MySQL     " "mysql"    "--version"
    _badge "Node.js   " "node"     "--version"
    _badge "npm       " "npm"      "--version"
    _badge "ngrok     " "ngrok"    "version"
    _badge "certbot   " "certbot"  "--version"
    echo ""
    divider
}

# ─── Main menu ────────────────────────────────────────────────────────────────
main_menu() {
    echo ""
    echo -e "  ${WHT}${BOLD}What do you want to install?${R}"
    echo ""
    echo -e "  ${CYN}${BOLD}  1${R}  ${WHT}Install Python 3${R}${DIM}                   (runtime + pip3)${R}"
    echo -e "  ${CYN}${BOLD}  2${R}  ${WHT}Install Apache 2${R}${DIM}                   (HTTP server)${R}"
    echo -e "  ${CYN}${BOLD}  3${R}  ${WHT}Install Nginx${R}${DIM}                      (HTTP server)${R}"
    echo -e "  ${CYN}${BOLD}  4${R}  ${WHT}Install ngrok${R}${DIM}                      (public tunnel)${R}"
    echo -e "  ${CYN}${BOLD}  5${R}  ${WHT}Install PHP + MySQL${R}${DIM}                (LAMP/LEMP stack)${R}"
    echo -e "  ${CYN}${BOLD}  6${R}  ${WHT}Install Node.js + npm${R}${DIM}              (JS runtime)${R}"
    echo -e "  ${CYN}${BOLD}  7${R}  ${WHT}Install Certbot (SSL)${R}${DIM}              (Let's Encrypt)${R}"
    echo -e "  ${MAG}${BOLD}  8${R}  ${WHT}${BOLD}Install EVERYTHING${R}${DIM}                 (full stack — 1-7 in one go)${R}"
    echo ""
    echo -e "  ${YLW}${BOLD}  9${R}  ${WHT}Status dashboard${R}${DIM}                   (check what's running)${R}"
    echo -e "  ${YLW}${BOLD} 10${R}  ${WHT}Deploy a website${R}${DIM}                   (point a domain to a folder)${R}"
    echo -e "  ${YLW}${BOLD} 11${R}  ${WHT}Open ports / firewall${R}${DIM}              (80, 443, 8080, custom)${R}"
    echo ""
    echo -e "  ${RED}${BOLD}  0${R}  ${WHT}Exit${R}"
    echo ""
    divider
    echo -e "  ${CYN}Choice:${R} \c"
    read -r CHOICE
}

# ─────────────────────────────────────────────────────────────────────────────
#  INSTALLERS  — each checks every sub-component before touching the system
# ─────────────────────────────────────────────────────────────────────────────

# ─── 1  Python 3 ──────────────────────────────────────────────────────────────
install_python() {
    require_root
    step "Python 3 + pip3"
    divider

    local need_python=false need_pip=false

    # Check python3
    if is_installed python3; then
        skip "python3  ($(get_version python3 --version))"
    else
        need_python=true
    fi

    # Check pip3 — also covers the case where python3 is installed but pip is missing
    if is_installed pip3; then
        skip "pip3  ($(get_version pip3 --version | awk '{print $2}'))"
    else
        need_pip=true
    fi

    # Nothing to do?
    if [[ "$need_python" == false && "$need_pip" == false ]]; then
        ok "Python 3 and pip3 are both already installed — nothing to do."
        divider
        return
    fi

    info "Updating package index..."
    eval "$PKG_UPDATE"

    if [[ "$need_python" == true ]]; then
        installing "python3"
        case "$PKG" in
            apt)     eval "$PKG_INSTALL python3 python3-pip python3-venv" ;;
            dnf|yum) eval "$PKG_INSTALL python3 python3-pip" ;;
            pacman)  eval "$PKG_INSTALL python python-pip" ;;
            apk)     eval "$PKG_INSTALL python3 py3-pip" ;;
            *)       err "Unknown package manager — install Python 3 manually"; return ;;
        esac
        ok "python3 installed: $(get_version python3 --version)"
        ok "pip3 installed: $(get_version pip3 --version | awk '{print $2}')"

    elif [[ "$need_pip" == true ]]; then
        # python3 exists but pip3 is missing — install pip only
        installing "pip3 only (python3 already present)"
        case "$PKG" in
            apt)     eval "$PKG_INSTALL python3-pip" ;;
            dnf|yum) eval "$PKG_INSTALL python3-pip" ;;
            pacman)  eval "$PKG_INSTALL python-pip" ;;
            apk)     eval "$PKG_INSTALL py3-pip" ;;
            *)
                # Fallback: use ensurepip or get-pip
                python3 -m ensurepip --upgrade 2>/dev/null || \
                    curl -fsSL https://bootstrap.pypa.io/get-pip.py | python3
                ;;
        esac
        ok "pip3 installed: $(get_version pip3 --version | awk '{print $2}')"
    fi

    divider
    ok "Python 3 setup complete."
    info "python3  :  $(get_version python3 --version)"
    info "pip3     :  $(get_version pip3 --version | awk '{print $2}')"
}

# ─── 2  Apache 2 ──────────────────────────────────────────────────────────────
install_apache() {
    require_root
    step "Apache 2"
    divider

    local APACHE_PKG APACHE_SVC
    case "$PKG" in
        apt)     APACHE_PKG="apache2"; APACHE_SVC="apache2" ;;
        dnf|yum) APACHE_PKG="httpd";   APACHE_SVC="httpd"   ;;
        pacman)  APACHE_PKG="apache";  APACHE_SVC="httpd"   ;;
        apk)     APACHE_PKG="apache2"; APACHE_SVC="apache2" ;;
        *)       err "Unknown package manager — install Apache manually"; return ;;
    esac

    if is_installed apache2 || is_installed httpd; then
        local ver
        ver="$(apache2 -v 2>/dev/null | grep -o '[0-9][0-9.]*' | head -1 || \
               httpd -v 2>/dev/null | grep -o '[0-9][0-9.]*' | head -1 || echo "?")"
        skip "Apache  (v${ver})"
    else
        installing "Apache 2"
        eval "$PKG_UPDATE"
        eval "$PKG_INSTALL $APACHE_PKG"
        ok "Apache installed: $(apache2 -v 2>/dev/null | head -1 || httpd -v 2>/dev/null | head -1)"
    fi

    info "Enabling and starting Apache..."
    svc_enable_start "$APACHE_SVC"

    info "Opening ports 80 and 443..."
    open_port 80
    open_port 443

    divider
    ok "Apache is live."
    info "Web root  :  /var/www/html"
    info "Config    :  /etc/apache2/  (or /etc/httpd/)"
    info "Test      :  curl http://localhost"
    info "Logs      :  /var/log/apache2/  (or /var/log/httpd/)"
}

# ─── 3  Nginx ─────────────────────────────────────────────────────────────────
install_nginx() {
    require_root
    step "Nginx"
    divider

    if is_installed nginx; then
        local ver
        ver="$(nginx -v 2>&1 | grep -o '[0-9][0-9.]*' | head -1 || echo "?")"
        skip "Nginx  (v${ver})"
    else
        installing "Nginx"
        eval "$PKG_UPDATE"
        eval "$PKG_INSTALL nginx"
        ok "Nginx installed"
    fi

    info "Enabling and starting Nginx..."
    svc_enable_start "nginx"

    info "Opening ports 80 and 443..."
    open_port 80
    open_port 443

    divider
    ok "Nginx is live."
    info "Web root  :  /var/www/html  (or /usr/share/nginx/html)"
    info "Config    :  /etc/nginx/"
    info "Sites     :  /etc/nginx/sites-available/  (Debian/Ubuntu)"
    info "Test      :  curl http://localhost"
    info "Logs      :  /var/log/nginx/"
}

# ─── 4  ngrok ─────────────────────────────────────────────────────────────────
install_ngrok() {
    step "ngrok"
    divider

    if is_installed ngrok; then
        local ver
        ver="$(ngrok version 2>/dev/null | grep -o '[0-9][0-9.]*' | head -1 || echo "?")"
        skip "ngrok  (v${ver})"
    else
        local ARCH OS_NAME ARCH_TAG
        ARCH="$(uname -m)"
        OS_NAME="$(uname -s | tr '[:upper:]' '[:lower:]')"

        case "$ARCH" in
            x86_64)        ARCH_TAG="amd64"  ;;
            aarch64|arm64) ARCH_TAG="arm64"  ;;
            armv7*)        ARCH_TAG="arm"    ;;
            *)             err "Unsupported arch: $ARCH"; return ;;
        esac

        installing "ngrok (${OS_NAME}/${ARCH_TAG})"
        local TMP
        TMP="$(mktemp -d)"
        local URL="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-${OS_NAME}-${ARCH_TAG}.tgz"

        if is_installed curl; then
            curl -fsSL "$URL" -o "${TMP}/ngrok.tgz"
        else
            wget -q "$URL" -O "${TMP}/ngrok.tgz"
        fi

        tar -xzf "${TMP}/ngrok.tgz" -C "$TMP"

        local INSTALL_DIR
        if [[ "$EUID" -eq 0 ]]; then
            INSTALL_DIR="/usr/local/bin"
        else
            INSTALL_DIR="${HOME}/.local/bin"
            mkdir -p "$INSTALL_DIR"
            export PATH="${INSTALL_DIR}:${PATH}"
        fi

        mv "${TMP}/ngrok" "${INSTALL_DIR}/ngrok"
        chmod +x "${INSTALL_DIR}/ngrok"
        rm -rf "$TMP"

        ok "ngrok installed: $(ngrok version 2>/dev/null | head -1)"
    fi

    divider
    echo -e "  ${YLW}${BOLD}ngrok requires a free auth token to open tunnels.${R}"
    echo -e "  ${DIM}  Get one at: https://dashboard.ngrok.com/authtokens${R}"
    echo ""
    echo -e "  ${CYN}  Paste your auth token (or Enter to skip):${R} \c"
    read -r NGROK_TOKEN
    NGROK_TOKEN="${NGROK_TOKEN// /}"

    if [[ -n "$NGROK_TOKEN" ]]; then
        ngrok config add-authtoken "$NGROK_TOKEN" &>/dev/null \
            && ok "Auth token saved." \
            || warn "Token save failed — run: ngrok config add-authtoken <token>"
    else
        warn "Skipped. Run later: ngrok config add-authtoken <your_token>"
    fi

    divider
    ok "ngrok ready."
    info "Expose port 80  :  ngrok http 80"
    info "Web dashboard   :  http://127.0.0.1:4040  (while tunnel is open)"
}

# ─── 5  PHP + MySQL ───────────────────────────────────────────────────────────
install_php_mysql() {
    require_root
    step "PHP + MySQL / MariaDB"
    divider

    local need_php=false need_db=false

    # Check PHP
    if is_installed php; then
        skip "PHP  ($(get_version php --version | awk '{print $1,$2}'))"
    else
        need_php=true
    fi

    # Check MySQL / MariaDB
    if is_installed mysql || is_installed mariadbd; then
        local db_ver
        db_ver="$(mysql --version 2>/dev/null | head -1 || echo "?")"
        skip "MySQL / MariaDB  (${db_ver})"
    else
        need_db=true
    fi

    if [[ "$need_php" == false && "$need_db" == false ]]; then
        ok "PHP and MySQL are both already installed — nothing to do."
        divider
        return
    fi

    info "Updating package index..."
    eval "$PKG_UPDATE"

    if [[ "$need_php" == true ]]; then
        installing "PHP + extensions"
        case "$PKG" in
            apt)
                eval "$PKG_INSTALL php php-fpm php-mysql php-cli php-curl php-mbstring php-xml php-zip"
                ;;
            dnf|yum)
                eval "$PKG_INSTALL php php-fpm php-mysqlnd php-cli php-curl php-mbstring php-xml php-zip"
                ;;
            pacman)
                eval "$PKG_INSTALL php php-fpm"
                ;;
            *)
                warn "Install PHP manually for your OS"
                ;;
        esac
        ok "PHP installed: $(get_version php --version | head -1)"
    fi

    if [[ "$need_db" == true ]]; then
        installing "MariaDB"
        case "$PKG" in
            apt)
                eval "$PKG_INSTALL mariadb-server mariadb-client" || \
                eval "$PKG_INSTALL mysql-server mysql-client" || true
                ;;
            dnf|yum)
                eval "$PKG_INSTALL mariadb-server mariadb" || true
                ;;
            pacman)
                eval "$PKG_INSTALL mariadb"
                ;;
            *)
                warn "Install MySQL/MariaDB manually for your OS"
                ;;
        esac

        local DB_SVC
        if systemctl list-units --type=service 2>/dev/null | grep -q "mariadb"; then
            DB_SVC="mariadb"
        else
            DB_SVC="mysql"
        fi
        svc_enable_start "$DB_SVC" || true
        ok "Database service started"
    fi

    divider
    ok "PHP + MySQL setup complete."
    is_installed php   && info "PHP    :  $(get_version php --version | awk '{print $1,$2}')"
    is_installed mysql && info "MySQL  :  $(mysql --version 2>/dev/null | head -1)"
    info "Secure DB  :  mysql_secure_installation"
}

# ─── 6  Node.js + npm ─────────────────────────────────────────────────────────
install_node() {
    require_root
    step "Node.js + npm"
    divider

    local need_node=false need_npm=false

    # Check Node
    if is_installed node; then
        skip "Node.js  ($(get_version node --version))"
    else
        need_node=true
    fi

    # Check npm separately — can be missing even if node exists
    if is_installed npm; then
        skip "npm  ($(get_version npm --version))"
    else
        need_npm=true
    fi

    if [[ "$need_node" == false && "$need_npm" == false ]]; then
        ok "Node.js and npm are both already installed — nothing to do."
    else
        if [[ "$need_node" == true ]]; then
            installing "Node.js LTS + npm"
            case "$PKG" in
                apt)
                    if is_installed curl; then
                        curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - &>/dev/null || true
                    fi
                    eval "$PKG_INSTALL nodejs"
                    ;;
                dnf|yum)
                    if is_installed curl; then
                        curl -fsSL https://rpm.nodesource.com/setup_lts.x | bash - &>/dev/null || true
                    fi
                    eval "$PKG_INSTALL nodejs"
                    ;;
                pacman) eval "$PKG_INSTALL nodejs npm" ;;
                apk)    eval "$PKG_INSTALL nodejs npm" ;;
                *)
                    warn "Unknown package manager — visit https://nodejs.org to install manually"
                    return
                    ;;
            esac
            ok "Node.js installed: $(get_version node --version)"

        elif [[ "$need_npm" == true ]]; then
            # node exists but npm is missing
            installing "npm only (Node.js already present)"
            case "$PKG" in
                apt)     eval "$PKG_INSTALL npm" ;;
                dnf|yum) eval "$PKG_INSTALL npm" ;;
                pacman)  eval "$PKG_INSTALL npm" ;;
                apk)     eval "$PKG_INSTALL npm" ;;
                *)       warn "Install npm manually" ;;
            esac
        fi
        ok "npm: $(get_version npm --version)"
    fi

    # PM2 — check before asking
    echo ""
    if is_installed pm2; then
        skip "PM2  ($(pm2 --version 2>/dev/null | tail -1))"
    else
        echo -e "  ${CYN}Install PM2 process manager? [Y/n]:${R} \c"
        read -r install_pm2
        if [[ "${install_pm2:-Y}" =~ ^[Yy]$ ]]; then
            npm install -g pm2 &>/dev/null \
                && ok "PM2 installed: $(pm2 --version 2>/dev/null | tail -1)" \
                || warn "PM2 install failed — try: npm install -g pm2"
        fi
    fi

    divider
    ok "Node.js setup complete."
    is_installed node && info "Node  :  $(get_version node --version)"
    is_installed npm  && info "npm   :  $(get_version npm --version)"
    info "Run app  :  node app.js"
    info "With PM2 :  pm2 start app.js --name myapp"
}

# ─── 7  Certbot ───────────────────────────────────────────────────────────────
install_certbot() {
    require_root
    step "Certbot (Let's Encrypt SSL)"
    divider

    if is_installed certbot; then
        skip "certbot  ($(get_version certbot --version))"
        divider
    else
        installing "Certbot"
        eval "$PKG_UPDATE"
        case "$PKG" in
            apt)
                eval "$PKG_INSTALL certbot"
                is_installed apache2 && eval "$PKG_INSTALL python3-certbot-apache" || true
                is_installed nginx   && eval "$PKG_INSTALL python3-certbot-nginx"  || true
                ;;
            dnf|yum)
                eval "$PKG_INSTALL certbot"
                is_installed httpd && eval "$PKG_INSTALL python3-certbot-apache" || true
                is_installed nginx && eval "$PKG_INSTALL python3-certbot-nginx"  || true
                ;;
            pacman) eval "$PKG_INSTALL certbot" ;;
            *)
                warn "Install certbot manually: https://certbot.eff.org"
                return
                ;;
        esac
        ok "Certbot installed: $(get_version certbot --version)"
        divider
    fi

    ok "Certbot ready."
    info "Apache SSL   :  certbot --apache -d yourdomain.com"
    info "Nginx SSL    :  certbot --nginx -d yourdomain.com"
    info "Standalone   :  certbot certonly --standalone -d yourdomain.com"
    info "Auto-renew   :  certbot renew --dry-run"
    warn "You need a real domain with port 80 open for Let's Encrypt to issue a cert"
}

# ─── 8  Install Everything ────────────────────────────────────────────────────
install_all() {
    require_root
    echo ""
    echo -e "  ${MAG}${BOLD}  🚀  Running full stack install...${R}"
    echo -e "  ${DIM}  Each component is checked first — already-installed ones are skipped.${R}"
    divider

    install_python
    install_apache
    install_nginx
    install_php_mysql
    install_node
    install_certbot
    install_ngrok

    echo ""
    echo -e "${BG_GRN}${BOLD}  ✅  Full stack complete!  ${R}"
    echo ""
    status_dashboard
}

# ─── 9  Status dashboard ─────────────────────────────────────────────────────
status_dashboard() {
    detect_os
    echo ""
    echo -e "  ${BG_BLU}${WHT}${BOLD}  System Status  ${R}"
    divider

    _chk() {
        local label="$1" cmd="$2"; shift 2
        if is_installed "$cmd"; then
            local ver
            ver="$("$cmd" "$@" 2>&1 | head -1 || echo "?")"
            echo -e "  ${GRN}${BOLD}  ✔  ${R}${GRN}${label}${R}${DIM}  ${ver}${R}"
        else
            echo -e "  ${RED}  ✖  ${label}${R}${DIM}  not installed${R}"
        fi
    }

    _svc() {
        local label="$1" svc="$2"
        local state; state="$(svc_status "$svc")"
        if [[ "$state" == "running" ]]; then
            echo -e "  ${GRN}${BOLD}  ▶  ${R}${GRN}${label}${R}${DIM}  running${R}"
        else
            echo -e "  ${YLW}  ■  ${label}${R}${DIM}  ${state}${R}"
        fi
    }

    echo ""
    echo -e "  ${WHT}${BOLD}Installed:${R}"
    _chk "Python 3 " "python3" "--version"
    _chk "pip3     " "pip3"    "--version"
    _chk "Apache   " "apache2" "-v"
    _chk "Nginx    " "nginx"   "-v"
    _chk "PHP      " "php"     "--version"
    _chk "MySQL    " "mysql"   "--version"
    _chk "Node.js  " "node"    "--version"
    _chk "npm      " "npm"     "--version"
    _chk "PM2      " "pm2"     "--version"
    _chk "certbot  " "certbot" "--version"
    _chk "ngrok    " "ngrok"   "version"
    _chk "git      " "git"     "--version"
    _chk "curl     " "curl"    "--version"

    echo ""
    echo -e "  ${WHT}${BOLD}Services:${R}"
    _svc "Apache  " "apache2"
    _svc "Apache  " "httpd"
    _svc "Nginx   " "nginx"
    _svc "MariaDB " "mariadb"
    _svc "MySQL   " "mysql"

    echo ""
    echo -e "  ${WHT}${BOLD}Open ports:${R}"
    if is_installed ss; then
        local ports
        ports="$(ss -tlnp 2>/dev/null | awk 'NR>1 {print $4}' | \
                 grep -o ':[0-9]*$' | tr -d ':' | sort -un | tr '\n' '  ')"
        echo -e "  ${DIM}  ${ports:-none detected}${R}"
    elif is_installed netstat; then
        local ports
        ports="$(netstat -tlnp 2>/dev/null | awk 'NR>2 {print $4}' | \
                 grep -o ':[0-9]*$' | tr -d ':' | sort -un | tr '\n' '  ')"
        echo -e "  ${DIM}  ${ports:-none detected}${R}"
    else
        warn "Install iproute2 or net-tools to see port info"
    fi

    echo ""
    echo -e "  ${WHT}${BOLD}Resources:${R}"
    echo -e "  ${DIM}$(df -h / 2>/dev/null | awk 'NR==2{print "Disk  :  used "$3" of "$2"  ("$5" used)"}')${R}"
    echo -e "  ${DIM}$(free -h 2>/dev/null | awk 'NR==2{print "RAM   :  used "$3" of "$2}')${R}"
    divider
}

# ─── 10  Deploy a website ─────────────────────────────────────────────────────
deploy_site() {
    echo ""
    echo -e "  ${MAG}${BOLD}  🚀  Deploy a Website${R}"
    divider

    local SERVER=""
    if is_installed nginx && [[ "$(svc_status nginx)" == "running" ]]; then
        SERVER="nginx"
    elif is_installed apache2 && [[ "$(svc_status apache2)" == "running" ]]; then
        SERVER="apache2"
    elif is_installed httpd && [[ "$(svc_status httpd)" == "running" ]]; then
        SERVER="apache2"
    fi

    if [[ -z "$SERVER" ]]; then
        warn "No running web server found. Install Apache (2) or Nginx (3) first."
        return
    fi

    ok "Web server detected: $SERVER"
    echo ""
    echo -e "  ${CYN}Domain name (Enter for localhost):${R} \c"
    read -r DOMAIN
    DOMAIN="${DOMAIN:-localhost}"

    echo -e "  ${CYN}Full path to your website folder:${R} \c"
    read -r SITE_ROOT
    SITE_ROOT="${SITE_ROOT/#\~/$HOME}"

    if [[ ! -d "$SITE_ROOT" ]]; then
        warn "Directory not found: $SITE_ROOT"
        echo -e "  ${CYN}Create it with a test page? [Y/n]:${R} \c"
        read -r mk
        if [[ "${mk:-Y}" =~ ^[Yy]$ ]]; then
            mkdir -p "$SITE_ROOT"
            cat > "${SITE_ROOT}/index.html" << HTML
<!DOCTYPE html>
<html>
<head><title>${DOMAIN}</title></head>
<body style="font-family:sans-serif;text-align:center;padding:4em;">
  <h1>${DOMAIN} is live!</h1>
  <p>Replace this file with your website.</p>
</body>
</html>
HTML
            ok "Created $SITE_ROOT with a test index.html"
        else
            return
        fi
    fi

    require_root
    SITE_ROOT="$(cd "$SITE_ROOT" && pwd)"

    if [[ "$SERVER" == "nginx" ]]; then
        local CONF="/etc/nginx/sites-available/${DOMAIN}"
        cat > "$CONF" << CONF
server {
    listen 80;
    server_name ${DOMAIN} www.${DOMAIN};
    root ${SITE_ROOT};
    index index.html index.htm index.php;
    location / { try_files \$uri \$uri/ =404; }
    access_log /var/log/nginx/${DOMAIN}.access.log;
    error_log  /var/log/nginx/${DOMAIN}.error.log;
}
CONF
        ln -sf "$CONF" "/etc/nginx/sites-enabled/${DOMAIN}" 2>/dev/null || true
        nginx -t &>/dev/null \
            && systemctl reload nginx \
            && ok "Nginx configured and reloaded" \
            || err "Nginx config test failed — check /etc/nginx/sites-available/${DOMAIN}"

    else
        local CONF_DIR="/etc/apache2/sites-available"
        [[ -d /etc/httpd/conf.d ]] && CONF_DIR="/etc/httpd/conf.d"
        local CONF="${CONF_DIR}/${DOMAIN}.conf"
        cat > "$CONF" << CONF
<VirtualHost *:80>
    ServerName ${DOMAIN}
    ServerAlias www.${DOMAIN}
    DocumentRoot ${SITE_ROOT}
    <Directory ${SITE_ROOT}>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog  /var/log/apache2/${DOMAIN}.error.log
    CustomLog /var/log/apache2/${DOMAIN}.access.log combined
</VirtualHost>
CONF
        if is_installed a2ensite; then
            a2ensite "${DOMAIN}" &>/dev/null || true
            a2enmod rewrite &>/dev/null || true
            systemctl reload apache2 && ok "Apache configured and reloaded"
        else
            systemctl reload httpd && ok "httpd configured and reloaded"
        fi
    fi

    divider
    ok "Site deployed."
    info "URL      :  http://${DOMAIN}"
    info "Root     :  ${SITE_ROOT}"
    info "Add SSL  :  certbot --${SERVER} -d ${DOMAIN}"
    warn "Point your domain's DNS A record to this server's IP if using a real domain"
}

# ─── 11  Firewall / port manager ─────────────────────────────────────────────
manage_firewall() {
    require_root
    echo ""
    echo -e "  ${YLW}${BOLD}  🔥  Firewall / Port Manager${R}"
    divider

    echo -e "  ${CYN}  1${R}  Open port 80   (HTTP)"
    echo -e "  ${CYN}  2${R}  Open port 443  (HTTPS)"
    echo -e "  ${CYN}  3${R}  Open port 22   (SSH)"
    echo -e "  ${CYN}  4${R}  Open port 8080 (dev / alt HTTP)"
    echo -e "  ${CYN}  5${R}  Open port 3000 (Node.js default)"
    echo -e "  ${CYN}  6${R}  Open a custom port"
    echo -e "  ${CYN}  7${R}  Show current rules"
    echo ""
    echo -e "  ${CYN}Choice:${R} \c"
    read -r FW_CHOICE

    case "$FW_CHOICE" in
        1) open_port 80   ;;
        2) open_port 443  ;;
        3) open_port 22   ;;
        4) open_port 8080 ;;
        5) open_port 3000 ;;
        6)
            echo -e "  ${CYN}Port number:${R} \c"
            read -r CPORT
            open_port "$CPORT"
            ;;
        7)
            if is_installed ufw; then
                ufw status verbose
            elif is_installed firewall-cmd; then
                firewall-cmd --list-all
            elif is_installed iptables; then
                iptables -L -n
            else
                warn "No firewall manager found"
            fi
            ;;
        *) warn "Invalid choice" ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
#  MAIN LOOP
# ─────────────────────────────────────────────────────────────────────────────
detect_os

while true; do
    banner
    main_menu

    case "$CHOICE" in
        1)  install_python    ;;
        2)  install_apache    ;;
        3)  install_nginx     ;;
        4)  install_ngrok     ;;
        5)  install_php_mysql ;;
        6)  install_node      ;;
        7)  install_certbot   ;;
        8)  install_all       ;;
        9)  status_dashboard  ;;
        10) deploy_site       ;;
        11) manage_firewall   ;;
        0)
            echo ""
            echo -e "${GRN}${BOLD}  ✅  Done. Your server is ready.${R}"
            echo ""
            exit 0
            ;;
        *)
            err "Invalid choice — pick 0–11"
            ;;
    esac

    echo ""
    echo -e "  ${DIM}Press Enter to return to the menu...${R}"
    read -r
done
