#!/bin/bash

# PACS System Health Check Script
# Verificación completa del estado del sistema

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Variables
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}     PACS System Health Check${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""
echo -e "Fecha: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Función para verificar servicio
check_service() {
    local service=$1
    local port=$2
    local name=$3
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    echo -n "[$TOTAL_CHECKS] Verificando $name... "
    
    # Verificar si el contenedor está corriendo
    if docker ps --format "{{.Names}}" | grep -q "^pacs-$service$"; then
        # Verificar puerto si se proporciona
        if [ ! -z "$port" ]; then
            if nc -z localhost $port 2>/dev/null; then
                echo -e "${GREEN}✓ OK${NC} (Container activo, Puerto $port accesible)"
                PASSED_CHECKS=$((PASSED_CHECKS + 1))
                return 0
            else
                echo -e "${YELLOW}⚠ ADVERTENCIA${NC} (Container activo, Puerto $port no accesible)"
                WARNINGS=$((WARNINGS + 1))
                return 1
            fi
        else
            echo -e "${GREEN}✓ OK${NC} (Container activo)"
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
            return 0
        fi
    else
        echo -e "${RED}✗ FALLO${NC} (Container no está corriendo)"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

# Función para verificar conectividad de base de datos
check_database() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    echo -n "[$TOTAL_CHECKS] Verificando conectividad PostgreSQL... "
    
    if docker exec pacs-postgres pg_isready -U pacs >/dev/null 2>&1; then
        echo -e "${GREEN}✓ OK${NC} (Base de datos respondiendo)"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        
        # Verificar tablas DCM4CHEE
        TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
        echo -n "[$TOTAL_CHECKS] Verificando esquema DCM4CHEE... "
        
        table_count=$(docker exec pacs-postgres psql -U pacs -d pacsdb -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null || echo "0")
        
        if [ "$table_count" -gt "0" ]; then
            echo -e "${GREEN}✓ OK${NC} ($table_count tablas encontradas)"
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
        else
            echo -e "${YELLOW}⚠ ADVERTENCIA${NC} (Esquema vacío - primera ejecución?)"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        echo -e "${RED}✗ FALLO${NC} (No se puede conectar a la base de datos)"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
}

# Función para verificar APIs REST
check_api() {
    local url=$1
    local name=$2
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    echo -n "[$TOTAL_CHECKS] Verificando API $name... "
    
    response=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    
    if [ "$response" = "200" ] || [ "$response" = "301" ] || [ "$response" = "302" ]; then
        echo -e "${GREEN}✓ OK${NC} (HTTP $response)"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    elif [ "$response" = "401" ] || [ "$response" = "403" ]; then
        echo -e "${GREEN}✓ OK${NC} (HTTP $response - Autenticación requerida)"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    elif [ "$response" = "000" ]; then
        echo -e "${RED}✗ FALLO${NC} (No responde)"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    else
        echo -e "${YELLOW}⚠ ADVERTENCIA${NC} (HTTP $response)"
        WARNINGS=$((WARNINGS + 1))
        return 1
    fi
}

# Función para verificar espacio en disco
check_disk_space() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    echo -n "[$TOTAL_CHECKS] Verificando espacio en disco... "
    
    available=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
    used_percent=$(df . | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [ "$used_percent" -lt 80 ]; then
        echo -e "${GREEN}✓ OK${NC} (${available}GB disponibles, ${used_percent}% usado)"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    elif [ "$used_percent" -lt 90 ]; then
        echo -e "${YELLOW}⚠ ADVERTENCIA${NC} (${available}GB disponibles, ${used_percent}% usado)"
        WARNINGS=$((WARNINGS + 1))
    else
        echo -e "${RED}✗ CRÍTICO${NC} (${available}GB disponibles, ${used_percent}% usado)"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
}

# Función para verificar memoria
check_memory() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    echo -n "[$TOTAL_CHECKS] Verificando uso de memoria... "
    
    if command -v free >/dev/null 2>&1; then
        mem_total=$(free -m | awk 'NR==2{print $2}')
        mem_used=$(free -m | awk 'NR==2{print $3}')
        mem_percent=$((mem_used * 100 / mem_total))
        
        if [ "$mem_percent" -lt 80 ]; then
            echo -e "${GREEN}✓ OK${NC} (${mem_percent}% usado, ${mem_used}MB/${mem_total}MB)"
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
        elif [ "$mem_percent" -lt 90 ]; then
            echo -e "${YELLOW}⚠ ADVERTENCIA${NC} (${mem_percent}% usado, ${mem_used}MB/${mem_total}MB)"
            WARNINGS=$((WARNINGS + 1))
        else
            echo -e "${RED}✗ CRÍTICO${NC} (${mem_percent}% usado, ${mem_used}MB/${mem_total}MB)"
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
        fi
    else
        echo -e "${YELLOW}⚠ No se puede verificar${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi
}

# ============================================
# EJECUTAR VERIFICACIONES
# ============================================

echo -e "${CYAN}=== Verificación de Servicios ===${NC}"
echo ""

# Verificar servicios principales
check_service "postgres" "5432" "PostgreSQL"
check_service "ldap" "389" "OpenLDAP"
check_service "dcm4chee" "8080" "DCM4CHEE Arc"
check_service "dcm4chee" "11112" "Servicio DICOM"
check_service "ohif" "3000" "OHIF Viewer"
check_service "oviyam" "8081" "Oviyam Viewer"
check_service "nginx" "80" "Nginx Proxy"
check_service "ldap-admin" "" "LDAP Admin (Opcional)"

echo ""
echo -e "${CYAN}=== Verificación de Base de Datos ===${NC}"
echo ""

check_database

echo ""
echo -e "${CYAN}=== Verificación de APIs y Endpoints ===${NC}"
echo ""

check_api "http://localhost:8080/dcm4chee-arc/ui2/" "DCM4CHEE UI"
check_api "http://localhost:8080/dcm4chee-arc/aets/DCM4CHEE/rs/studies?limit=1" "QIDO-RS API"
check_api "http://localhost:3000" "OHIF Viewer"
check_api "http://localhost:8081/oviyam" "Oviyam"
check_api "http://localhost/health" "Nginx Health"

echo ""
echo -e "${CYAN}=== Verificación de Recursos del Sistema ===${NC}"
echo ""

check_disk_space
check_memory

echo ""
echo -e "${CYAN}=== Estado de Contenedores Docker ===${NC}"
echo ""

docker-compose ps --format "table {{.Name}}\t{{.Status}}\t{{.State}}"

echo ""
echo -e "${CYAN}=== Uso de Recursos por Contenedor ===${NC}"
echo ""

docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"

echo ""
echo -e "${CYAN}=== Logs Recientes de Errores ===${NC}"
echo ""

# Buscar errores en los logs de los últimos 5 minutos
echo "Verificando logs de errores..."
for container in postgres ldap dcm4chee ohif oviyam nginx; do
    errors=$(docker logs pacs-$container 2>&1 | tail -100 | grep -i "error\|fail\|critical" | wc -l)
    if [ "$errors" -gt 0 ]; then
        echo -e "${YELLOW}⚠ pacs-$container: $errors errores en logs recientes${NC}"
    fi
done

echo ""
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}         RESUMEN DE SALUD${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# Calcular estado general
if [ "$FAILED_CHECKS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    STATUS="${GREEN}EXCELENTE${NC}"
    STATUS_MSG="Sistema funcionando perfectamente"
elif [ "$FAILED_CHECKS" -eq 0 ] && [ "$WARNINGS" -gt 0 ]; then
    STATUS="${YELLOW}BUENO${NC}"
    STATUS_MSG="Sistema operativo con advertencias menores"
elif [ "$FAILED_CHECKS" -gt 0 ] && [ "$FAILED_CHECKS" -le 2 ]; then
    STATUS="${YELLOW}DEGRADADO${NC}"
    STATUS_MSG="Sistema parcialmente operativo"
else
    STATUS="${RED}CRÍTICO${NC}"
    STATUS_MSG="Sistema con problemas significativos"
fi

echo -e "Estado General: $STATUS"
echo -e "$STATUS_MSG"
echo ""
echo "Verificaciones totales: $TOTAL_CHECKS"
echo -e "  ${GREEN}✓ Exitosas:${NC} $PASSED_CHECKS"
echo -e "  ${YELLOW}⚠ Advertencias:${NC} $WARNINGS"
echo -e "  ${RED}✗ Fallos:${NC} $FAILED_CHECKS"
echo ""

# URLs de acceso
if [ "$FAILED_CHECKS" -lt 3 ]; then
    echo -e "${CYAN}=== URLs de Acceso ===${NC}"
    echo ""
    echo "DCM4CHEE Admin: http://localhost:8080/dcm4chee-arc/ui2"
    echo "OHIF Viewer:    http://localhost:3000"
    echo "Oviyam Viewer:  http://localhost:8081/oviyam"
    echo "LDAP Admin:     http://localhost:6080"
    echo "Nginx Proxy:    http://localhost"
    echo ""
fi

echo -e "${BLUE}======================================${NC}"
echo -e "Verificación completada: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${BLUE}======================================${NC}"

# Exit code basado en el estado
if [ "$FAILED_CHECKS" -eq 0 ]; then
    exit 0
else
    exit 1
fi