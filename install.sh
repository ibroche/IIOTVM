#!/bin/bash

# Mise à jour et installation des paquets nécessaires
sudo apt update && sudo apt install -y docker.io docker-compose git build-essential cmake

# Installation d'open62541
mkdir -p ~/opcua_server && cd ~/opcua_server
git clone https://github.com/open62541/open62541.git
cd open62541
git checkout v1.3.5
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -DUA_ENABLE_AMALGAMATION=ON
make -j$(nproc)
sudo make install

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
- **OPC UA Server** (Serveur OPC UA basé sur open62541, installé hors Docker)

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

Le serveur OPC UA (open62541) est installé en dehors de Docker et doit être configuré manuellement.
EOL

# Lancer Docker Compose
cd projet-opcua && docker-compose up -d

echo "Installation terminée. Tous les services sont en cours d'exécution. Le serveur OPC UA open62541 est installé hors Docker."
