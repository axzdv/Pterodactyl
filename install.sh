if (( $EUID != 0 )); then
    echo ""
    echo "Please run as root"
    echo ""
    exit
fi
clear

Download="https://raw.githubusercontent.com/sebasdevx/Pterodactyl/main/src"

blowfish_secret=""
FQDN=""
FQDN_Node=""
MYSQL_PASSWORD=""
SSL_AVAILABLE=false
Node_SSL_AVAILABLE=false
Pterodactyl_conf="pterodactyl-no_ssl.conf"
user_username=""
user_password=""

installPanel() {
  apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg
  LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
  curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
   echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list
   apt update
  apt -y install php8.1 php8.1-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server
  curl -sS https://getcomposer.org/installer | sudo php --
  --install-dir=/usr/local/bin --filename=composer
  sudo mkdir /var/www/pterodactyl
  cd /var/www/pterodactyl
  curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
  tar -xzvf panel.tar.gz
  chmod -R 755 storage/* bootstrap/cache/
  rm panel.tar.gz
  # MYSQL SETUP
  
   mysql -u root -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASSWORD}';"
    mysql -u root -e "CREATE DATABASE panel;"
    mysql -u root -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
    mysql -u root -e "CREATE USER 'pterodactyluser'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASSWORD}';"
    mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO 'pterodactyluser'@'127.0.0.1' WITH GRANT OPTION;"
    mysql -u root -e "CREATE USER 'pterodactyluser'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';"
    mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO 'pterodactyluser'@'%' WITH GRANT OPTION;"
    mysql -u root -e "flush privileges;"
    
    curl -o /etc/mysql/my.cnf $Download/my.conf
    curl -o /etc/mysql/mariadb.conf.d/50-server.cnf
    $Download/50-server.cnf
    
    systemctl restart mariadb
    systemctl restart mysql
    cp .env.example .env
    COMPOSER_ALLOW_SUPERUSER=1
    composer install --no-dev --optimize-autoloader
    php artisan key:generate --force
    
    app_url="http://$FQDN"
    if [ "$SSL_AVAILABLE" == true ]
        then
        app_url="https://$FQDN"
        Pterodactyl_conf="pterodactyl.conf"
        apt update
        apt install -y certbot
        apt install -y python3-certbot-nginx
        certbot certonly --nginx --redirect --no-eff-email --register-unsafely-without-email -d "$FQDN"
    fi
    php artisan p:environment:setup \
    --author="contact@vultamnodes.com" \
    --url="$app_url" \
    --timezone="UTC" \
    --cache="file" \
    --session="file" \
    --queue="redis" \
    --redis-host="localhost" \
    --redis-pass="null" \
    --redis-port="6379" \
    --settings-ui=true \
    --telemetry=true
    
    php artisan p:environment:database \
    --host="127.0.0.1" \
    --port="3306" \
    --database="panel" \
    --username="pterodactyl" \
    --password="${MYSQL_PASSWORD}"
    
    php artisan migrate --seed --force
    
    php artisan p:user:make \
    --email="contact@vultamnodes.com" \
    --username="$user_username" \
    --name-first="$user_username" \
    --name-last="$user_username" \
    --password="$user_password" \
    --admin=1
    
    chown -R www-data:www-data /var/www/pterodactyl/*
    crontab -l | {
        cat
        echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1"
    } | crontab -l
    
    curl -o /etc/systemd/system/pteroq.service $Download/pteroq.service
    systemctl enable --now redis-server
    systemctl enable --now pteroq.service
    
    curl -o /etc/nginx/sites-enabled/pterodactyl.conf $Download/$Pterodactyl_conf
    sed -i -e "s@<domain>@${FQDN}@g" /etc/nginx/sites-enabled/pterodactyl.conf
    systemctl restart nginx
    cd
}

installWings() {
    cd

    rm /etc/apt/sources.list.d/mariadb.list
    rm /etc/apt/sources.list.d/mariadb.list.old_1
    rm /etc/apt/sources.list.d/mariadb.list.old_2
    rm /etc/apt/sources.list.d/mariadb.list.old_3
    rm /etc/apt/sources.list.d/mariadb.list.old_4
    rm /etc/apt/sources.list.d/mariadb.list.old_5

    rm /etc/default/grub

    rm /etc/mysql/my.cnf
    rm /etc/mysql/mariadb.conf.d/50-server.cnf

    curl -sSL https://get.docker.com/ | CHANNEL=stable bash
    systemctl enable --now docker

    curl -o /etc/default/grub $Download/grub
    update-grub
    
    mkdir -p /etc/pterodactyl
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
    chmod u+x /usr/local/bin/wings
    
    apt update

    curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash

    mysql -u root -e "CREATE USER 'pterodactyluser'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';"
    mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO 'pterodactyluser'@'%' WITH GRANT OPTION;"
    mysql -u root -e "flush privileges;"

    curl -o /etc/mysql/my.cnf $Download/my.cnf
    curl -o /etc/mysql/mariadb.conf.d/50-server.cnf $Download/50-server.cnf
    
    systemctl restart mysql
    systemctl restart mariadb

    app_url="http://$FQDN"
    if [ "$SSL_AVAILABLE" == true ]
        then
        apt update
        apt install -y certbot
        apt install -y python3-certbot-nginx
        certbot certonly --nginx --redirect --no-eff-email --register-unsafely-without-email -d "$FQDN"
    fi
    
    rm /etc/systemd/system/wings.service
    curl -o /etc/systemd/system/wings.service $Download/wings.service
    echo > config.yml
    cd
}

updatePanel() {
    cd /var/www/pterodactyl
    php artisan down
    curl -L https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz | tar -xzv
    chmod -R 755 storage/* bootstrap/cache
    composer install --no-dev --optimize-autoloader
    php artisan optimize:clear
    php artisan migrate --seed --force
    chown -R www-data:www-data /var/www/pterodactyl/*
    php artisan queue:restart
    php artisan up
    cd
}

installPhpMyAdmin() {
    cd /var/www/pterodactyl/public/

    rm /etc/mysql/my.cnf
    rm /etc/mysql/mariadb.conf.d/50-server.cnf

    mkdir pma
    cd pma

    wget https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.tar.gz
    tar xvzf phpMyAdmin-latest-all-languages.tar.gz

    mv phpMyAdmin-*-all-languages/* /var/www/pterodactyl/public/pma

    rm -rf phpM*

    mkdir /var/www/pterodactyl/public/pma/tmp
    
    chmod -R 777 /var/www/pterodactyl/public/pma/tmp

    rm config.sample.inc.php

    curl -o /var/www/pterodactyl/public/pma/config.inc.php $GitHub_Account/config.inc.php
    sed -i -e "s@<blowfish_secret>@${blowfish_secret}@g" /var/www/pterodactyl/public/pma/config.inc.php
    rm -rf /var/www/pterodactyl/public/pma/setup
    cd
}

AssetsPanel() {
  sudo mkdir -p /etc/apt/keyrings
 curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo .gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
 echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg]
 https://deb.nodesource.com/node_16.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.blowfish_secret
 
 apt update
 apt install -y nodejs
 npm i -g yarn
 cd /var/www/pterodactyl
 yarn
 cd
}

print_error() {
    COLOR_RED='\033[0;31m'
    COLOR_NC='\033[0m'

    echo ""
    echo -e "* ${COLOR_RED}ERROR${COLOR_NC}: $1"
    echo ""
}

required_input() {
    local __resultvar=$1
    local result=''

    while [ -z "$result" ]; do
        echo -n "* ${2}"
        read -r result

        if [ -z "${3}" ]; then
        [ -z "$result" ] && result="${4}"
        else
        [ -z "$result" ] && print_error "${3}"
        fi
    done

    eval "$__resultvar="'$result'""
}


invalid_ip() {
    ip route get "$1" >/dev/null 2>&1
    echo $?
}

check_FQDN_SSL() {
    if [[ $(invalid_ip "$FQDN") == 1 && $FQDN != 'localhost' ]]; then
        SSL_AVAILABLE=true
    fi
}
check_FQDN_Node_SSL() {
    if [[ $(invalid_ip "$FQDN_Node") == 1 && $FQDN_Node != 'localhost' ]]; then
        Node_SSL_AVAILABLE=true
    fi
}

password_input() {
    local __resultvar=$1
    local result=''
    local default="$4"

    while [ -z "$result" ]; do
        echo -n "* ${2}"

        while IFS= read -r -s -n1 char; do
        [[ -z $char ]] && {
            printf '\n'
            break
        }
        if [[ $char == $'\x7f' ]]; then
            if [ -n "$result" ]; then
            [[ -n $result ]] && result=${result%?}
            printf '\b \b'
            fi
        else
            result+=$char
            printf '*'
        fi
        done
        [ -z "$result" ] && [ -n "$default" ] && result="$default"
        [ -z "$result" ] && print_error "${3}"
    done

    eval "$__resultvar="'$result'""
}

summary() {
    clear
    echo ""
    echo -e "\033[1;94mDatabase credentials:\033[0m"
    echo -e "\033[1;92m*\033[0m IPv4: 127.0.0.1"
    echo -e "\033[1;92m*\033[0m Port: 3306"
    echo -e "\033[1;92m*\033[0m User:  pterodactyluser"
    echo -e "\033[1;92m*\033[0m Password: $MYSQL_PASSWORD"
    echo ""
    echo -e "\033[1;94mPanel credentials:\033[0m"
    echo -e "\033[1;92m*\033[0m Username: $user_username"
    echo -e "\033[1;92m*\033[0m Password: $user_password"
    echo ""
    echo -e "\033[1;96mhttps://$FQDN"
    echo ""
}

echo ""
echo "[0] Exit"
echo "[1] Install Panel"
echo "[2] Install Wings"
echo "[3] Update Panel"
echo "[4] Install phpMyAdmin"
echo "[5] Install Assets (NodeJS)"
echo ""
read -p "Please enter a number: " choice
echo ""

if [ $choice == "0" ]
then
    echo -e "\033[0;96mCya\033[0m"
    echo ""
    exit
fi

if [ $choice == "1" ]
    then
    password_input MYSQL_PASSWORD "Provide password for database: " "MySQL password cannot be empty"
    required_input user_username "Provide username for panel: " "Username cannot be empty"
    password_input user_password "Provide password for panel: " "Password cannot be empty"

    while [ -z "$FQDN" ]; do
    echo -n "* Set the FQDN of this panel (panel.example.com | 0.0.0.0): "
    read -r FQDN
    [ -z "$FQDN" ] && print_error "FQDN cannot be empty"
    done

    check_FQDN_SSL
    installPanel
    summary
    exit
fi

if [ $choice == "2" ]
    then
    password_input MYSQL_PASSWORD "Provide password for database: " "MySQL password cannot be empty"

    while [ -z "$FQDN" ]; do
    echo -n "* Set the FQDN of the node (node.example.com | 0.0.0.0): "
    read -r FQDN
    [ -z "$FQDN" ] && print_error "FQDN cannot be empty"
    done

    check_FQDN_SSL
    installWings
    clear
    echo ""
    echo -e "\033[0;92mWings installed successfully\033[0m"
    echo ""
    exit
fi

if [ $choice == "3" ]
then
    updatePanel
    clear
    echo ""
    echo -e "\033[0;92mPanel updated successfully\033[0m"
    echo ""
    exit
fi

if [ $choice == "4" ]
    then
    required_input blowfish_secret "Provide blowfish secret for phpMyAdmin: " "Blowfish secret cannot be empty"

    installPhpMyAdmin
    clear
    echo ""
    echo -e "\033[0;92mphpMyAdmin installed successfully\033[0m"
    echo ""
    exit
fi

if [ $choice == "5" ]
then
    AssetsPanel
    clear
    echo ""
    echo -e "\033[0;92mAssets installed successfully\033[0m"
    echo ""
    exit
fi