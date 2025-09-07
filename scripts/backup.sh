#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

BACKUP_DIR="backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="pacs_backup_${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"
COMPRESS=true
KEEP_DAYS=30

echo -e "${BLUE}======================================"
echo "     PACS System - Backup"
echo "======================================${NC}"
echo ""
echo "Timestamp: ${TIMESTAMP}"
echo ""

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-compress)
            COMPRESS=false
            shift
            ;;
        --keep-days)
            KEEP_DAYS="$2"
            shift
            shift
            ;;
        --output|-o)
            BACKUP_PATH="$2"
            shift
            shift
            ;;
        --help|-h)
            echo "Uso: $0 [opciones]"
            echo ""
            echo "Opciones:"
            echo "  --no-compress         No comprimir el backup"
            echo "  --keep-days N        Mantener backups por N días (default: 30)"
            echo "  -o, --output PATH    Ruta de salida del backup"
            echo "  -h, --help          Mostrar esta ayuda"
            echo ""
            exit 0
            ;;
        *)
            echo -e "${RED}Opción desconocida: $1${NC}"
            exit 1
            ;;
    esac
done

check_prerequisites() {
    echo -e "${YELLOW}Verificando prerequisitos...${NC}"
    
    if ! docker ps | grep -q pacs-postgres; then
        echo -e "${RED}Error: PostgreSQL no está corriendo${NC}"
        exit 1
    fi
    
    mkdir -p "${BACKUP_DIR}"
    mkdir -p "${BACKUP_PATH}"
    
    echo -e "${GREEN}✓ Prerequisitos verificados${NC}"
}

calculate_sizes() {
    echo ""
    echo -e "${CYAN}=== Calculando tamaño de datos ===${NC}"
    
    db_size=$(docker exec pacs-postgres psql -U pacs -d pacsdb -t -c "SELECT pg_size_pretty(pg_database_size('pacsdb'));" 2>/dev/null || echo "N/A")
    echo "Base de datos PostgreSQL: $db_size"
    
    if [ -d "data/dicom-storage" ]; then
        dicom_size=$(du -sh data/dicom-storage 2>/dev/null | awk '{print $1}' || echo "N/A")
        echo "Archivos DICOM: $dicom_size"
    fi
    
    total_size=$(du -sh data/ 2>/dev/null | awk '{print $1}' || echo "N/A")
    echo "Tamaño total estimado: $total_size"
    echo ""
}

backup_postgres() {
    echo -e "${YELLOW}[1/5] Respaldando base de datos PostgreSQL...${NC}"
    
    docker exec pacs-postgres pg_dump \
        -U pacs \
        -d pacsdb \
        --verbose \
        --no-owner \
        --no-acl \
        --format=custom \
        --file=/tmp/pacsdb_backup.dump \
        2>/dev/null
    
    docker cp pacs-postgres:/tmp/pacsdb_backup.dump "${BACKUP_PATH}/postgres_backup.dump"
    
    docker exec pacs-postgres rm /tmp/pacsdb_backup.dump
    
    docker exec pacs-postgres pg_dump \
        -U pacs \
        -d pacsdb \
        --schema-only \
        --no-owner \
        --no-acl \
        > "${BACKUP_PATH}/postgres_schema.sql" \
        2>/dev/null
    
    echo -e "${GREEN}✓ Base de datos respaldada${NC}"
}

backup_dicom_files() {
    echo -e "${YELLOW}[2/5] Respaldando archivos DICOM...${NC}"
    
    if [ -d "data/dicom-storage" ]; then
        file_count=$(find data/dicom-storage -type f 2>/dev/null | wc -l)
        
        if [ "$file_count" -gt 0 ]; then
            echo "Copiando $file_count archivos DICOM..."
            
            if command -v rsync &> /dev/null; then
                rsync -av --progress data/dicom-storage/ "${BACKUP_PATH}/dicom-storage/"
            else
                cp -r data/dicom-storage "${BACKUP_PATH}/"
            fi
            
            echo -e "${GREEN}✓ Archivos DICOM respaldados ($file_count archivos)${NC}"
        else
            echo -e "${YELLOW}No hay archivos DICOM para respaldar${NC}"
        fi
    else
        echo -e "${YELLOW}Directorio DICOM no encontrado${NC}"
    fi
}

backup_ldap() {
    echo -e "${YELLOW}[3/5] Respaldando configuración LDAP...${NC}"
    
    if docker ps | grep -q pacs-ldap; then
        docker exec pacs-ldap slapcat -n 1 > "${BACKUP_PATH}/ldap_backup.ldif" 2>/dev/null || true
        docker exec pacs-ldap slapcat -n 0 > "${BACKUP_PATH}/ldap_config.ldif" 2>/dev/null || true
        
        echo -e "${GREEN}✓ LDAP respaldado${NC}"
    else
        echo -e "${YELLOW}LDAP no está corriendo, saltando...${NC}"
    fi
}

backup_configs() {
    echo -e "${YELLOW}[4/5] Respaldando configuraciones...${NC}"
    
    mkdir -p "${BACKUP_PATH}/configs"
    
    cp .env "${BACKUP_PATH}/configs/.env" 2>/dev/null || true
    cp docker-compose.yml "${BACKUP_PATH}/configs/docker-compose.yml" 2>/dev/null || true
    
    if [ -d "config" ]; then
        cp -r config "${BACKUP_PATH}/configs/"
    fi
    
    cat > "${BACKUP_PATH}/backup_info.txt" << EOF
PACS System Backup Information
==============================
Timestamp: ${TIMESTAMP}
Hostname: $(hostname)
User: $(whoami)
Docker Version: $(docker --version)
Docker Compose Version: $(docker-compose --version)

Containers Status:
$(docker-compose ps)

System Info:
$(uname -a)

Backup Contents:
- PostgreSQL database dump
- DICOM files
- LDAP configuration
- System configurations
EOF
    
    echo -e "${GREEN}✓ Configuraciones respaldadas${NC}"
}

compress_backup() {
    if [ "$COMPRESS" = true ]; then
        echo -e "${YELLOW}[5/5] Comprimiendo backup...${NC}"
        
        cd "${BACKUP_DIR}"
        
        size_before=$(du -sh "${BACKUP_NAME}" | awk '{print $1}')
        
        tar -czf "${BACKUP_NAME}.tar.gz" "${BACKUP_NAME}/"
        
        size_after=$(du -sh "${BACKUP_NAME}.tar.gz" | awk '{print $1}')
        
        rm -rf "${BACKUP_NAME}"
        
        echo -e "${GREEN}✓ Backup comprimido (${size_before} → ${size_after})${NC}"
        
        FINAL_BACKUP="${BACKUP_NAME}.tar.gz"
        cd - > /dev/null
    else
        echo -e "${YELLOW}[5/5] Saltando compresión...${NC}"
        FINAL_BACKUP="${BACKUP_NAME}"
    fi
}

cleanup_old_backups() {
    echo ""
    echo -e "${CYAN}=== Limpieza de backups antiguos ===${NC}"
    
    old_count=$(find "${BACKUP_DIR}" -name "pacs_backup_*.tar.gz" -type f -mtime +${KEEP_DAYS} 2>/dev/null | wc -l)
    
    if [ "$old_count" -gt 0 ]; then
        echo "Encontrados $old_count backups antiguos (más de ${KEEP_DAYS} días)"
        find "${BACKUP_DIR}" -name "pacs_backup_*.tar.gz" -type f -mtime +${KEEP_DAYS} -exec rm {} \;
        echo -e "${GREEN}✓ Backups antiguos eliminados${NC}"
    else
        echo "No hay backups antiguos para eliminar"
    fi
}

verify_backup() {
    echo ""
    echo -e "${CYAN}=== Verificando integridad del backup ===${NC}"
    
    if [ "$COMPRESS" = true ]; then
        if [ -f "${BACKUP_DIR}/${FINAL_BACKUP}" ]; then
            tar -tzf "${BACKUP_DIR}/${FINAL_BACKUP}" > /dev/null 2>&1
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ Archivo de backup íntegro${NC}"
                
                file_count=$(tar -tzf "${BACKUP_DIR}/${FINAL_BACKUP}" | wc -l)
                file_size=$(du -h "${BACKUP_DIR}/${FINAL_BACKUP}" | awk '{print $1}')
                
                echo "  Archivos en backup: $file_count"
                echo "  Tamaño del backup: $file_size"
            else
                echo -e "${RED}✗ Error al verificar el backup${NC}"
                exit 1
            fi
        fi
    else
        if [ -d "${BACKUP_PATH}" ]; then
            file_count=$(find "${BACKUP_PATH}" -type f | wc -l)
            dir_size=$(du -sh "${BACKUP_PATH}" | awk '{print $1}')
            
            echo -e "${GREEN}✓ Directorio de backup creado${NC}"
            echo "  Archivos en backup: $file_count"
            echo "  Tamaño del backup: $dir_size"
        fi
    fi
}

show_summary() {
    echo ""
    echo -e "${BLUE}======================================"
    echo "     Backup Completado"
    echo "======================================${NC}"
    echo ""
    
    if [ "$COMPRESS" = true ]; then
        echo -e "Archivo de backup: ${GREEN}${BACKUP_DIR}/${FINAL_BACKUP}${NC}"
    else
        echo -e "Directorio de backup: ${GREEN}${BACKUP_PATH}${NC}"
    fi
    
    echo ""
    echo "Contenido del backup:"
    echo "  ✓ Base de datos PostgreSQL"
    echo "  ✓ Archivos DICOM"
    echo "  ✓ Configuración LDAP"
    echo "  ✓ Archivos de configuración"
    echo ""
    
    echo -e "${CYAN}Para restaurar este backup use:${NC}"
    echo -e "${GREEN}./scripts/restore.sh ${BACKUP_DIR}/${FINAL_BACKUP}${NC}"
    echo ""
    
    backup_list=$(ls -lh "${BACKUP_DIR}"/pacs_backup_*.tar.gz 2>/dev/null | wc -l)
    echo "Total de backups disponibles: $backup_list"
    
    echo ""
    echo -e "${GREEN}Backup completado exitosamente${NC}"
}

main() {
    check_prerequisites
    calculate_sizes
    backup_postgres
    backup_dicom_files
    backup_ldap
    backup_configs
    compress_backup
    cleanup_old_backups
    verify_backup
    show_summary
}

trap 'echo -e "\n${RED}Backup interrumpido${NC}"; exit 1' INT TERM

main