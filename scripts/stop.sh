#!/bin/bash

# PACS System Stop Script
# Detención segura del sistema con opciones

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables
REMOVE_VOLUMES=false
BACKUP_BEFORE_STOP=false

echo -e "${BLUE}======================================"
echo "     PACS System - Deteniendo"
echo "======================================${NC}"
echo ""

# Procesar argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        --remove-volumes|-v)
            REMOVE_VOLUMES=true
            shift
            ;;
        --backup|-b)
            BACKUP_BEFORE_STOP=true
            shift
            ;;
        --help|-h)
            echo "Uso: $0 [opciones]"
            echo ""
            echo "Opciones:"
            echo "  -b, --backup         Realizar backup antes de detener"
            echo "  -v, --remove-volumes Eliminar volúmenes (CUIDADO: borra datos)"
            echo "  -h, --help          Mostrar esta ayuda"
            echo ""
            exit 0
            ;;
        *)
            echo -e "${RED}Opción desconocida: $1${NC}"
            echo "Use $0 --help para ver las opciones disponibles"
            exit 1
            ;;
    esac
done

# Función para verificar si hay contenedores corriendo
check_running_containers() {
    local running=$(docker-compose ps -q 2>/dev/null | wc -l)
    if [ "$running" -eq 0 ]; then
        echo -e "${YELLOW}No hay contenedores PACS corriendo${NC}"
        exit 0
    fi
    echo -e "${GREEN}Se encontraron $running contenedores corriendo${NC}"
}

# Función para hacer backup si se solicita
perform_backup() {
    if [ "$BACKUP_BEFORE_STOP" = true ]; then
        echo -e "${YELLOW}Realizando backup antes de detener...${NC}"
        if [ -f scripts/backup.sh ]; then
            bash scripts/backup.sh
            echo -e "${GREEN}✓ Backup completado${NC}"
        else
            echo -e "${RED}Script de backup no encontrado${NC}"
            read -p "¿Continuar sin backup? (s/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Ss]$ ]]; then
                exit 1
            fi
        fi
    fi
}

# Función para detener servicios
stop_services() {
    echo -e "${YELLOW}Deteniendo servicios PACS...${NC}"
    echo ""
    
    # Detener en orden inverso al inicio
    echo "Deteniendo Nginx..."
    docker-compose stop nginx 2>/dev/null || true
    
    echo "Deteniendo visualizadores..."
    docker-compose stop ohif oviyam 2>/dev/null || true
    
    echo "Deteniendo DCM4CHEE..."
    docker-compose stop dcm4chee-arc 2>/dev/null || true
    
    echo "Deteniendo servicios base..."
    docker-compose stop ldap-admin ldap postgres 2>/dev/null || true
    
    echo ""
    echo -e "${GREEN}✓ Todos los servicios detenidos${NC}"
}

# Función para remover contenedores
remove_containers() {
    echo -e "${YELLOW}Removiendo contenedores...${NC}"
    docker-compose down
    echo -e "${GREEN}✓ Contenedores removidos${NC}"
}

# Función para remover volúmenes si se solicita
remove_volumes() {
    if [ "$REMOVE_VOLUMES" = true ]; then
        echo ""
        echo -e "${RED}======================================${NC}"
        echo -e "${RED}         ¡ADVERTENCIA!${NC}"
        echo -e "${RED}======================================${NC}"
        echo -e "${RED}Está a punto de eliminar TODOS los datos${NC}"
        echo -e "${RED}incluyendo:${NC}"
        echo -e "${RED} - Base de datos PostgreSQL${NC}"
        echo -e "${RED} - Archivos DICOM almacenados${NC}"
        echo -e "${RED} - Configuraciones LDAP${NC}"
        echo -e "${RED} - Todos los estudios médicos${NC}"
        echo ""
        
        read -p "¿Está ABSOLUTAMENTE seguro? Escriba 'SI ELIMINAR TODO' para confirmar: " confirm
        
        if [ "$confirm" = "SI ELIMINAR TODO" ]; then
            echo -e "${YELLOW}Eliminando volúmenes...${NC}"
            docker-compose down -v
            
            # También eliminar directorios de datos si existen
            if [ -d "data" ]; then
                echo -e "${YELLOW}Eliminando directorios de datos...${NC}"
                rm -rf data/
            fi
            
            if [ -d "volumes" ]; then
                echo -e "${YELLOW}Eliminando directorios de volúmenes...${NC}"
                rm -rf volumes/
            fi
            
            echo -e "${GREEN}✓ Volúmenes y datos eliminados${NC}"
        else
            echo -e "${YELLOW}Operación cancelada${NC}"
        fi
    fi
}

# Función para mostrar estado final
show_final_status() {
    echo ""
    echo -e "${BLUE}======================================"
    echo "    PACS System detenido"
    echo "======================================${NC}"
    echo ""
    
    # Verificar que no hay contenedores corriendo
    local running=$(docker-compose ps -q 2>/dev/null | wc -l)
    
    if [ "$running" -eq 0 ]; then
        echo -e "${GREEN}✓ Sistema completamente detenido${NC}"
        
        if [ "$REMOVE_VOLUMES" = false ]; then
            echo -e "${BLUE}Los datos se han preservado${NC}"
            echo -e "Para reiniciar use: ${GREEN}./scripts/start.sh${NC}"
        else
            echo -e "${YELLOW}Todos los datos han sido eliminados${NC}"
            echo -e "Para reinstalar use: ${GREEN}./scripts/start.sh${NC}"
        fi
    else
        echo -e "${RED}⚠ Algunos contenedores podrían seguir corriendo${NC}"
        docker-compose ps
    fi
    
    echo ""
}

# Main
main() {
    check_running_containers
    perform_backup
    stop_services
    remove_containers
    remove_volumes
    show_final_status
}

# Manejo de interrupciones
trap 'echo -e "\n${RED}Interrupción detectada${NC}"; exit 1' INT TERM

# Ejecutar
main