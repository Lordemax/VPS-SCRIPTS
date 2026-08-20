# VPS-SCRIPTS
Automatic Script Installer by Lordemax

==========

## Usage
### Centos 6 (OpenVZ VPS)
```
wget https://raw.github.com/choirulanam217/script/master/centos6.sh
bash centos6.sh
```
Tested on
* CentOS 6 32 bit
* CentOS 6 64 bit
* OpenVZ only

### Centos 6 (KVM VPS)
```
wget https://raw.github.com/choirulanam217/script/master/centos6-kvm.sh
bash centos6-kvm.sh
```
Tested on
* CentOS 6 32 bit
* CentOS 6 64 bit
* KVM only

### Debian 6 32bit
```
wget https://raw.github.com/choirulanam217/script/master/debian6.sh
bash debian6.sh
```
Tested on
* Debian 6 32 bit
* Debian 6 64 bit
* OpenVZ only

### Debian 12 or Ubuntu 22.04
```
wget https://raw.githubusercontent.com/Lordemax/VPS-SCRIPTS/master/install.sh
bash install.sh
```
Choose the operating system from the menu. The installer validates the
selected release and configures Nginx, the distribution PHP-FPM package,
OpenVPN, Dropbear, Squid, vnStat, and Fail2Ban.

The old `debian7.sh` filename remains as a compatibility wrapper and now
launches the Debian 12 installer. Debian 6, CentOS 6, and Debian 7 are no
longer supported by their original scripts because their repositories and
runtime packages have reached end of life.

### VPS user management
```bash
sudo bash user-manager.sh list
sudo bash user-manager.sh add USER [DAYS]
sudo bash user-manager.sh password USER
sudo bash user-manager.sh expire USER DAYS
sudo bash user-manager.sh disable USER
sudo bash user-manager.sh enable USER
sudo bash user-manager.sh delete USER
```
The user manager only modifies regular users (UID 1000 or higher). Passwords
are entered interactively and are never placed in command-line arguments.

### VPS tools
```bash
sudo bash vps-tools.sh menu
sudo bash vps-tools.sh info
sudo bash vps-tools.sh services
sudo bash vps-tools.sh ram
sudo bash vps-tools.sh bandwidth
sudo bash vps-tools.sh backup
sudo bash vps-tools.sh ports
sudo bash vps-tools.sh logins
sudo bash vps-tools.sh firewall
sudo bash vps-tools.sh cleanup-expired
sudo bash vps-tools.sh reboot-on|reboot-off
sudo bash vps-tools.sh backup-on|backup-off
sudo bash vps-tools.sh ipv6-on|ipv6-off
```
These commands provide system information, service status, RAM and network
usage, plus a local configuration backup in `/root/vps-backups`. Backups do
not overwrite system account files when restored. Scheduled maintenance uses
systemd timers; expired accounts are locked rather than deleted.

Standalone compatibility commands are also available: `menu.sh`,
`backup.sh`, `autoreboot.sh`, `restart.sh`, `clearlog.sh`, `logcleaner.sh`,
`cek-bandwidth.sh`, `cek-trafik.sh`, `cekv.sh`, `ram.sh`, `running.sh`,
`tendang.sh`, `usernew.sh`, `dns.sh`, and `netf.sh`. They delegate to the maintained
local tools instead of downloading code at runtime.

The reference project's Xray/VMess/VLESS/Trojan installers, WebSocket and
Stunnel payloads, Cloudflare automation, remote backup credentials, and full
system restore scripts were not copied. They have no visible license in the
source repository and can replace firewall, account, or service configuration
without a rollback path.

### Advanced services
Run `sudo bash advanced-services.sh menu` or choose **Advanced services** from
`vps-tools.sh menu` to optionally install:

- Xray VMess, VLESS, and Trojan WebSocket endpoints on localhost
- SSH WebSocket bridge on port 8022
- Stunnel SSH TLS on port 8443
- Dante SOCKS5 on port 1080
- Cloudflare DNS A-record updates using an API token
- Local backup and restricted configuration restore

These services are opt-in and use alternate ports to avoid conflicts with the
base installer. Review firewall rules before exposing proxy services publicly.


### Service
* OpenSSH port 22, 143
* OpenVPN port 1194 tcp
* Dropbear port 109, 110, 443
* Squid port 8080 (limit to IP VPS)
* badvpn-udpgw port 7300

### Function
* Webmin http(s)://[ip]:10000/
* vnstat http://[ip]/vnstat/
* MRTG http://[ip]/mrtg/
* Timezone : Asia/Jakarta
* Fail2Ban : [on]
* IPv6     : [off]

### Tools
* axel
* bmon
* htop
* iftop
* mtr
* nethogs  

### What's script installed
* screenfetch
* ps_mem.py (https://github.com/pixelb/ps_mem/)
* speedtest-cli (https://github.com/sivel/speedtest-cli)
* bench-network.sh
* user-login.sh
* user-limit.sh
* user-expire.sh

Openvpn
wget https://raw.github.com/choirulanam217/script/master/dimas.debian
bash dimas.debian

