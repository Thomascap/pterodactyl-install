USE_DOMAIN=false
FQDN="hostname --ip-address"
USE_SSL=false
apt update
clear

echo "Do you want to use a domainname for this node? (y/n)"
read USE_DOMAIN_CHOICE
if [ "$USE_DOMAIN_CHOICE" == "y" ]; then
    USE_DOMAIN=true
elif [ "$USE_DOMAIN_CHOICE" == "Y" ]; then
    USE_DOMAIN=true
elif [ "$USE_DOMAIN_CHOICE" == "n" ]; then
    USE_DOMAIN=false
elif [ "$USE_DOMAIN_CHOICE" == "N" ]; then
    USE_DOMAIN=false
else
    echo "Answer not found, no domain will be used."
    USE_DOMAIN=false
fi

if [ "$USE_DOMAIN" == "true" ]; then
echo "On which domain name should this node be installed?"
read FQDN
echo "Do you want SSL on this domain? (IPs cannot have SSL!) (y/n)"
read USE_SSL_CHOICE
if [ "$USE_SSL_CHOICE" == "y" ]; then
    USE_SSL=true
elif [ "$USE_SSL_CHOICE" == "Y" ]; then
    USE_SSL=true
elif [ "$USE_SSL_CHOICE" == "n" ]; then
    USE_SSL=false
elif [ "$USE_SSL_CHOICE" == "N" ]; then
    USE_SSL=false
else
    echo "Answer not found, no SSL will be used."
    USE_SSL=false
fi
elif [ "$USE_DOMAIN" == "false" ]; then
echo ""
fi

clear

if [ "$virtualization" == "openvz" ]; then
# Docker Installation
# -------------------
bash <(curl -s https://xxxxxxx)
systemctl enable docker
# Wings Installation
# ------------------
mkdir -p /etc/pterodactyl
curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
chmod u+x /usr/local/bin/wings
# Daemonizing (using systemd)
# ---------------------------
curl -o /etc/systemd/system/wings.service https://raw.githubusercontent.com/Thomascap/pterodactyl-installer/main/pterodactyl-ssl.conf
systemctl enable --now wings
elif [ "$virtualization" == "kvm" ]; then
# Docker Installation
# -------------------
curl -sSL https://get.docker.com/ | CHANNEL=stable bash
systemctl enable --now docker
# Wings Installation
# ------------------
mkdir -p /etc/pterodactyl
curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
chmod u+x /usr/local/bin/wings
# Daemonizing (using systemd)
# ---------------------------
curl -o /etc/systemd/system/wings.service https://raw.githubusercontent.com/Thomascap/pterodactyl-installer/main/pterodactyl-ssl.conf
systemctl enable --now wings
fi

# Creating SSL Certificates
# -------------------------
sudo apt update
sudo apt install -y certbot
sudo apt install -y python3-certbot-nginx
# Creating a Certificate
if [ "$USE_SSL" == true ]; then
certbot certonly -d ${FQDN} --standalone --agree-tos --register-unsafely-without-email
elif [ "$USE_SSL" == false ]; then
echo ""
fi

clear
echo "Please now create a node on the panel and copy the configuration in /etc/pterodactyl/config.yml and then start the wings."
