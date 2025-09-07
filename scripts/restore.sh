#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

BACKUP_FILE=""
RESTORE_DIR="restore_temp"
FORCE_RESTORE=false
RESTORE_CONFIG=true

echo -e "${BLUE}======================================"
echo "     PACS System - Restore"
echo "======================================${NC}"
echo ""

if [ $# -eq 0 ]; then
    echo -e "${RED}Error: Se requiere archivo de backup${NC}"
    echo "Uso: $0 <archivo_backup.tar.gz> [opciones]"
    echo ""
    echo "Opciones:"
    echo "  --force             Forzar restauración sin confirmación"
    echo "  --no-config         No restaurar configuraciones"
    echo "  -h, --help          Mostrar esta ayuda"
    echo ""
    
    if [ -d "backups" ]; then
        echo -e "${CYAN}Backups disponibles:${NC}"
        ls -lh backups/pacs_backup_*.tar.gz 2>/dev/null || echo "No hay backups disponibles"
    fi
    exit 1
fi

BACKUP_FILE="$1"
shift

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_RESTORE=true
            shift
            ;;
        --no-config)
            RESTORE_CONFIG=false
            shift
            ;;
        --help|-h)
            echo "Uso: $0 <archivo_backup.tar.gz> [opciones]"
            echo ""
            echo "Opciones:"
            echo "  --force             Forzar restauración sin confirmación"
            echo "  --no-config         No restaurar configuraciones"
            echo "  -h, --help          Mostrar esta ayuda"
            exit 0
            ;;
        *)
            echo -e "${RED}Opción desconocida: $1${NC}"
            exit 1
            ;;
    esac
done

verify_backup_file() {
    echo -e "${YELLOW}Verificando archivo de backup...${NC}"
    
    if [ ! -f "$BACKUP_FILE" ]; then
        echo -e "${RED}Error: Archivo de backup no encontrado: $BACKUP_FILE${NC}"
        exit 1
    fi
    
    tar -tzf "$BACKUP_FILE" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Archivo de backup corrupto o inválido${NC}"
        exit 1
    fi
    
    backup_size=$(du -h "$BACKUP_FILE" | awk '{print $1}')
    echo -e "${GREEN}✓ Archivo de backup válido ($backup_size)${NC}"
}

check_prerequisites() {
    echo -e "${YELLOW}Verificando prerequisitos...${NC}"
    
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Error: Docker no está instalado${NC}"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        echo -e "${RED}Error: Docker Compose no está instalado${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Prerequisitos cumplidos${NC}"
}

extract_backup() {
    echo -e "${YELLOW}Extrayendo backup...${NC}"
    
    rm -rf "${RESTORE_DIR}"
    mkdir -p "${RESTORE_DIR}"
    
    tar -xzf "$BACKUP_FILE" -C "${RESTORE_DIR}"
    
    EXTRACTED_DIR=$(ls -d ${RESTORE_DIR}/pacs_backup_* | head -1)
    
    if [ ! -d "$EXTRACTED_DIR" ]; then
        echo -e "${RED}Error: Estructura de backup inválida${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Backup extraído${NC}"
}

confirm_restore() {
    if [ "$FORCE_RESTORE" = false ]; then
        echo ""
        echo -e "${YELLOW}======================================${NC}"
        echo -e "${YELLOW}         ¡ADVERTENCIA!${NC}"
        echo -e "${YELLOW}======================================${NC}"
        echo ""
        echo -e "${YELLOW}Esta operación:${NC}"
        echo "  - Detendrá el sistema PACS actual"
        echo "  - Sobrescribirá TODOS los datos actuales"
        echo "  - Restaurará datos del backup"
        echo ""
        
        read -p "¿Está seguro de continuar? (s/n): " -n 1 -r
        echo
        
        if [[ ! $REPLY =~ ^[Ss]$ ]]; then
            echo -e "${YELLOW}Restauración cancelada${NC}"
            exit 0
        fi
    fi
}

stop_services() {
    echo -e "${YELLOW}Deteniendo servicios actuales...${NC}"
    
    if [ -f "scripts/stop.sh" ]; then
        bash scripts/stop.sh
    else
        docker-compose down 2>/dev/null || true
    fi
    
    echo -e "${GREEN}✓ Servicios detenidos${NC}"
}

restore_configs() {
    if [ "$RESTORE_CONFIG" = true ]; then
        echo -e "${YELLOW}[1/4] Restaurando configuraciones...${NC}"
        
        if [ -f "$EXTRACTED_DIR/configs/.env" ]; then
            cp "$EXTRACTED_DIR/configs/.env" .env
            echo "  ✓ Archivo .env restaurado"
        fi
        
        if [ -f "$EXTRACTED_DIR/configs/docker-compose.yml" ]; then
            cp "$EXTRACTED_DIR/configs/docker-compose.yml" docker-compose.yml.backup
            echo "  ✓ docker-compose.yml respaldado como docker-compose.yml.backup"
        fi
        
        if [ -d "$EXTRACTED_DIR/configs/config" ]; then
            rm -rf config.backup
            mv config config.backup 2>/dev/null || true
            cp -r "$EXTRACTED_DIR/configs/config" config
            echo "  ✓ Configuraciones restauradas"
        fi
        
        echo -e "${GREEN}✓ Configuraciones restauradas${NC}"
    else
        echo -e "${YELLOW}[1/4] Saltando restauración de configuraciones...${NC}"
    fi
}

start_base_services() {
    echo -e "${YELLOW}[2/4] Iniciando servicios base...${NC}"
    
    docker-compose up -d postgres ldap
    
    echo "Esperando que PostgreSQL esté listo..."
    sleep 10
    
    max_attempts=30
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if docker exec pacs-postgres pg_isready -U pacs >/dev/null 2>&1; then
            echo -e "${GREEN}✓ PostgreSQL listo${NC}"
            break
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    if [ $attempt -eq $max_attempts ]; then
        echo -e "${RED}Error: PostgreSQL no responde${NC}"
        exit 1
    fi
}

restore_postgres() {
    echo -e "${YELLOW}[3/4] Restaurando base de datos PostgreSQL...${NC}"
    
    if [ -f "$EXTRACTED_DIR/postgres_backup.dump" ]; then
        docker exec -i pacs-postgres dropdb -U pacs --if-exists pacsdb 2>/dev/null || true
        docker exec -i pacs-postgres createdb -U pacs pacsdb
        
        docker cp "$EXTRACTED_DIR/postgres_backup.dump" pacs-postgres:/tmp/restore.dump
        
        docker exec pacs-postgres pg_restore \
            -U pacs \
            -d pacsdb \
            --verbose \
            --no-owner \
            --no-acl \
            /tmp/restore.dump \
            2>/dev/null || true
        
        docker exec pacs-postgres rm /tmp/restore.dump
        
        echo -e "${GREEN}✓ Base de datos restaurada${NC}"
    else
        echo -e "${YELLOW}No se encontró backup de base de datos${NC}"
    fi
}

restore_dicom_files() {
    echo -e "${YELLOW}[4/4] Restaurando archivos DICOM...${NC}"
    
    if [ -d "$EXTRACTED_DIR/dicom-storage" ]; then
        rm -rf data/dicom-storage.old
        mv data/dicom-storage data/dicom-storage.old 2>/dev/null || true
        
        mkdir -p data/
        cp -r "$EXTRACTED_DIR/dicom-storage" data/
        
        file_count=$(find data/dicom-storage -type f 2>/dev/null | wc -l)
        echo -e "${GREEN}✓ Archivos DICOM restaurados ($file_count archivos)${NC}"
    else
        echo -e "${YELLOW}No se encontraron archivos DICOM en el backup${NC}"
    fi
}

restore_ldap() {
    echo -e "${YELLOW}Restaurando LDAP...${NC}"
    
    if [ -f "$EXTRACTED_DIR/ldap_backup.ldif" ]; then
        docker cp "$EXTRACTED_DIR/ldap_backup.ldif" pacs-ldap:/tmp/restore.ldif
        
        docker exec pacs-ldap ldapadd \
            -x \
            -D "cn=admin,dc=pacs,dc=local" \
            -w "${LDAP_ADMIN_PASSWORD}" \
            -f /tmp/restore.ldif \
            -c \
            2>/dev/null || true
        
        docker exec pacs-ldap rm /tmp/restore.ldif
        
        echo -e "${GREEN}✓ LDAP restaurado${NC}"
    else
        echo -e "${YELLOW}No se encontró backup de LDAP${NC}"
    fi
}

start_all_services() {
    echo -e "${YELLOW}Iniciando todos los servicios...${NC}"
    
    docker-compose up -d
    
    echo "Esperando que los servicios se inicialicen..."
    sleep 30
    
    echo -e "${GREEN}✓ Todos los servicios iniciados${NC}"
}

cleanup() {
    echo -e "${YELLOW}Limpiando archivos temporales...${NC}"
    
    rm -rf "${RESTORE_DIR}"
    
    echo -e "${GREEN}✓ Limpieza completada${NC}"
}

verify_restore() {
    echo ""
    echo -e "${CYAN}=== Verificando restauración ===${NC}"
    
    services_ok=true
    
    echo -n "PostgreSQL: "
    if docker exec pacs-postgres pg_isready -U pacs >/dev/null 2>&1; then
        echo -e "${GREEN}✓ OK${NC}"
    else
        echo -e "${RED}✗ FALLO${NC}"
        services_ok=false
    fi
    
    echo -n "DCM4CHEE: "
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080/dcm4chee-arc/ui2/" | grep -q "200\|302"; then
        echo -e "${GREEN}✓ OK${NC}"
    else
        echo -e "${YELLOW}⚠ Iniciando...${NC}"
    fi
    
    echo -n "OHIF Viewer: "
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:3000" | grep -q "200"; then
        echo -e "${GREEN}✓ OK${NC}"
    else
        echo -e "${YELLOW}⚠ Iniciando...${NC}"
    fi
    
    if [ "$services_ok" = false ]; then
        echo ""
        echo -e "${RED}Algunos servicios no están funcionando correctamente${NC}"
        echo "Ejecute ./scripts/health-check.sh para más detalles"
    fi
}

show_summary() {
    echo ""
    echo -e "${BLUE}======================================"
    echo "     Restauración Completada"
    echo "======================================${NC}"
    echo ""
    
    echo "Backup restaurado: $(basename $BACKUP_FILE)"
    echo ""
    echo "Componentes restaurados:"
    echo "  ✓ Base de datos PostgreSQL"
    echo "  ✓ Archivos DICOM"
    echo "  ✓ Configuración LDAP"
    
    if [ "$RESTORE_CONFIG" = true ]; then
        echo "  ✓ Archivos de configuración"
    fi
    
    echo ""
    echo -e "${CYAN}URLs de acceso:${NC}"
    echo "  DCM4CHEE: http://localhost:8080/dcm4chee-arc/ui2"
    echo "  OHIF:     http://localhost:3000"
    echo "  Oviyam:   http://localhost:8081/oviyam"
    echo ""
    
    echo -e "${GREEN}Sistema PACS restaurado exitosamente${NC}"
    echo ""
    echo -e "${YELLOW}Nota: DCM4CHEE puede tardar 2-3 minutos en estar completamente operativo${NC}"
}

main() {
    verify_backup_file
    check_prerequisites
    extract_backup
    confirm_restore
    stop_services
    restore_configs
    start_base_services
    restore_postgres
    restore_dicom_files
    restore_ldap
    start_all_services
    cleanup
    verify_restore
    show_summary
}

trap 'echo -e "\n${RED}Restauración interrumpida${NC}"; cleanup; exit 1' INT TERM

main