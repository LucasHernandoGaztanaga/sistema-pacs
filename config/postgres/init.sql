-- PACS Database Initialization Script
-- Optimización de PostgreSQL para datos DICOM

-- Configuraciones de rendimiento para PostgreSQL
ALTER SYSTEM SET shared_buffers = '256MB';
ALTER SYSTEM SET effective_cache_size = '1GB';
ALTER SYSTEM SET maintenance_work_mem = '64MB';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
ALTER SYSTEM SET wal_buffers = '16MB';
ALTER SYSTEM SET default_statistics_target = 100;
ALTER SYSTEM SET random_page_cost = 1.1;
ALTER SYSTEM SET effective_io_concurrency = 200;
ALTER SYSTEM SET work_mem = '4MB';
ALTER SYSTEM SET min_wal_size = '1GB';
ALTER SYSTEM SET max_wal_size = '4GB';

-- Configuraciones adicionales para DICOM
ALTER SYSTEM SET max_connections = 200;
ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';

-- Crear extensiones útiles si no existen
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Configuración de autovacuum para tablas grandes
ALTER SYSTEM SET autovacuum_vacuum_scale_factor = 0.1;
ALTER SYSTEM SET autovacuum_analyze_scale_factor = 0.05;

-- Log de consultas lentas (más de 1 segundo)
ALTER SYSTEM SET log_min_duration_statement = 1000;

-- Aplicar cambios
SELECT pg_reload_conf();

-- Mensaje de confirmación
DO $$
BEGIN
    RAISE NOTICE 'PostgreSQL optimizado para PACS/DICOM';
END $$;