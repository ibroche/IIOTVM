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

# 🌩 Installation de Cloudflared
echo "🌩 Installation de Cloudflared..."
sudo mkdir -p /usr/local/bin
curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
sudo chmod +x /usr/local/bin/cloudflared
cloudflared -v

# 🌍 Connexion à Cloudflare
echo "🌍 Connexion à Cloudflare... Suivez les instructions affichées."
cloudflared tunnel login

# 📌 Création du tunnel Cloudflare
echo "📌 Création du tunnel..."
cloudflared tunnel create mon-tunnel
TUNNEL_ID=$(cloudflared tunnel list | grep "mon-tunnel" | awk '{print $3}')

# 📌 Configuration du tunnel
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

# 🔄 Activation du service Cloudflared
cloudflared service install
sudo systemctl enable --now cloudflared

# 📌 Suppression complète des anciennes installations
echo "🧹 Nettoyage complet d'Open62541..."
sudo systemctl stop opcua_server.service || true
sudo systemctl disable opcua_server.service || true
sudo rm -rf ~/open62541
sudo rm -rf /usr/local/include/open62541*
sudo rm -rf /usr/local/lib/libopen62541*
sudo rm -rf /etc/systemd/system/opcua_server.service
sudo systemctl daemon-reload

# 📌 Installation des Dépendances pour Open62541
echo "🔧 Installation des dépendances..."
sudo apt install -y cmake gcc git libssl-dev libjansson-dev pkg-config python3 python3-pip python3-dev

# 📌 Installation propre de Open62541
echo "⚙️ Téléchargement et compilation de Open62541..."
mkdir -p ~/open62541
cd ~/open62541
git clone https://github.com/open62541/open62541.git .
git checkout v1.3.5

# 📌 Suppression du répertoire `build` s'il existe
rm -rf build
mkdir build && cd build

# 📌 Configuration et Compilation
cmake .. -DUA_ENABLE_AMALGAMATION=ON
make -j$(nproc)
sudo make install
sudo ldconfig

# 📌 Vérification de l'installation
if [ ! -f "/usr/local/include/open62541.h" ]; then
    echo "❌ Erreur : Open62541 n'a pas été installé correctement."
    exit 1
fi

# 📌 Création du Répertoire OPC UA
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

# 📌 Création du Serveur OPC UA
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

# 📌 Compilation du Serveur OPC UA
gcc -std=c99 -o ~/opcua_server/opcua_server_bin ~/opcua_server/opcua_server.c \
    -I/usr/local/include -L/usr/local/lib $(pkg-config --cflags --libs open62541) -ljansson

# 📌 Création d'un Service systemd pour OPC UA
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

# 📌 Activation du Service OPC UA
sudo systemctl daemon-reload
sudo systemctl enable opcua_server.service
sudo systemctl start opcua_server.service
echo "✅ Serveur OPC UA installé et démarré avec succès !"

# 📌 Vérification et Création de `docker-compose.yml`
if [ ! -f "docker-compose.yml" ]; then
    echo "⚠️ Fichier docker-compose.yml introuvable, création en cours..."
    cat <<EOF > docker-compose.yml
version: '3'
services:
  nodered:
    image: nodered/node-red
    restart: unless-stopped
    ports:
      - "1880:1880"

  streamlit:
    image: python:3.9
    restart: unless-stopped
    ports:
      - "8501:8501"

  phpmyadmin:
    image: phpmyadmin/phpmyadmin
    restart: unless-stopped
    ports:
      - "8080:80"
EOF
fi

# 🚀 Lancement des Services Docker
docker-compose up -d --build
echo "✅ Installation Complète !"
