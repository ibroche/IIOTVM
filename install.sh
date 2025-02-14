#!/bin/bash

# Mise à jour et installation des paquets nécessaires
sudo apt update && sudo apt install -y docker.io docker-compose

# Création du dossier du projet
mkdir -p projet-opcua/streamlit_app projet-opcua/nodered_data projet-opcua/opcua_config

# Création du fichier docker-compose.yml
cat <<EOL > projet-opcua/docker-compose.yml
version: '3.8'

services:
  mariadb:
    image: mariadb:latest
    container_name: mariadb_container
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
    volumes:
      - mariadb_data:/var/lib/mysql
    ports:
      - "3306:3306"

  phpmyadmin:
    image: phpmyadmin/phpmyadmin:latest
    container_name: phpmyadmin_container
    restart: always
    environment:
      PMA_HOST: mariadb
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
    ports:
      - "8080:80"
    depends_on:
      - mariadb

  streamlit:
    image: python:3.9
    container_name: streamlit_container
    restart: always
    working_dir: /app
    volumes:
      - ./streamlit_app:/app
    command: >
      sh -c "pip install streamlit && streamlit run app.py --server.port=8501 --server.address=0.0.0.0"
    ports:
      - "8501:8501"

  nodered:
    image: nodered/node-red:latest
    container_name: nodered_container
    restart: always
    ports:
      - "1880:1880"
    volumes:
      - ./nodered_data:/data

  opcua_server:
    image: ghcr.io/freeopcua/opcua-android:latest
    container_name: opcua_server_container
    restart: always
    ports:
      - "4840:4840"
    volumes:
      - ./opcua_config:/config

volumes:
  mariadb_data:
EOL

# Création du fichier .env
cat <<EOL > projet-opcua/.env
MYSQL_ROOT_PASSWORD=ec
MYSQL_DATABASE=opcua_db
MYSQL_USER=opcua_user
MYSQL_PASSWORD=ec
EOL

# Création du fichier de configuration OPC UA
cat <<EOL > projet-opcua/opcua_config/config.json
{
    "server_name": "My OPC UA Server",
    "port": 4840,
    "security": "None",
    "endpoints": [
        "opc.tcp://0.0.0.0:4840"
    ]
}
EOL

# Création du fichier Streamlit app.py
cat <<EOL > projet-opcua/streamlit_app/app.py
import streamlit as st

st.title("Coucou")
st.write("Bienvenue sur mon application Streamlit!")
EOL

# Création du fichier README.md
cat <<EOL > projet-opcua/README.md
# Projet OPC UA avec Docker

## Services inclus
- **MariaDB** (Base de données)
- **PhpMyAdmin** (Gestion de la base)
- **Streamlit** (Application Python)
- **Node-RED** (Orchestration de flux)
- **OPC UA Server** (Serveur OPC UA intégré)

## Installation
1. Assurez-vous d'avoir Docker et Docker Compose installés.
2. Clonez ce projet et placez-vous dans le dossier.
3. Lancez la commande :

```bash
docker-compose up -d
```

4. Accédez aux services :
   - PhpMyAdmin : http://localhost:8080
   - Streamlit : http://localhost:8501
   - Node-RED : http://localhost:1880
   - OPC UA Server : `opc.tcp://localhost:4840`

Le serveur OPC UA est configuré selon `opcua_config/config.json`.
EOL

# Lancer Docker Compose
cd projet-opcua && docker-compose up -d

echo "Installation terminée. Tous les services sont en cours d'exécution."
