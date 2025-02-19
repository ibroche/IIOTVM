#!/bin/bash
set -e

# --- Installation de Docker & Docker Compose ---
echo "Mise à jour des paquets et installation de Docker et Docker Compose..."
sudo apt-get update
sudo apt-get install -y docker.io docker-compose
sudo systemctl enable docker --now

# --- Configuration pour Docker et Traefik ---
echo "=== Configuration initiale pour Docker et Traefik ==="
read -p "Entrez votre email pour ACME (Let's Encrypt) : " ACME_EMAIL
read -p "Entrez votre domaine de base (ex: ibroche.com) : " BASE_DOMAIN

# Calcul automatique des sous-domaines
PMA_DOMAIN="pma.${BASE_DOMAIN}"
STREAMLIT_DOMAIN="streamlit.${BASE_DOMAIN}"
NODERED_DOMAIN="nodered.${BASE_DOMAIN}"

# Identifiants et base de données par défaut
MYSQL_USER="ec"
MYSQL_PASSWORD="ec"
MYSQL_DATABASE="IOT_DB"

# Exporter les variables pour docker-compose et générer un fichier .env
export ACME_EMAIL BASE_DOMAIN PMA_DOMAIN STREAMLIT_DOMAIN NODERED_DOMAIN MYSQL_USER MYSQL_PASSWORD MYSQL_DATABASE
cat <<EOF > .env
ACME_EMAIL=${ACME_EMAIL}
BASE_DOMAIN=${BASE_DOMAIN}
PMA_DOMAIN=${PMA_DOMAIN}
STREAMLIT_DOMAIN=${STREAMLIT_DOMAIN}
NODERED_DOMAIN=${NODERED_DOMAIN}
MYSQL_USER=${MYSQL_USER}
MYSQL_PASSWORD=${MYSQL_PASSWORD}
MYSQL_DATABASE=${MYSQL_DATABASE}
EOF

echo "=== Création des répertoires nécessaires ==="
mkdir -p streamlit letsencrypt

# --- Création du fichier mosquitto.conf ---
echo "=== Création du fichier mosquitto.conf ==="
# Supprimer le fichier existant s'il existe (pour éviter les problèmes de permission)
if [ -f mosquitto.conf ]; then
    sudo rm -f mosquitto.conf
fi
cat <<'EOF' > mosquitto.conf
allow_anonymous true
listener 1883
persistence true
persistence_location /mosquitto/data/
log_dest file /mosquitto/log/mosquitto.log
EOF

# --- Création du fichier docker-compose.yml ---
echo "=== Création du fichier docker-compose.yml ==="
cat <<EOF > docker-compose.yml
version: '3.8'

services:
  traefik:
    image: traefik:v2.9
    command:
      - "--api.insecure=false"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.myresolver.acme.tlschallenge=true"
      - "--certificatesresolvers.myresolver.acme.email=${ACME_EMAIL}"
      - "--certificatesresolvers.myresolver.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "./letsencrypt:/letsencrypt"
    networks:
      - app-network

  mariadb:
    image: mariadb:latest
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_PASSWORD}
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
    volumes:
      - mariadb_data:/var/lib/mysql
    networks:
      - app-network

  phpmyadmin:
    image: phpmyadmin/phpmyadmin:latest
    environment:
      PMA_HOST: mariadb
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.phpmyadmin.rule=Host(\`${PMA_DOMAIN}\`)"
      - "traefik.http.routers.phpmyadmin.entrypoints=websecure"
      - "traefik.http.routers.phpmyadmin.tls.certresolver=myresolver"
    networks:
      - app-network

  streamlit:
    build: ./streamlit
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.streamlit.rule=Host(\`${STREAMLIT_DOMAIN}\`)"
      - "traefik.http.routers.streamlit.entrypoints=websecure"
      - "traefik.http.routers.streamlit.tls.certresolver=myresolver"
    networks:
      - app-network

  nodered:
    image: nodered/node-red:latest
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.nodered.rule=Host(\`${NODERED_DOMAIN}\`)"
      - "traefik.http.routers.nodered.entrypoints=websecure"
      - "traefik.http.routers.nodered.tls.certresolver=myresolver"
    volumes:
      - nodered_data:/data
    networks:
      - app-network

  mqtt:
    container_name: mosquitto
    image: eclipse-mosquitto:latest
    restart: always
    ports:
      - "1883:1883"
    networks:
      - app-network
    volumes:
      - ./mosquitto.conf:/mosquitto/config/mosquitto.conf
      - /mosquitto/data
      - /mosquitto/log
   portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    command: -H unix:///var/run/docker.sock
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.portainer.rule=Host(`portainer.${BASE_DOMAIN}`)"
      - "traefik.http.routers.portainer.entrypoints=websecure"
      - "traefik.http.routers.portainer.tls.certresolver=myresolver"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    networks:
      - app-network

volumes:
  mariadb_data:
  nodered_data:
  portainer_data:

networks:
  app-network:
    driver: bridge
EOF

# --- Création du Dockerfile pour le service Streamlit ---
echo "=== Création du Dockerfile pour le service Streamlit ==="
mkdir -p streamlit
cat <<'EOF' > streamlit/Dockerfile
FROM python:3.9-slim

WORKDIR /app

# Installation de Streamlit
RUN pip install streamlit

# Copie du fichier app.py dans le container
COPY app.py .

EXPOSE 8501

# Lancement de Streamlit sur le port 8501 avec CORS désactivé
CMD ["streamlit", "run", "app.py", "--server.port=8501", "--server.enableCORS=false"]
EOF

# --- Création du fichier streamlit/app.py (placeholder) ---
echo "=== Création du fichier streamlit/app.py (placeholder) ==="
cat <<'EOF' > streamlit/app.py
# Streamlit app placeholder.
# Fonctionnalités à ajouter prochainement.
EOF

# --- Lancement de l'environnement Docker ---
echo "=== Lancement de l'environnement Docker avec docker-compose ==="
sudo docker-compose up -d
echo "=== Docker et services lancés ==="

# --- Installation et configuration OPC UA (open62541) ---
read -p "Voulez-vous installer et configurer un serveur OPC UA (open62541) sur la VM ? (y/n) : " INSTALL_OPCUA
if [[ "$INSTALL_OPCUA" =~ ^[Yy]$ ]]; then
    echo "Arrêt temporaire des services Docker pour libérer des ressources..."
    sudo docker-compose down
    echo "Installation de open62541..."
    sudo apt-get update
    sudo apt-get install -y git build-essential gcc pkg-config cmake python3 \
      libmbedtls-dev check libsubunit-dev python3-sphinx graphviz python3-sphinx-rtd-theme \
      libavahi-client-dev libavahi-common-dev

    # Si le dossier open62541 existe déjà, on le met à jour, sinon on le clone
    if [ -d "open62541" ]; then
        echo "Le dossier open62541 existe déjà, mise à jour..."
        cd open62541
        git pull
        git submodule update --init --recursive
    else
        git clone https://github.com/open62541/open62541.git
        cd open62541
        git submodule update --init --recursive
    fi

    # Si le dossier build existe déjà, on le supprime pour repartir sur une base propre
    if [ -d "build" ]; then
        echo "Le dossier build existe déjà, suppression..."
        rm -rf build
    fi

    mkdir build && cd build
    cmake ..
    make -j$(nproc)
    sudo make install
    sudo ldconfig
    cd ../..
    echo "open62541 a été installé avec succès sur la VM."

    # Création du fichier de configuration JSON pour le serveur OPC UA
    echo "=== Création du fichier de configuration OPC UA (opcua_config.json) ==="
    cat <<'EOF' > opcua_config.json
{
  "server": {
    "name": "My OPC UA Server",
    "variables": {
      "temperature": 25.0,
      "pressure": 1013.25,
      "humidity": 45.0,
      "status": true,
      "device": "Sensor_A1"
    }
  }
}

EOF

    # Installation de cJSON
    sudo apt-get install libcjson-dev

    # Création d'un exemple de serveur OPC UA qui lit le fichier JSON
    echo "=== Création de l'exemple de serveur OPC UA (opcua_server.c) ==="
    cat <<'EOF' > opcua_server.c
#include <open62541/server.h>
#include <open62541/server_config_default.h>
#include <stdio.h>
#include <stdlib.h>
#include <cjson/cJSON.h>

static void addVariablesFromConfig(UA_Server *server, const char *configJson) {
    cJSON *json = cJSON_Parse(configJson);
    if (!json) {
        printf("Erreur de parsing JSON\n");
        return;
    }

    cJSON *serverObj = cJSON_GetObjectItem(json, "server");
    if (!serverObj) {
        printf("Objet 'server' non trouvé dans le JSON\n");
        cJSON_Delete(json);
        return;
    }

    cJSON *variables = cJSON_GetObjectItem(serverObj, "variables");
    if (!variables) {
        printf("Objet 'variables' non trouvé dans le JSON\n");
        cJSON_Delete(json);
        return;
    }

    cJSON *var = NULL;
    cJSON_ArrayForEach(var, variables) {
        const char *varName = var->string;
        UA_VariableAttributes attr = UA_VariableAttributes_default;
        UA_NodeId nodeId = UA_NODEID_STRING(1, (char *)varName);
        UA_QualifiedName qname = UA_QUALIFIEDNAME(1, (char *)varName);

        // Détecte le type de la variable dans le JSON et configure le UA_Variant
        if(cJSON_IsNumber(var)) {
            UA_Double val = var->valuedouble;
            UA_Variant_setScalar(&attr.value, &val, &UA_TYPES[UA_TYPES_DOUBLE]);
            attr.dataType = UA_TYPES[UA_TYPES_DOUBLE].typeId;
            attr.valueRank = -1;
        } else if(cJSON_IsBool(var)) {
            UA_Boolean val = cJSON_IsTrue(var);
            UA_Variant_setScalar(&attr.value, &val, &UA_TYPES[UA_TYPES_BOOLEAN]);
            attr.dataType = UA_TYPES[UA_TYPES_BOOLEAN].typeId;
            attr.valueRank = -1;
        } else if(cJSON_IsString(var)) {
            const char *str = cJSON_GetStringValue(var);
            UA_String uaStr = UA_STRING_ALLOC(str);
            UA_Variant_setScalar(&attr.value, &uaStr, &UA_TYPES[UA_TYPES_STRING]);
            attr.dataType = UA_TYPES[UA_TYPES_STRING].typeId;
            attr.valueRank = -1;
        } else {
            printf("Type non supporté pour la variable '%s'\n", varName);
            continue;
        }

        // Définir le nom d'affichage et la description
        attr.displayName = UA_LOCALIZEDTEXT("en-US", (char *)varName);
        attr.description = UA_LOCALIZEDTEXT("en-US", (char *)varName);

        UA_Server_addVariableNode(server, nodeId,
            UA_NODEID_NUMERIC(0, UA_NS0ID_OBJECTSFOLDER),
            UA_NODEID_NUMERIC(0, UA_NS0ID_ORGANIZES),
            qname, UA_NODEID_NULL, attr, NULL, NULL);

        printf("Variable '%s' ajoutée.\n", varName);
    }

    cJSON_Delete(json);
}

static UA_StatusCode startOpcUaServer(const char *configFilePath) {
    UA_Server *server = UA_Server_new();
    UA_ServerConfig_setDefault(UA_Server_getConfig(server));

    // Lecture du fichier JSON de configuration
    FILE *fp = fopen(configFilePath, "r");
    if(!fp) {
        printf("Erreur : impossible d'ouvrir le fichier JSON: %s\n", configFilePath);
        return UA_STATUSCODE_BADNOTFOUND;
    }
    fseek(fp, 0, SEEK_END);
    long fileSize = ftell(fp);
    rewind(fp);
    char *jsonContent = malloc(fileSize + 1);
    if(!jsonContent) {
        fclose(fp);
        return UA_STATUSCODE_BADOUTOFMEMORY;
    }
    fread(jsonContent, 1, fileSize, fp);
    jsonContent[fileSize] = '\0';
    fclose(fp);

    printf("Configuration JSON chargée :\n%s\n", jsonContent);

    // Ici, vous pourriez analyser le JSON pour extraire des variables
    addVariablesFromConfig(server, jsonContent);
    free(jsonContent);

    volatile UA_Boolean running = true;
    UA_StatusCode retval = UA_Server_run(server, &running);
    UA_Server_delete(server);
    return retval;
}

int main(void) {
    const char *configFilePath = "opcua_config.json";
    return (int)startOpcUaServer(configFilePath);
}


EOF

    echo "Exemple de serveur OPC UA (opcua_server.c) créé."

    # Compilation du serveur OPC UA avec inclusion du chemin d'en-tête adéquat
    gcc -std=c99 -I/usr/local/include -L/usr/local/lib -o opcua_server opcua_server.c -lopen62541 -lcjson

    echo "Serveur OPC UA compilé avec succès (exécutable 'opcua_server')."

    # Démarrage du serveur OPC UA en arrière-plan
    ./opcua_server &
    echo "Serveur OPC UA démarré en arrière-plan. Vous pouvez modifier 'opcua_config.json' pour changer les variables."
else
    echo "Installation et configuration OPC UA ignorées."
fi
echo "Relance des services Docker..."
sudo docker-compose up -d
echo "Installation terminée. Tous les services Docker sont lancés, et le serveur OPC UA a été configuré selon 'opcua_config.json' si vous l'avez choisi."
