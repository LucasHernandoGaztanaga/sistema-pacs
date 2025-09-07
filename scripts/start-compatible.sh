#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}======================================"
echo "     PACS System - Iniciando"
echo "======================================${NC}"
echo ""

if command -v "docker" &> /dev/null && docker compose version &> /dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
    echo -e "${GREEN}Usando Docker Compose V2${NC}"
elif command -v "docker-compose" &> /dev/null; then
    COMPOSE_CMD="docker-compose"
    echo -e "${GREEN}Usando Docker Compose V1${NC}"
else
    echo -e "${RED}Error: Docker Compose no está instalado${NC}"
    exit 1
fi

echo -e "${YELLOW}Verificando requisitos...${NC}"

if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        cp .env.example .env
        echo -e "${GREEN}✓ Archivo .env creado${NC}"
    fi
fi

mkdir -p data/postgres data/ldap data/ldap-config data/dicom-storage data/logs/nginx
mkdir -p volumes/dcm4chee-arc volumes/wildfly volumes/oviyam volumes/nginx-cache

echo -e "${YELLOW}Construyendo imágenes si es necesario...${NC}"

if [ -f config/oviyam/Dockerfile ]; then
    $COMPOSE_CMD build oviyam || echo -e "${YELLOW}Oviyam se construirá al iniciar${NC}"
fi

echo -e "${YELLOW}Iniciando servicios PACS...${NC}"

$COMPOSE_CMD pull --ignore-pull-failures

echo -e "${BLUE}Iniciando servicios base...${NC}"
$COMPOSE_CMD up -d postgres ldap

sleep 10

echo -e "${BLUE}Iniciando DCM4CHEE...${NC}"
$COMPOSE_CMD up -d dcm4chee-arc

sleep 30

echo -e "${BLUE}Iniciando visualizadores...${NC}"
$COMPOSE_CMD up -d ohif oviyam

echo -e "${BLUE}Iniciando proxy Nginx...${NC}"
$COMPOSE_CMD up -d nginx ldap-admin

echo ""
$COMPOSE_CMD ps

echo ""
echo -e "${GREEN}======================================"
echo "    PACS System iniciado"
echo "======================================${NC}"
echo ""
echo -e "${BLUE}URLs de acceso:${NC}"
echo -e "  DCM4CHEE: ${GREEN}http://localhost:8080/dcm4chee-arc/ui2${NC}"
echo -e "  OHIF:     ${GREEN}http://localhost:3000${NC}"
echo -e "  Oviyam:   ${GREEN}http://localhost:8081/oviyam${NC}"
echo ""

