

FQDN="pterodactyl.mynode.nl"
USE_SSL=false
EMAIL="pterodactyl@mynode.nl"
MYSQL_USER="pterodactyl"
MYSQL_PASSWORD=`head -c 8 /dev/random | base64`
MYSQL_DATABASE="panel"
MYSQL_USER_PANEL="pterodactyluser"
MYSQL_PASSWORD_PANEL=`head -c 8 /dev/random | base64`
USER_EMAIL="admin@gmail.com"
USER_USERNAME="admin"
USER_FIRSTNAME="admin"
USER_LASTNAME="admin"
USER_PASSWORD=`head -c 8 /dev/random | base64`
RAM=`grep MemTotal /proc/meminfo | awk '{print $2 / 1024}'`
virtualization=`systemd-detect-virt`

echo "On which domain name should this panel be installed? (FQDN)"
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


# Example Dependency Installation
# -------------------------------
# Add "add-apt-repository" command
apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg
# Add additional repositories for PHP, Redis, and MariaDB
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
add-apt-repository -y ppa:chris-lea/redis-server
curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash
# Update repositories list
apt update
# Add universe repository if you are on Ubuntu 18.04
apt-add-repository universe
# Install Dependencies
apt -y install php8.0 php8.0-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server

# Installing Composer
# -------------------
curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer

# Download Files
# --------------
mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/

# Installation
# ------------
# Database Configuration
mysql -u root -e "CREATE USER '${MYSQL_USER}'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASSWORD}';"
mysql -u root -e "CREATE DATABASE ${MYSQL_DATABASE};"
mysql -u root -e "GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'127.0.0.1' WITH GRANT OPTION;"
mysql -u root -e "CREATE USER '${MYSQL_USER_PANEL}'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASSWORD_PANEL}';"
mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO '${MYSQL_USER_PANEL}'@'127.0.0.1' WITH GRANT OPTION;"
mysql -u root -e "FLUSH PRIVILEGES;"
sed -i -e "s/127.0.0.1/0.0.0.0/g" /etc/mysql/my.cnf
sed -i -e "s/127.0.0.1/0.0.0.0/g" /etc/mysql/mariadb.conf.d/50-server.cnf
systemctl restart mysql
systemctl restart mysqld
cp .env.example .env
y | composer install --no-dev --optimize-autoloader
php artisan key:generate --force

# Environment Configuration
# -------------------------
if [ "$USE_SSL" == true ]; then
php artisan p:environment:setup --author=$EMAIL --url=https://$FQDN --timezone=Europe/Amsterdam --cache=redis --session=redis --queue=redis --redis-host=127.0.0.1 --redis-pass=null --redis-port=6379  --settings-ui=true
elif [ "$USE_SSL" == false ]; then
php artisan p:environment:setup --author=$EMAIL --url=http://$FQDN --timezone=Europe/Amsterdam --cache=redis --session=redis --queue=redis --redis-host=127.0.0.1 --redis-pass=null --redis-port=6379  --settings-ui=true
fi
php artisan p:environment:database --host=127.0.0.1 --port=3306 --database=$MYSQL_DATABASE --username=$MYSQL_USER --password=$MYSQL_PASSWORD

# Database Setup
# --------------
y | php artisan migrate --seed --force

# Locations Setup
# --------------
php artisan p:location:make --short=EARTH --long="This server is hosted on Earth"

# Node Setup
# ----------
cd /var/www/pterodactyl/app/Console/Commands && mkdir Node && cd Node
wget https://raw.githubusercontent.com/Thomascap/pterodactyl-install/main/commands/Node/MakeNodeCommand.php
cd /var/www/pterodactyl
if [ "$USE_SSL" == true ]; then
php artisan p:node:make --name=node01 --description=node01 --locationId=1 --fqdn=$FQDN --public=1 --scheme=https --proxy=0 --maintenance=0 --maxMemory=$RAM --overallocateMemory=0 --maxDisk=5000 --overallocateDisk=0 --uploadSize=100 --daemonListeningPort=8080 --daemonSFTPPort=2022 --daemonBase=/var/lib/pterodactyl/volumes
elif [ "$USE_SSL" == false ]; then
php artisan p:node:make --name=node01 --description=node01 --locationId=1 --fqdn=$FQDN --public=1 --scheme=http --proxy=0 --maintenance=0 --maxMemory=$RAM --overallocateMemory=0 --maxDisk=5000 --overallocateDisk=0 --uploadSize=100 --daemonListeningPort=8080 --daemonSFTPPort=2022 --daemonBase=/var/lib/pterodactyl/volumes
fi

# Database Setup
# --------------
cd /var/www/pterodactyl/app/Console/Commands && mkdir Database && cd Database && mkdir Host && cd Host
wget https://raw.githubusercontent.com/Thomascap/pterodactyl-install/main/commands/Database/Host/MakeHostCommand.php
cd /var/www/pterodactyl
php artisan p:database:host:make --name=db01 --host=127.0.0.1 --port=3306 --username=$MYSQL_USER_PANEL --password=$MYSQL_PASSWORD_PANEL --node_id=1

# Add The First User
# --------------
php artisan p:user:make --email=$USER_EMAIL --username=$USER_USERNAME --name-first=$USER_FIRSTNAME --name-last=$USER_LASTNAME --password=$USER_PASSWORD --admin=1

# Set Permissions
# ---------------
chown -R www-data:www-data /var/www/pterodactyl/*

# Queue Listeners
# ---------------
# Crontab Configuration
cronjob="* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1"
(crontab -u root -l; echo "$cronjob" ) | crontab -u root -
# Create Queue Worker
curl -o /etc/systemd/system/pteroq.service https://raw.githubusercontent.com/Thomascap/pterodactyl-install/main/configurations/pteroq.service
sudo systemctl enable --now redis-server
sudo systemctl enable --now pteroq.service

# Stop & Remove Apache2
# ----------------------
systemctl stop apache2
apt -y remove apache2
systemctl stop nginx

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

# Webserver Configuration
# -----------------------
if [ "$USE_SSL" == true ]; then
curl -o /etc/nginx/sites-available/pterodactyl.conf https://raw.githubusercontent.com/Thomascap/pterodactyl-install/main/configurations/pterodactyl-ssl.conf
sed -i -e "s/<domain>/${FQDN}/g" /etc/nginx/sites-available/pterodactyl.conf
elif [ "$USE_SSL" == false ]; then
curl -o /etc/nginx/sites-available/pterodactyl.conf https://raw.githubusercontent.com/Thomascap/pterodactyl-install/main/configurations/pterodactyl.conf
sed -i -e "s/<domain>/${FQDN}/g" /etc/nginx/sites-available/pterodactyl.conf
fi
# Enabling Configuration
sudo ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
systemctl restart nginx

# Installing Wings
# ----------------
if [ "$virtualization" == "openvz" ]; then
# Docker Installation
wget https://raw.githubusercontent.com/Thomascap/pterodactyl-install/main/scripts/dockerfix.bash
bash dockerfix.bash
systemctl enable docker
# Wings Installation
mkdir -p /etc/pterodactyl
curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
chmod u+x /usr/local/bin/wings
# Daemonizing (using systemd)
curl -o /etc/systemd/system/wings.service https://raw.githubusercontent.com/Thomascap/pterodactyl-install/main/configurations/wings.service
systemctl enable --now wings
elif [ "$virtualization" == "kvm" ]; then
# Docker Installation
curl -sSL https://get.docker.com/ | CHANNEL=stable bash
systemctl enable --now docker
# Wings Installation
mkdir -p /etc/pterodactyl
curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
chmod u+x /usr/local/bin/wings
# Daemonizing (using systemd)
curl -o /etc/systemd/system/wings.service https://raw.githubusercontent.com/Thomascap/pterodactyl-install/main/configurations/wings.service
systemctl enable --now wings
fi

cd /etc/pterodactyl
wget https://raw.githubusercontent.com/Thomascap/pterodactyl-install/main/configurations/config.yml
UUID=`cat /var/www/pterodactyl/storage/app/uuid.txt`
token_id=`cat /var/www/pterodactyl/storage/app/daemon_token_id.txt`
token=`cat /var/www/pterodactyl/storage/app/daemon_token.txt`
sed -i -e "s/<uuid>/${UUID}/g" /etc/pterodactyl/config.yml
sed -i -e "s/<token_id>/${token_id}/g" /etc/pterodactyl/config.yml
sed -i -e "s/<token>/${token}/g" /etc/pterodactyl/config.yml
sed -i -e "s/<fqdn>/${FQDN}/g" /etc/pterodactyl/config.yml

# Login Settings
# --------------
echo "----------------------------------"
echo "Pterodactyl Logingegevens:"
echo "URL: ${FQDN}"
echo "Username: ${USER_USERNAME}"
echo "Password: ${USER_PASSWORD}"
echo "----------------------------------"
echo "MySQL Database Logingegevens:"
echo "IP: 127.0.0.1"
echo "Database: ${MYSQL_DATABASE}"
echo "Username: ${MYSQL_USER}"
echo "Password: ${MYSQL_PASSWORD}"
echo "----------------------------------"
echo "MySQL Panel Logingegevens:"
echo "IP: 127.0.0.1"
echo "Username: ${MYSQL_USER_PANEL}"
echo "Password: ${MYSQL_PASSWORD_PANEL}"
echo "----------------------------------"
