if (( $EUID != 0 )); then
    echo ""
    echo "Please run as root"
    echo ""
    exit
fi

clear

GitHub_Account="https://raw.githubusercontent.com/axzdv/Pterodactyl/main/src"

blowfish_secret=""
FQDN=""
FQDN_Node=""
MYSQL_PASSWORD=""
SSL_AVAILABLE=false
Node_SSL_AVAILABLE=false
Pterodactyl_conf="pterodactyl-no_ssl.conf"
email=""
user_username=""
user_password=""
email_regex="^(([A-Za-z0-9]+((\.|\-|\_|\+)?[A-Za-z0-9]?)*[A-Za-z0-9]+)|[A-Za-z0-9]+)@(([A-Za-z0-9]+)+((\.|\-|\_)?([A-Za-z0-9]+)+)*)+\.([A-Za-z]{2,})+$"


installPanel() {
    rm /etc/nginx/sites-enabled/default
    rm /etc/nginx/sites-enabled/pterodactyl.conf
    
    apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg

    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php

    curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list
    
    apt update

    apt -y install php8.1 php8.1-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server
    
    curl -sS https://getcomposer.org/installer | sudo php --
    --install-dir=/usr/local/bin --filename=getcomposer
    
    sudo mkdir /var/www/pterodactyl 
    cd /var/www/pterodactyl
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/
    rm /var/www/pterodactyl/panel.tar.gz
    
    mysql -u root -e "DROP USER 'pterodactyl'@'127.0.0.1';"
    mysql -u root -e "DROP DATABASE panel;"
    mysql -u root -e "DROP USER 'pterodactyluser'@'127.0.0.1';"
    mysql -u root -e "DROP USER 'pterodactyluser'@'%';"
    mysql -u root -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASSWORD}';"
    mysql -u root -e "CREATE DATABASE panel;"
    mysql -u root -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
    mysql -u root -e "CREATE USER 'pterodactyluser'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASSWORD}';"
    mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO 'pterodactyluser'@'127.0.0.1' WITH GRANT OPTION;"
    mysql -u root -e "CREATE USER 'pterodactyluser'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';"
    mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO 'pterodactyluser'@'%' WITH GRANT OPTION;"
    mysql -u root -e "flush privileges;"
    
    curl -o /etc/mysql/my.cnf $GitHub_Account/my.cnf
    curl -o /etc/mysql/mariadb.conf.d/50-server.cnf
    $GitHub_Account/50-server.cnf
    
    systemctl restart mysql
    systemctl restart mariadb
    
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
    --author="$email" \
    --url="$app_url" \
    --timezone="America/New_York" \
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
    --email="$email" \
    --username="$user_username" \
    --name-first="$user_username" \
    --name-last="$user_username" \
    --password="$user_password" \
    --admin=1
    
    chown -R www-data:www-data /var/www/pterodactyl/*
    
    crontab -l | {
        cat
        echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1"
    } | crontab -
    
   curl -o /etc/systemd/system/pteroq.service $GitHub_Account/pteroq.service

    systemctl enable --now redis-server
    systemctl enable --now pteroq.service
    
    curl -o /etc/nginx/sites-enabled/pterodactyl.conf $GitHub_Account/$Pterodactyl_conf
    sed -i -e "s@<domain>@${FQDN}@g" /etc/nginx/sites-enabled/pterodactyl.conf

    systemctl restart nginx

    cd
}

installWings() {
  cd
  curl -sSL https://get.docker.com/ | CHANNEL=stable bash
    systemctl enable --now docker

    curl -o /etc/default/grub $GitHub_Account/grub
    update-grub
    
    mkdir -p /etc/pterodactyl
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
    chmod u+x /usr/local/bin/wings
    
    apt update

    curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash

    mysql -u root -e "CREATE USER 'pterodactyluser'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';"
    mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO 'pterodactyluser'@'%' WITH GRANT OPTION;"
    mysql -u root -e "flush privileges;"

    curl -o /etc/mysql/my.cnf $GitHub_Account/my.cnf
    curl -o /etc/mysql/mariadb.conf.d/50-server.cnf $GitHub_Account/50-server.cnf
    
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
    curl -o /etc/systemd/system/wings.service $GitHub_Account/wings.service
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

installphpmyadmin() {
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

valid_email() {
    [[ $1 =~ ${email_regex} ]]
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

email_input() {
    local __resultvar=$1
    local result=''

    while ! valid_email "$result"; do
        echo -n "* ${2}"
        read -r result

        valid_email "$result" || print_error "${3}"
    done

    eval "$__resultvar="'$result'""
}

summary() {
  clear
  echo ""
  echo -e "033[1;94mDatos MySQL:\033[0m"
  echo -e "033[1;94mUSER: pterodactyluser\033[0m"
  echo -e "033[1;94mDireccion IP: 127.0.0.1\033[0m"
  echo -e "033[1;94mContraseña: $MYSQL_PASSWORD\033[0m"
  echo -e "033[1;94mNombre: Panel\033[0m"
  echo ""
  echo -e "\033[1;94mPanel credentials:\033[0m"
  echo -e "\033[1;92m*\033[0m Email: $email"
  echo -e "\033[1;92m*\033[0m Usuario: $user_username"
  echo -e "\033[1;92m*\033[0m Contraseña: $user_password"
  echo ""
  echo -e "\033[1;96mPanel:\033[0m htttps://$FQDN"
  echo ""
}

echo ""
echo "[0] Salir"
echo "[1] Instalar Pterodactyl"
echo "[2] Instalar Wings"
echo "[3] Actualizar Panel"
echo "[4] Instalar phpMyAdmim"
echo ""
read -p "Por favor selecciona una opcion: " choice

if [ $choice == "0" ]
then
    echo -e "\033[0;96mHasta pronto.\033[0m"
    echo ""
    exit
fi

if [ $choice == "1" ]
    then
    password_input MYSQL_PASSWORD "MySQL Contraseña: " "Debes
    colocar una contraseña MySQL"
    email_input email "Email: " "Debes colocar un
    email"
    required_input user_username "Usuario: " "Debes colocar
    el nombre de usuario"
    password_input user_password "Contraseña: " "Debes colocar
    una contraseña"

  while [ -z "$FQDN" ]; do
  echo -n "* Introduce el FQDN (panel.example.com | 0.0.0.0)): "
  read -r FQDN
  [ -z "$FQDN" ] && print_error "FQDN No puede estar vacio"
  done
    check_FQDN_SSL
    installPanel
    summary
    exit
fi

if [ $choice == "2" ]
    then
    password_input MYSQL_PASSWORD "Contraseña de la database: " "La contraseña
    no puede estar vacia"

    while [ -z "$FQDN" ]; do
    echo -n "* Introduce el FQDN (node.example.com | 0.0.0.0): "
    read -r FQDN
    [ -z "$FQDN" ] && print_error "FQDN no puede estar vacío"
    done

    check_FQDN_SSL
    installWings
    clear
    echo ""
    echo -e "\033[0;92mWings instalados correctamente\033[0m"
    echo ""
    exit
fi

if [ $choice == "3" ]
then
    updatePanel
    clear
    echo ""
    echo -e "\033[0;92mPanel Actualizado Correctamente\033[0m"
    echo ""
    exit
fi

if [ $choice == "4" ]
    then
   required_input blowfish_secret "Introduce la clave secreta: "
    "Blowfish secret no debe estar vacia"

    installphpmyadmin
    clear
    echo ""
    echo -e "\033[0;92mphpMyAdmin instalada\033[0m"
    echo ""
    exit
fi