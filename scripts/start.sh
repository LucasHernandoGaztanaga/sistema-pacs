#!/bin/bash

# PACS System Start Script
# Sistema de inicio completo con validaciones

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================"
echo "     PACS System - Iniciando"
echo "======================================${NC}"
echo ""

# Función para verificar requisitos
check_requirements() {
    echo -e "${YELLOW}Verificando requisitos...${NC}"
    
    # Verificar Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Error: Docker no está instalado${NC}"
        echo "Por favor instale Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    # Verificar Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        echo -e "${RED}Error: Docker Compose no está instalado${NC}"
        echo "Por favor instale Docker Compose: https://docs.docker.com/compose/install/"
        exit 1
    fi
    
    # Verificar archivo .env
    if [ ! -f .env ]; then
        echo -e "${YELLOW}Archivo .env no encontrado. Creando desde .env.example...${NC}"
        if [ -f .env.example ]; then
            cp .env.example .env
            echo -e "${GREEN}✓ Archivo .env creado${NC}"
            echo -e "${YELLOW}Por favor, edite el archivo .env con sus configuraciones${NC}"
            exit 0
        else
            echo -e "${RED}Error: No se encuentra .env.example${NC}"
            exit 1
        fi
    fi
    
    echo -e "${GREEN}✓ Todos los requisitos cumplidos${NC}"
}

# Función para crear directorios necesarios
create_directories() {
    echo -e "${YELLOW}Creando directorios necesarios...${NC}"
    
    # Crear directorios de datos
    mkdir -p data/postgres
    mkdir -p data/ldap
    mkdir -p data/ldap-config
    mkdir -p data/dicom-storage
    mkdir -p data/logs/nginx
    
    # Crear directorios de volúmenes
    mkdir -p volumes/dcm4chee-arc
    mkdir -p volumes/wildfly
    mkdir -p volumes/oviyam
    mkdir -p volumes/nginx-cache
    
    # Establecer permisos
    chmod -R 755 data/
    chmod -R 755 volumes/
    
    echo -e "${GREEN}✓ Directorios creados${NC}"
}

# Función para verificar puertos
check_ports() {
    echo -e "${YELLOW}Verificando disponibilidad de puertos...${NC}"
    
    local ports=("5432" "389" "636" "8080" "8081" "3000" "11112" "80")
    local all_clear=true
    
    for port in "${ports[@]}"; do
        if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
            echo -e "${RED}✗ Puerto $port ya está en uso${NC}"
            all_clear=false
        fi
    done
    
    if [ "$all_clear" = true ]; then
        echo -e "${GREEN}✓ Todos los puertos están disponibles${NC}"
    else
        echo -e "${RED}Por favor libere los puertos en uso antes de continuar${NC}"
        read -p "¿Desea continuar de todos modos? (s/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            exit 1
        fi
    fi
}

# Función para construir imágenes si es necesario
build_images() {
    echo -e "${YELLOW}Construyendo imágenes personalizadas...${NC}"
    
    # Construir Oviyam si el Dockerfile existe
    if [ -f config/oviyam/Dockerfile ]; then
        echo "Construyendo imagen de Oviyam..."
        docker-compose build oviyam
        echo -e "${GREEN}✓ Imagen de Oviyam construida${NC}"
    fi
}

# Función para iniciar servicios
start_services() {
    echo -e "${YELLOW}Iniciando servicios PACS...${NC}"
    echo ""
    
    # Pull de imágenes
    echo "Descargando imágenes Docker necesarias..."
    docker-compose pull --ignore-pull-failures
    
    # Iniciar servicios en orden
    echo -e "${BLUE}Iniciando servicios base...${NC}"
    docker-compose up -d postgres ldap
    
    echo "Esperando que PostgreSQL esté listo..."
    sleep 10
    
    echo -e "${BLUE}Iniciando DCM4CHEE...${NC}"
    docker-compose up -d dcm4chee-arc
    
    echo "Esperando que DCM4CHEE se inicialice (esto puede tomar 2-3 minutos)..."
    sleep 30
    
    echo -e "${BLUE}Iniciando visualizadores...${NC}"
    docker-compose up -d ohif oviyam
    
    echo -e "${BLUE}Iniciando proxy Nginx...${NC}"
    docker-compose up -d nginx
    
    # Opcional: LDAP Admin
    docker-compose up -d ldap-admin
    
    echo -e "${GREEN}✓ Todos los servicios iniciados${NC}"
}

# Función para verificar estado
check_status() {
    echo ""
    echo -e "${YELLOW}Verificando estado de los servicios...${NC}"
    echo ""
    
    docker-compose ps
    
    echo ""
    echo -e "${GREEN}======================================"
    echo "    PACS System iniciado con éxito"
    echo "======================================${NC}"
    echo ""
    echo -e "${BLUE}URLs de acceso:${NC}"
    echo -e "  DCM4CHEE Admin: ${GREEN}http://localhost:8080/dcm4chee-arc/ui2${NC}"
    echo -e "  OHIF Viewer:    ${GREEN}http://localhost:3000${NC}"
    echo -e "  Oviyam Viewer:  ${GREEN}http://localhost:8081/oviyam${NC}"
    echo -e "  LDAP Admin:     ${GREEN}http://localhost:6080${NC}"
    echo -e "  Nginx Proxy:    ${GREEN}http://localhost${NC}"
    echo ""
    echo -e "${BLUE}Configuración DICOM:${NC}"
    echo -e "  AE Title: ${GREEN}DCM4CHEE${NC}"
    echo -e "  DICOM Port: ${GREEN}11112${NC}"
    echo -e "  Host: ${GREEN}localhost${NC}"
    echo ""
    echo -e "${YELLOW}Nota: DCM4CHEE puede tardar hasta 3 minutos en estar completamente operativo${NC}"
    echo ""
}

# Main
main() {
    check_requirements
    create_directories
    check_ports
    build_images
    start_services
    check_status
}

# Ejecutar
main