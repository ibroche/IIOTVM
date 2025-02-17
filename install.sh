#!/bin/bash

set -e

# Demande du domaine à l'utilisateur
echo "Veuillez entrer votre nom de domaine (ex: example.com) :"
read domain_name

# Variables
docker_compose_file="docker-compose.yml"
mosquitto_conf="mosquitto.conf"
traefik_config="traefik.yml"
ftp_user="ec"
ftp_pass="ec"

# Vérification de l'installation des prérequis
if ! command -v docker &> /dev/null; then
    echo "Docker n'est pas installé. Installation en cours..."
    curl -fsSL https://get.docker.com | bash
    sudo systemctl start docker
    sudo systemctl enable docker
fi

if ! command -v docker-compose &> /dev/null; then
    echo "Docker Compose n'est pas installé. Installation en cours..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
fi

# Ouverture des ports nécessaires
sudo ufw allow 20,21,22,80,443,1880,1883,8080,8501/tcp

# Création des répertoires et fichiers nécessaires
mkdir -p "mqtt_data" "mqtt_log" "streamlit" "letsencrypt"

# Création du fichier mosquitto.conf si non existant
if [ ! -f "$mosquitto_conf" ]; then
    cat <<EOL > "$mosquitto_conf"
allow_anonymous true
listener 1883
persistence true
persistence_location /mosquitto/data/
log_dest file /mosquitto/log/mosquitto.log
EOL
    echo "Fichier mosquitto.conf créé."
fi

# Création du fichier traefik.yml si non existant
if [ ! -f "$traefik_config" ]; then
    cat <<EOL > "$traefik_config"
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

providers:
  docker:
    exposedByDefault: false

certificatesResolvers:
  myresolver:
    acme:
      email: certbot@$domain_name
      storage: /letsencrypt/acme.json
      tlsChallenge: {}
EOL
    echo "Fichier traefik.yml créé."
fi

# Configuration des permissions pour Traefik SSL
sudo touch letsencrypt/acme.json
sudo chmod 600 letsencrypt/acme.json

# Création du fichier docker-compose.yml si non existant
if [ ! -f "$docker_compose_file" ]; then
    cat <<EOL > "$docker_compose_file"
version: '3.8'

services:
  traefik:
    image: traefik:v2.9
    container_name: traefik
    restart: always
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./traefik.yml:/traefik.yml
      - ./letsencrypt:/letsencrypt
    command:
      - "--api.dashboard=true"
      - "--providers.docker"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.myresolver.acme.tlschallenge=true"
      - "--certificatesresolvers.myresolver.acme.email=certbot@$domain_name"
      - "--certificatesresolvers.myresolver.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"
      - "443:443"
    networks:
      - backend

  mariadb:
    image: mariadb:latest
    container_name: mariadb
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: ec
      MYSQL_DATABASE: ec
      MYSQL_USER: ec
      MYSQL_PASSWORD: ec
    volumes:
      - mariadb_data:/var/lib/mysql
    networks:
      - backend

  phpmyadmin:
    image: phpmyadmin/phpmyadmin:latest
    container_name: phpmyadmin
    restart: always
    environment:
      PMA_HOST: mariadb
      MYSQL_ROOT_PASSWORD: ec
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.phpmyadmin.rule=Host(`phpmyadmin.$domain_name`)"
      - "traefik.http.routers.phpmyadmin.entrypoints=websecure"
      - "traefik.http.routers.phpmyadmin.tls.certresolver=myresolver"
    networks:
      - backend

  mqtt:
    image: eclipse-mosquitto:latest
    container_name: mqtt
    restart: always
    volumes:
      - ./mosquitto.conf:/mosquitto/config/mosquitto.conf
      - mqtt_data:/mosquitto/data
      - mqtt_log:/mosquitto/log
    networks:
      - backend

  nodered:
    image: nodered/node-red:latest
    container_name: nodered
    restart: always
    volumes:
      - nodered_data:/data
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.nodered.rule=Host(`nodered.$domain_name`)"
      - "traefik.http.routers.nodered.entrypoints=websecure"
      - "traefik.http.routers.nodered.tls.certresolver=myresolver"
    networks:
      - backend

  streamlit:
    image: python:3.9
    container_name: streamlit
    restart: always
    volumes:
      - ./streamlit:/app
    working_dir: /app
    command: ["bash", "-c", "pip install streamlit && streamlit run app.py --server.port 8501 --server.enableCORS false --server.headless true"]
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.streamlit.rule=Host(`streamlit.$domain_name`)"
      - "traefik.http.routers.streamlit.entrypoints=websecure"
      - "traefik.http.routers.streamlit.tls.certresolver=myresolver"
    networks:
      - backend

volumes:
  mariadb_data:
  mqtt_data:
  mqtt_log:
  nodered_data:
  letsencrypt:

networks:
  backend:
EOL
    echo "Fichier docker-compose.yml créé."
fi

# Vérification et démarrage des services avec Docker Compose
if [ -f "$docker_compose_file" ]; then
    echo "Lancement des services avec Docker Compose..."
    docker-compose up -d
else
    echo "Fichier docker-compose.yml introuvable. Assurez-vous qu'il est bien présent."
    exit 1
fi

echo "Installation terminée ! Tous les services sont lancés avec HTTPS sécurisé par Traefik."
