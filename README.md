# Sistema PACS - Picture Archiving and Communication System

Sistema completo de archivo y comunicación de imágenes médicas basado en Docker.

## 🏥 Componentes

- **DCM4CHEE Arc Light 5.31.2** - Servidor PACS principal
- **PostgreSQL 15.5** - Base de datos
- **OHIF Viewer 3.8.0** - Visualizador DICOM moderno
- **Oviyam 2.8.2** - Visualizador DICOM alternativo
- **OpenLDAP 2.6.6** - Gestión de usuarios
- **Nginx 1.25.3** - Proxy reverso

## 📋 Requisitos

### Hardware Mínimo
- CPU: 4 cores
- RAM: 8 GB
- Storage: 500 GB SSD
- SO: Debian 11+ / Ubuntu 20.04+

### Software
- Docker 20.10+
- Docker Compose 1.29+
- Git

## 🚀 Instalación Rápida

### 1. Clonar repositorio
```bash
git clone <repository-url>
cd pacs-system
```

### 2. Configurar variables de entorno
```bash
cp .env.example .env
nano .env
```

### 3. Iniciar sistema
```bash
chmod +x scripts/*.sh
./scripts/start.sh
```

## 📝 Comandos Principales

### Gestión del Sistema

```bash
# Iniciar sistema completo
./scripts/start.sh

# Detener sistema
./scripts/stop.sh

# Verificar estado
./scripts/health-check.sh

# Ver logs
docker-compose logs -f [servicio]
```

### Backup y Restore

```bash
# Crear backup
./scripts/backup.sh

# Restaurar backup
./scripts/restore.sh backups/pacs_backup_TIMESTAMP.tar.gz

# Backup con opciones
./scripts/backup.sh --no-compress --keep-days 60
```

## 🌐 URLs de Acceso

| Servicio | URL | Credenciales por defecto |
|----------|-----|-------------------------|
| DCM4CHEE Admin | http://localhost:8080/dcm4chee-arc/ui2 | admin / admin |
| OHIF Viewer | http://localhost:3000 | - |
| Oviyam Viewer | http://localhost:8081/oviyam | - |
| LDAP Admin | http://localhost:6080 | cn=admin,dc=pacs,dc=local / [.env password] |
| Nginx Proxy | http://localhost | - |

## 🔧 Configuración DICOM

### Configuración de Modalidad

Para conectar equipos de imagenología:

- **AE Title**: DCM4CHEE
- **Host**: [IP del servidor]
- **Puerto**: 11112
- **Protocolo**: DICOM

### Ejemplo con dcmtk

```bash
# Verificar conectividad
echoscu -aec DCM4CHEE localhost 11112

# Enviar estudio
storescu -aec DCM4CHEE localhost 11112 *.dcm
```

## 📊 Monitoreo

### Ver estado de contenedores
```bash
docker-compose ps
```

### Ver uso de recursos
```bash
docker stats
```

### Ver logs en tiempo real
```bash
# Todos los servicios
docker-compose logs -f

# Servicio específico
docker-compose logs -f dcm4chee-arc
```

## 🔐 Seguridad

### Cambiar contraseñas por defecto

Editar archivo `.env`:
```bash
POSTGRES_PASSWORD=NuevaContraseñaSegura
LDAP_ADMIN_PASSWORD=NuevaContraseñaLDAP
WILDFLY_ADMIN_PASSWORD=NuevaContraseñaAdmin
```

### Configurar firewall

```bash
# Permitir solo puertos necesarios
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 11112/tcp
```

## 🛠️ Solución de Problemas

### DCM4CHEE no inicia