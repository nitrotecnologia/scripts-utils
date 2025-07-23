#!/bin/bash

# Apache Guacamole auto-installer for Ubuntu 24.04
# Autor: Daniel Guerra
# Executar com: sudo ./install_guacamole.sh

set -e

echo "### Apache Guacamole Installer ###"

# Prompt de variáveis
read -p "Informe a senha do MySQL para o usuário root (será usada para criar o banco): " MYSQL_ROOT_PASSWORD
read -p "Informe uma senha forte para o usuário guac_user do MySQL: " GUAC_DB_PASSWORD

# Atualizar sistema
echo "[1/10] Atualizando sistema..."
apt update && apt upgrade -y
apt autoremove -y
apt autoclean -y
apt clean

# Instalar dependências
echo "[2/10] Instalando pacotes necessários..."
apt install -y build-essential libcairo2-dev libjpeg-turbo8-dev \
    libpng-dev libtool-bin libossp-uuid-dev libvncserver-dev \
    freerdp2-dev libssh2-1-dev libtelnet-dev libwebsockets-dev \
    libpulse-dev libvorbis-dev libwebp-dev libssl-dev \
    libpango1.0-dev libswscale-dev libavcodec-dev libavutil-dev \
    libavformat-dev wget gnupg2 software-properties-common

# Baixar e compilar guacamole-server
echo "[3/10] Baixando e compilando Guacamole Server..."
cd /usr/local/src
wget https://downloads.apache.org/guacamole/1.5.5/source/guacamole-server-1.5.5.tar.gz
tar -xvf guacamole-server-1.5.5.tar.gz
cd guacamole-server-1.5.5
./configure --with-init-dir=/etc/init.d --enable-allow-freerdp-snapshots
make
make install
ldconfig

# Ativar e iniciar guacd
echo "[4/10] Ativando e iniciando guacd..."
systemctl daemon-reload
systemctl enable guacd
systemctl start guacd

# Criar diretórios
echo "[5/10] Criando diretórios para extensões..."
mkdir -p /etc/guacamole/{extensions,lib}

# Instalar Tomcat9
echo "[6/10] Instalando Tomcat9..."
add-apt-repository -y -s "deb http://archive.ubuntu.com/ubuntu/ jammy main universe"
apt install -y tomcat9 tomcat9-admin tomcat9-common tomcat9-user

wget https://downloads.apache.org/guacamole/1.5.5/binary/guacamole-1.5.5.war
mv guacamole-1.5.5.war /var/lib/tomcat9/webapps/guacamole.war
systemctl restart tomcat9 guacd

# Instalar e configurar MariaDB
echo "[7/10] Instalando MariaDB..."
apt install -y mariadb-server
mysqladmin -u root password "$MYSQL_ROOT_PASSWORD"

# Configurar segurança do MySQL
mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<EOF
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';
FLUSH PRIVILEGES;
EOF

# Baixar MySQL Connector/J
echo "[8/10] Instalando MySQL Connector/J..."
cd /usr/local/src
wget https://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-j-9.1.0.tar.gz
tar -xf mysql-connector-j-9.1.0.tar.gz
cp mysql-connector-j-9.1.0/mysql-connector-j-9.1.0.jar /etc/guacamole/lib/

# Plugin JDBC Guacamole
echo "[9/10] Instalando plugin JDBC..."
wget https://downloads.apache.org/guacamole/1.5.5/binary/guacamole-auth-jdbc-1.5.5.tar.gz
tar -xf guacamole-auth-jdbc-1.5.5.tar.gz
mv guacamole-auth-jdbc-1.5.5/mysql/guacamole-auth-jdbc-mysql-1.5.5.jar /etc/guacamole/extensions/

# Criar banco e usuário
echo "[10/10] Criando banco e importando schema..."
mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<EOF
CREATE DATABASE guac_db;
CREATE USER 'guac_user'@'localhost' IDENTIFIED BY '$GUAC_DB_PASSWORD';
GRANT SELECT,INSERT,UPDATE,DELETE ON guac_db.* TO 'guac_user'@'localhost';
FLUSH PRIVILEGES;
EOF

cd guacamole-auth-jdbc-1.5.5/mysql/schema
cat *.sql | mysql -u root -p"$MYSQL_ROOT_PASSWORD" guac_db

# Criar guacamole.properties
cat <<EOT > /etc/guacamole/guacamole.properties
mysql-hostname: 127.0.0.1
mysql-port: 3306
mysql-database: guac_db
mysql-username: guac_user
mysql-password: $GUAC_DB_PASSWORD
EOT

# Restart final
echo "Finalizando instalação..."
systemctl restart tomcat9 guacd mysql

echo "### Instalação finalizada com sucesso! ###"
echo "Acesse via: http://<IP-DO-SERVIDOR>:8080/guacamole"
echo "Login padrão: guacadmin / guacadmin"
