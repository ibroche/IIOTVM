#!/bin/bash

# 🔥 Demander le nom de domaine Cloudflare
echo "🔹 Entrez votre domaine Cloudflare (ex: votre-domaine.com) :"
read DOMAIN

# 🚀 Mise à Jour et Installation des Dépendances
echo "🔍 Mise à jour du système..."
sudo apt update && sudo apt upgrade -y

# 🐳 Installation de Docker + Docker Compose
echo "🐳 Installation de Docker..."
sudo apt install -y docker.io docker-compose

# 🌨 Installation de Cloudflared
echo "🌨 Installation de Cloudflared..."
sudo mkdir -p /usr/local/bin
curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
sudo chmod +x /usr/local/bin/cloudflared
cloudflared -v

# 🌍 Connexion à Cloudflare
echo "🌍 Connexion à Cloudflare... Suivez les instructions affichées."
cloudflared tunnel login

# 📀 Création du tunnel Cloudflare
echo "📀 Création du tunnel..."
cloudflared tunnel create mon-tunnel
TUNNEL_ID=$(cloudflared tunnel list | grep "mon-tunnel" | awk '{print $3}')

# 📼 Configuration du tunnel
mkdir -p /etc/cloudflared
cat <<EOF > /etc/cloudflared/config.yml
tunnel: $TUNNEL_ID
credentials-file: /root/.cloudflared/$TUNNEL_ID.json
ingress:
  - hostname: nodered.$DOMAIN
    service: http://localhost:1880
  - hostname: streamlit.$DOMAIN
    service: http://localhost:8501
  - hostname: phpmyadmin.$DOMAIN
    service: http://localhost:8080
  - hostname: opcua.$DOMAIN
    service: http://localhost:4840
  - service: http_status:404
EOF

# 🌐 Ajout des routes DNS Cloudflare
cloudflared tunnel route dns $TUNNEL_ID nodered.$DOMAIN
cloudflared tunnel route dns $TUNNEL_ID streamlit.$DOMAIN
cloudflared tunnel route dns $TUNNEL_ID phpmyadmin.$DOMAIN
cloudflared tunnel route dns $TUNNEL_ID opcua.$DOMAIN

# 🛠 Activation du service Cloudflared
cloudflared service install
sudo systemctl enable --now cloudflared

# 🛋 Nettoyage et installation propre d'Open62541
echo "🧹 Nettoyage et installation propre d'Open62541..."
sudo rm -rf ~/open62541 /usr/local/include/open62541* /usr/local/lib/libopen62541* /etc/systemd/system/opcua_server.service
sudo systemctl daemon-reload

# 🔨 Installation des Dépendances pour Open62541
echo "🔨 Installation des dépendances..."
sudo apt install -y cmake gcc git libssl-dev libjansson-dev pkg-config python3 python3-pip python3-dev mariadb-server

# 💪 Installation et Compilation d'Open62541
echo "💪 Compilation d'Open62541..."
mkdir -p ~/open62541 && cd ~/open62541
git clone --depth=1 --branch v1.3.5 https://github.com/open62541/open62541.git .
rm -rf build && mkdir build && cd build
cmake .. -DUA_ENABLE_AMALGAMATION=ON
make -j$(nproc)
sudo make install
sudo ldconfig

# 💡 Vérification de l'installation d'Open62541
if [ ! -f "/usr/local/include/open62541.h" ]; then
    echo "❌ Erreur : Open62541 n'a pas été installé correctement."
    exit 1
fi

# 🛠 Correction des chemins Open62541
sudo mkdir -p /usr/local/include/open62541
sudo cp /usr/local/include/open62541.h /usr/local/include/open62541/server.h

# 🎯 Compilation du Serveur OPC UA
echo "🎯 Compilation du serveur OPC UA..."
mkdir -p ~/opcua_server
cat <<EOF > ~/opcua_server/variables.json
{
  "variables": [
    { "name": "temperature", "type": "Double", "initialValue": 25.0 },
    { "name": "status", "type": "Boolean", "initialValue": true },
    { "name": "speed", "type": "Int32", "initialValue": 100 }
  ]
}
EOF

cat <<EOF > ~/opcua_server/opcua_server.c
#include <open62541/server.h>
#include <open62541/server_config_default.h>
#include <open62541/plugin/log_stdout.h>
#include <jansson.h>

int main(void) {
    UA_Server *server = UA_Server_new();
    UA_ServerConfig_setDefault(UA_Server_getConfig(server));
    UA_StatusCode status = UA_Server_run(server, &(UA_Boolean){true});
    UA_Server_delete(server);
    return status == UA_STATUSCODE_GOOD ? 0 : 1;
}
EOF
gcc -std=c99 -o ~/opcua_server/opcua_server_bin ~/opcua_server/opcua_server.c \
    -I/usr/local/include/open62541 -L/usr/local/lib $(pkg-config --cflags --libs open62541) -ljansson

# 🔒 Configuration du Service OPC UA
cat <<EOF | sudo tee /etc/systemd/system/opcua_server.service
[Unit]
Description=OPC UA Server
After=network.target

[Service]
ExecStart=/home/$USER/opcua_server/opcua_server_bin
Restart=always
User=$USER
Group=$USER

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable opcua_server.service
sudo systemctl start opcua_server.service

# 🐳 Création du fichier docker-compose.yml
cat <<EOF > docker-compose.yml
version: '3.8'
services:
  nodered:
    image: nodered/node-red
    restart: unless-stopped
    ports:
      - "1880:1880"

  mariadb:
    image: mariadb:latest
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: ec
    ports:
      - "3306:3306"

  phpmyadmin:
    image: phpmyadmin/phpmyadmin
    restart: unless-stopped
    environment:
      PMA_HOST: mariadb
      MYSQL_USER: ec
      MYSQL_PASSWORD: ec
    ports:
      - "8080:80"

  streamlit:
    image: python:3.9
    restart: unless-stopped
    working_dir: /app
    volumes:
      - ~/streamlit:/app
    command: ["python3", "-m", "streamlit", "run", "app.py", "--server.port=8501"]
    ports:
      - "8501:8501"
EOF

# 🚀 Lancement des Services Docker
docker-compose up -d --build

echo "✅ Installation Complète !"
