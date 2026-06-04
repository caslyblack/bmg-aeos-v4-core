-- B.M.G. AEOS v4 Core - Database Initialization Script

-- Create schemas
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS audit;
CREATE SCHEMA IF NOT EXISTS api;

-- Set search path
ALTER DATABASE aeos SET search_path TO core, api, audit, public;

-- Core tables for service management
CREATE TABLE IF NOT EXISTS core.services (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT,
    version VARCHAR(50) NOT NULL,
    status VARCHAR(50) DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'maintenance')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(255),
    updated_by VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS core.service_instances (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    service_id UUID NOT NULL REFERENCES core.services(id) ON DELETE CASCADE,
    host VARCHAR(255) NOT NULL,
    port INTEGER NOT NULL CHECK (port > 0 AND port < 65536),
    status VARCHAR(50) DEFAULT 'up' CHECK (status IN ('up', 'down', 'unknown')),
    health_check_url VARCHAR(500),
    last_health_check TIMESTAMP WITH TIME ZONE,
    last_health_status BOOLEAN,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(service_id, host, port)
);

CREATE TABLE IF NOT EXISTS core.config (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    service_id UUID NOT NULL REFERENCES core.services(id) ON DELETE CASCADE,
    key VARCHAR(255) NOT NULL,
    value JSONB NOT NULL,
    value_type VARCHAR(50) DEFAULT 'json',
    version INTEGER DEFAULT 1,
    active BOOLEAN DEFAULT true,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(service_id, key, version)
);

-- API endpoints tracking
CREATE TABLE IF NOT EXISTS api.endpoints (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    service_id UUID NOT NULL REFERENCES core.services(id) ON DELETE CASCADE,
    method VARCHAR(10) NOT NULL CHECK (method IN ('GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS', 'HEAD')),
    path VARCHAR(500) NOT NULL,
    description TEXT,
    deprecated BOOLEAN DEFAULT false,
    deprecated_at TIMESTAMP WITH TIME ZONE,
    requires_auth BOOLEAN DEFAULT true,
    rate_limit INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(service_id, method, path)
);

-- Audit tables for compliance
CREATE TABLE IF NOT EXISTS audit.logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    service_id UUID REFERENCES core.services(id) ON DELETE SET NULL,
    action VARCHAR(255) NOT NULL,
    entity_type VARCHAR(100) NOT NULL,
    entity_id UUID,
    changes JSONB,
    user_id VARCHAR(255),
    ip_address INET,
    status VARCHAR(50) DEFAULT 'success' CHECK (status IN ('success', 'failure', 'pending')),
    error_message TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS audit.events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_type VARCHAR(100) NOT NULL,
    service_id UUID REFERENCES core.services(id) ON DELETE SET NULL,
    severity VARCHAR(50) DEFAULT 'info' CHECK (severity IN ('debug', 'info', 'warning', 'error', 'critical')),
    message TEXT NOT NULL,
    context JSONB DEFAULT '{}',
    resolved BOOLEAN DEFAULT false,
    resolved_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX idx_services_status ON core.services(status);
CREATE INDEX idx_services_name ON core.services(name);
CREATE INDEX idx_service_instances_service_id ON core.service_instances(service_id);
CREATE INDEX idx_service_instances_status ON core.service_instances(status);
CREATE INDEX idx_service_instances_host_port ON core.service_instances(host, port);
CREATE INDEX idx_config_service_id ON core.config(service_id);
CREATE INDEX idx_config_active ON core.config(active);
CREATE INDEX idx_config_key ON core.config(key);
CREATE INDEX idx_api_endpoints_service_id ON api.endpoints(service_id);
CREATE INDEX idx_api_endpoints_path ON api.endpoints(path);
CREATE INDEX idx_audit_logs_created_at ON audit.logs(created_at DESC);
CREATE INDEX idx_audit_logs_service_id ON audit.logs(service_id);
CREATE INDEX idx_audit_logs_entity_type ON audit.logs(entity_type);
CREATE INDEX idx_audit_logs_user_id ON audit.logs(user_id);
CREATE INDEX idx_audit_events_created_at ON audit.events(created_at DESC);
CREATE INDEX idx_audit_events_service_id ON audit.events(service_id);
CREATE INDEX idx_audit_events_severity ON audit.events(severity);

-- Create functions for automatic timestamp updates
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply update triggers
CREATE TRIGGER update_services_timestamp BEFORE UPDATE ON core.services
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_service_instances_timestamp BEFORE UPDATE ON core.service_instances
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_config_timestamp BEFORE UPDATE ON core.config
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_api_endpoints_timestamp BEFORE UPDATE ON api.endpoints
FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Create audit logging function
CREATE OR REPLACE FUNCTION audit.log_changes()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit.logs (service_id, action, entity_type, entity_id, changes, created_at)
    VALUES (
        COALESCE(NEW.service_id, OLD.service_id),
        TG_ARGV[0],
        TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        jsonb_build_object('before', row_to_json(OLD), 'after', row_to_json(NEW)),
        CURRENT_TIMESTAMP
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Grant permissions to application user
GRANT CONNECT ON DATABASE aeos TO aeos;
GRANT USAGE ON SCHEMA core, api, audit TO aeos;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA core, api, audit TO aeos;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA core, api, audit TO aeos;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA core, api, audit TO aeos;

-- Grant specific permissions
GRANT SELECT, INSERT, UPDATE ON core.services TO aeos;
GRANT SELECT, INSERT, UPDATE ON core.service_instances TO aeos;
GRANT SELECT, INSERT, UPDATE ON core.config TO aeos;
GRANT SELECT, INSERT, UPDATE ON api.endpoints TO aeos;
GRANT SELECT, INSERT ON audit.logs TO aeos;
GRANT SELECT, INSERT ON audit.events TO aeos;

-- Insert sample service
INSERT INTO core.services (name, description, version, status, created_by)
VALUES ('aeos-core', 'B.M.G. AEOS v4 Core Service', '4.0.0', 'active', 'system')
ON CONFLICT (name) DO NOTHING;

-- Add health check for core service
INSERT INTO core.service_instances (service_id, host, port, status, health_check_url, created_by)
SELECT id, 'localhost', 8080, 'up', 'http://localhost:8080/health', 'system'
FROM core.services WHERE name = 'aeos-core'
ON CONFLICT (service_id, host, port) DO NOTHING;

-- Create comment on tables for documentation
COMMENT ON TABLE core.services IS 'Central registry of all microservices in the AEOS ecosystem';
COMMENT ON TABLE core.service_instances IS 'Running instances of microservices with health status';
COMMENT ON TABLE core.config IS 'Dynamic configuration management for services';
COMMENT ON TABLE api.endpoints IS 'API endpoint registry and metadata';
COMMENT ON TABLE audit.logs IS 'Audit trail of all system changes';
COMMENT ON TABLE audit.events IS 'System events and alerts';
