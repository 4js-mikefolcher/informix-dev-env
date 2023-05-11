# informix-dev-env
Docker Informix Genero Development Environment

## Prerequisites
 **Following packages must be installed**
 - Docker Desktop
 - Four Js License Manager 6

## Steps to Create Docker Containers
 - Download the Linux x86_64 Genero Studio Server 4.01 installer and put it into the genero/files subdirectory
 - Update the docker-compose.yaml build arguments: FGLLICNUM, PUBLICKEY, GST_PCK
 - Run './create-volumes.sh' to create the external volumes (on Windows, just run the two commands manually)
 - Run 'docker compose build' to build the docker containers
 - Run 'docker compose up' to start the docker containers

