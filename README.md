# 🌐 web-stack-installer - Installs everything your server needs to go live


A single bash script that turns any Linux machine or VPS into a fully functional web hosting server. One command, colour-coded menu, installs everything your site needs to go live on the internet.

---

## 🎯 What It Does

Gives you a menu-driven CLI that installs and configures:

| Component | What it is |
|-----------|------------|
| **Python 3** | Runtime + pip |
| **Apache 2** | HTTP server (LAMP stack) |
| **Nginx** | HTTP server (LEMP stack) |
| **PHP + MySQL** | Backend language + database |
| **Node.js + npm** | JavaScript runtime |
| **Certbot** | Free SSL certificates via Let's Encrypt |
| **ngrok** | Instant public tunnel — no domain needed |

Plus built-in tools for:
- 📊 Live **status dashboard** — shows every installed component and running service
- 🚀 **One-command site deploy** — generates an Apache or Nginx virtual host config pointed at any folder
- 🔥 **Firewall manager** — opens common ports (80, 443, 22, 8080, 3000) or any custom port
- 🔍 Auto-detects OS and package manager — works on Ubuntu, Debian, CentOS, Arch, Alpine

---

## 🚀 Usage

```bash
chmod +x webhost-setup.sh
sudo ./webhost-setup.sh
```

You get a colour-coded menu every time:

```
  ╔══════════════════════════════════════════════════════╗
  ║   🌐  webhost-setup  —  Web Stack Installer         ║
  ║      Installs everything your server needs to go live ║
  ╚══════════════════════════════════════════════════════╝

  Component Status

  ✔  Python 3   v3.11.2
  ○  Apache     not installed
  ✔  Nginx      v1.24.0
  ✔  ngrok      v3.38.0

  ──────────────────────────────────────────────────

  What do you want to install?

    1  Install Python 3                (runtime + pip)
    2  Install Apache 2                (HTTP server)
    3  Install Nginx                   (HTTP server)
    4  Install ngrok                   (public tunnel)
    5  Install PHP + MySQL             (LAMP/LEMP stack)
    6  Install Node.js + npm           (JS runtime)
    7  Install Certbot (SSL)           (Let's Encrypt)
    8  Install EVERYTHING              (full stack — 1-7 in one go)

    9  Status dashboard                (check what's running)
   10  Deploy a website                (point a domain to a folder)
   11  Open ports / firewall           (80, 443, 8080, custom)

    0  Exit
```

Pick a number, hit Enter. After each action it drops back to the menu.

---

## 📋 Menu Options

### 1 — Python 3
Installs `python3`, `pip3`, and `venv`. Uses the right package manager for your OS (`apt`, `dnf`, `yum`, `pacman`, `apk`).

### 2 — Apache 2
Installs Apache, enables and starts the service, opens ports 80 and 443 in your firewall. Shows you the web root and config path.

### 3 — Nginx
Installs Nginx, enables and starts the service, opens ports 80 and 443. Shows config and log paths.

### 4 — ngrok
Downloads the right ngrok binary for your CPU (x86_64 / ARM64 / ARMv7), puts it in `/usr/local/bin`, and prompts for your auth token to save it. No manual steps.

### 5 — PHP + MySQL
Installs PHP, PHP-FPM, common PHP extensions (`curl`, `mbstring`, `xml`, `zip`), and MariaDB/MySQL. Starts the database service.

### 6 — Node.js + npm
Installs Node.js LTS via NodeSource. Optionally installs **PM2** for running Node apps in the background as persistent services.

### 7 — Certbot (SSL)
Installs Certbot and the right plugin for whichever web server you're running (Apache or Nginx). Tells you the exact commands to get and renew certificates.

### 8 — Install Everything
Runs all of the above in sequence. One option, full stack — Python, Apache, Nginx, PHP, MySQL, Node, Certbot, ngrok.

### 9 — Status Dashboard
Shows what's installed (with versions), which services are running, which ports are open, and a snapshot of disk + memory usage.

```
  Installed:
  ✔  Python 3    Python 3.11.2
  ✔  Apache      Apache/2.4.57
  ✔  Nginx       nginx/1.24.0
  ✔  PHP         PHP 8.2.7
  ✔  Node.js     v20.11.0
  ✔  ngrok       ngrok version 3.38.0

  Services:
  ▶  Apache    running
  ▶  Nginx     running
  ▶  MariaDB   running

  Open ports:   22 80 443 3306

  Disk: used 4.2G of 40G (11% used)
  RAM:  used 512M of 2.0G
```

### 10 — Deploy a Website
Prompts for a domain name and folder path, then:
- Writes a virtual host config for Apache or Nginx
- Enables the site and reloads the server
- Tells you how to add SSL with Certbot

```
Domain name:       example.com
Website folder:    /var/www/example

→ Config written to /etc/nginx/sites-available/example.com
→ Nginx reloaded
→ Site live at http://example.com
```

### 11 — Firewall / Port Manager
Opens common ports or any custom port using `ufw` or `firewalld`, whichever is present.

---

## 📋 Requirements

| Requirement | Notes |
|-------------|-------|
| **Linux** | Ubuntu, Debian, CentOS, RHEL, Arch, Alpine — any modern distro |
| **Bash 4.0+** | Pre-installed everywhere |
| **sudo / root** | Required for installing packages and configuring services |
| **curl or wget** | For downloading ngrok — present on any VPS |

---

## 💻 OS Support

| OS | Package Manager | Supported |
|----|----------------|-----------|
| Ubuntu / Debian | apt | ✅ |
| CentOS / RHEL / Fedora | dnf / yum | ✅ |
| Arch Linux | pacman | ✅ |
| Alpine Linux | apk | ✅ |
| macOS | — | ⚠️ Partial (ngrok + Node only — no Apache/Nginx via this script on Mac) |

---

## 🔧 Running Without Root

Most install actions need `sudo`. The script checks and tells you exactly when root is required. ngrok can be installed without root — it goes to `~/.local/bin` instead of `/usr/local/bin`.

---

## 🌍 Supported Architectures

| CPU | Supported |
|-----|-----------|
| x86_64 (most VPS and desktops) | ✅ |
| ARM64 (Raspberry Pi, AWS Graviton, Apple Silicon) | ✅ |
| ARMv7 (older Pi) | ✅ |

---

*krainium*
