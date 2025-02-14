#!/bin/bash

# 🔥 Demander le nom de domaine personnalisé
echo "🔹 Entrez votre domaine Cloudflare (ex: votre-domaine.com) :"
read DOMAIN

# 🛠 Configuration par défaut
TUNNEL_NAME="mon-tunnel"

# 🚀 Démarrage de l'installation
echo "🚀 Installation en cours... Patientez."

# 📌 Mise à jour du système
echo "🔍 Mise à jour du système..."
sudo apt update && sudo apt upgrade -y

# 🐳 Installation de Docker + Docker Compose
echo "🐳 Installation de Docker..."
sudo apt install -y docker.io docker-compose

# 🌩 Installation de Cloudflared (nouvelle méthode)
echo "🌩 Installation de Cloudflared..."
sudo mkdir -p /usr/local/bin
curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
sudo chmod +x /usr/local/bin/cloudflared
cloudflared -v

# 🌍 Connexion à Cloudflare
echo "🌍 Connexion à Cloudflare... Suivez les instructions affichées."
cloudflared tunnel login

# 📌 Création du tunnel Cloudflare
echo "📌 Création du tunnel $TUNNEL_NAME..."
cloudflared tunnel create $TUNNEL_NAME
TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $3}')

# 📌 Configuration Cloudflare
echo "⚙️ Configuration du tunnel Cloudflared..."
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
echo "🌐 Ajout des routes DNS..."
cloudflared tunnel route dns $TUNNEL_ID nodered.$DOMAIN
cloudflared tunnel route dns $TUNNEL_ID streamlit.$DOMAIN
cloudflared tunnel route dns $TUNNEL_ID phpmyadmin.$DOMAIN
cloudflared tunnel route dns $TUNNEL_ID opcua.$DOMAIN

# 🔄 Activation et démarrage du service Cloudflared
cloudflared service install
sudo systemctl enable --now cloudflared

# 📌 Installation des dépendances pour Open62541
echo "🔧 Installation des dépendances..."
sudo apt install -y cmake gcc git libssl-dev libjansson-dev pkg-config

# 📌 Télécharger et Compiler Open62541
echo "⚙️ Téléchargement et compilation d'open62541..."
mkdir -p /usr/local/src
cd /usr/local/src
if [ ! -d "open62541" ]; then
    sudo git clone https://github.com/open62541/open62541.git
fi
cd open62541
sudo git checkout v1.3.5
sudo mkdir -p build
cd build
sudo cmake .. -DUA_ENABLE_AMALGAMATION=ON
sudo make -j$(nproc)
sudo make install
sudo ldconfig

# 📌 Vérification de l'installation de Open62541
if [ ! -f "/usr/local/include/open62541.h" ]; then
    echo "❌ Erreur : Open62541 n'a pas été installé correctement."
    exit 1
fi

# 📌 Ajout des chemins pour open62541
export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig"
export C_INCLUDE_PATH="/usr/local/include"
export LIBRARY_PATH="/usr/local/lib"
export LD_LIBRARY_PATH="/usr/local/lib"

# 📌 Création du répertoire OPC UA + JSON
mkdir -p opcua_server
cat <<EOF > opcua_server/variables.json
{
  "variables": [
    { "name": "temperature", "type": "Double", "initialValue": 25.0 },
    { "name": "status", "type": "Boolean", "initialValue": true },
    { "name": "speed", "type": "Int32", "initialValue": 100 }
  ]
}
EOF

# 📌 Création du serveur OPC UA
cat <<EOF > opcua_server/opcua_server.c
#include <open62541/server.h>
#include <open62541/server_config_default.h>
#include <open62541/plugin/log_stdout.h>
#include <jansson.h>

static void addVariable(UA_Server *server, char *name, char *type, json_t *initialValue) {
    UA_VariableAttributes attr = UA_VariableAttributes_default;
    UA_Variant value;

    if (strcmp(type, "Boolean") == 0 && json_is_boolean(initialValue)) {
        UA_Boolean val = json_boolean_value(initialValue);
        UA_Variant_setScalar(&value, &val, &UA_TYPES[UA_TYPES_BOOLEAN]);
    } else if (strcmp(type, "Int32") == 0 && json_is_integer(initialValue)) {
        UA_Int32 val = (UA_Int32) json_integer_value(initialValue);
        UA_Variant_setScalar(&value, &val, &UA_TYPES[UA_TYPES_INT32]);
    } else if (strcmp(type, "Double") == 0 && json_is_number(initialValue)) {
        UA_Double val = (UA_Double) json_real_value(initialValue);
        UA_Variant_setScalar(&value, &val, &UA_TYPES[UA_TYPES_DOUBLE]);
    } else {
        return;
    }

    attr.value = value;
    attr.displayName = UA_LOCALIZEDTEXT("en-US", name);
    attr.accessLevel = UA_ACCESSLEVELMASK_READ | UA_ACCESSLEVELMASK_WRITE;

    UA_NodeId nodeId = UA_NODEID_STRING(1, name);
    UA_QualifiedName qName = UA_QUALIFIEDNAME(1, name);
    UA_Server_addVariableNode(server, nodeId, UA_NODEID_NUMERIC(0, UA_NS0ID_OBJECTSFOLDER),
                              UA_NODEID_NUMERIC(0, UA_NS0ID_HASCOMPONENT),
                              qName, UA_NODEID_NUMERIC(0, UA_NS0ID_BASEDATAVARIABLETYPE),
                              attr, NULL, NULL);
}

int main(void) {
    UA_Server *server = UA_Server_new();
    UA_ServerConfig_setDefault(UA_Server_getConfig(server));

    UA_StatusCode status = UA_Server_run(server, &(UA_Boolean){true});
    UA_Server_delete(server);
    return status == UA_STATUSCODE_GOOD ? 0 : 1;
}
EOF

# 📌 Compilation du serveur OPC UA
gcc -std=c99 -o opcua_server/opcua_server_bin opcua_server/opcua_server.c \
    -I/usr/local/include -L/usr/local/lib $(pkg-config --cflags --libs open62541) -ljansson

# 📌 Vérification et génération de docker-compose.yml si absent
if [ ! -f "docker-compose.yml" ]; then
    echo "⚠️ Fichier docker-compose.yml introuvable, génération en cours..."
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

  opcua:
    build: ./opcua_server
    restart: unless-stopped
    ports:
      - "4840:4840"
EOF
fi

# 🚀 Lancement des services Docker
echo "🚀 Lancement des services..."
docker-compose up -d --build

echo "✅ Installation terminée !"
