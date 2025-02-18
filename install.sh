#!/bin/bash
set -e

echo "=== Configuration initiale ==="
read -p "Entrez votre email pour ACME (Let’s Encrypt) : " ACME_EMAIL
read -p "Entrez votre domaine de base (ex: ibroche.com) : " BASE_DOMAIN

# Calcul automatique des sous-domaines
PMA_DOMAIN="pma.${BASE_DOMAIN}"
STREAMLIT_DOMAIN="streamlit.${BASE_DOMAIN}"
NODERED_DOMAIN="nodered.${BASE_DOMAIN}"

# Identifiants et base de données par défaut
MYSQL_USER="ec"
MYSQL_PASSWORD="ec"
MYSQL_DATABASE="IOT_DB"

echo "=== Création des répertoires nécessaires ==="
mkdir -p streamlit letsencrypt

echo "=== Création du fichier mosquitto.conf ==="
cat <<'EOF' > mosquitto.conf
allow_anonymous true
listener 1883
persistence true
persistence_location /mosquitto/data/
log_dest file /mosquitto/log/mosquitto.log
EOF

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
      PMA_USER: ${MYSQL_USER}
      PMA_PASSWORD: ${MYSQL_PASSWORD}
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

volumes:
  mariadb_data:
  nodered_data:

networks:
  app-network:
    driver: bridge
EOF

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

echo "=== Création du fichier streamlit/app.py (placeholder) ==="
cat <<'EOF' > streamlit/app.py
# Streamlit app placeholder.
# Fonctionnalités à ajouter prochainement.
EOF

echo "=== Lancement de l'environnement avec docker-compose ==="
docker-compose up -d

echo "Installation terminée. Tous les services sont lancés."
