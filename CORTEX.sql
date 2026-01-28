-- ====================================================================================
-- SYNAPTIA TECHNOLOGIES - CORTEX DATABASE SCHEMA (MODULAR MONOLITH)
-- Motor: PostgreSQL 14+
-- Architecture: 6 Bounded Contexts via PostgreSQL Schemas
-- ====================================================================================

-- 1. SCHEMA DEFINITIONS (Bounded Contexts)
CREATE SCHEMA core;        -- Identity, Auth, Locations
CREATE SCHEMA assets;      -- Asset Ontology & Telemetry
CREATE SCHEMA catalog;     -- Templates & Definitions
CREATE SCHEMA inventory;   -- Parts, Stock, Transactions
CREATE SCHEMA maintenance; -- Work Orders, PMs, Execution
CREATE SCHEMA analytics;   -- Audit, Reports, Intelligence

-- ====================================================================================
-- MÓDULO CORE: Identity & Context
-- ====================================================================================

-- Role definitions for RBAC
CREATE TABLE core.roles (
    role_id SERIAL PRIMARY KEY,
    role_name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT
);

-- Granular permissions
CREATE TABLE core.permissions (
    permission_id SERIAL PRIMARY KEY,
    permission_name VARCHAR(100) UNIQUE NOT NULL -- e.g., 'wo_create', 'asset_edit'
);

-- Junction table for M:M relationship between Roles and Permissions
CREATE TABLE core.role_permissions (
    role_id INT NOT NULL REFERENCES core.roles(role_id) ON DELETE CASCADE,
    permission_id INT NOT NULL REFERENCES core.permissions(permission_id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

-- Core Users and Personnel
CREATE TABLE core.users (
    user_id BIGSERIAL PRIMARY KEY,
    username VARCHAR(100) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    role_id INT NOT NULL REFERENCES core.roles(role_id),
    is_active BOOLEAN DEFAULT TRUE,
    last_login TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Hierarchical locations (Sites -> Buildings -> Zones)
CREATE TABLE core.locations (
    location_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    address TEXT,
    parent_location_id INT REFERENCES core.locations(location_id),
    latitude NUMERIC(10, 8),
    longitude NUMERIC(11, 8)
);

-- ====================================================================================
-- MÓDULO ASSETS: The Ontology Layer
-- ====================================================================================

-- Asset categories (e.g., HVAC, Vehicle, Manufacturing)
CREATE TABLE assets.types (
    asset_type_id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT
);

-- Core Asset registry
CREATE TABLE assets.registry (
    asset_id BIGSERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    tag_number VARCHAR(100) UNIQUE NOT NULL,
    serial_number VARCHAR(100),
    asset_type_id INT NOT NULL REFERENCES assets.types(asset_type_id),
    location_id INT NOT NULL REFERENCES core.locations(location_id),
    status VARCHAR(50) NOT NULL DEFAULT 'Operational', -- 'Operational', 'Down', 'Maintenance'
    criticality VARCHAR(50) DEFAULT 'Medium', -- 'High', 'Medium', 'Low'
    manufacturer VARCHAR(100),
    model VARCHAR(100),
    install_date DATE,
    purchase_cost NUMERIC(15, 2) DEFAULT 0,
    last_meter_reading NUMERIC(15, 2),
    custom_fields JSONB -- Flexible data for asset-specific attributes
);

-- IoT sensor readings and manual meter inputs
CREATE TABLE assets.readings (
    reading_id BIGSERIAL PRIMARY KEY,
    asset_id BIGINT NOT NULL REFERENCES assets.registry(asset_id) ON DELETE CASCADE,
    reading_type VARCHAR(100) NOT NULL, -- 'Runtime', 'Temperature', 'Vibration'
    value NUMERIC(15, 2) NOT NULL,
    unit VARCHAR(50),
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    source VARCHAR(50) DEFAULT 'Manual' -- 'Manual', 'IoT', 'System'
);

-- ====================================================================================
-- MÓDULO CATALOG: Templates & Definitions
-- ====================================================================================

-- Reusable maintenance instructions/steps
CREATE TABLE catalog.maintenance_tasks (
    task_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    estimated_duration_min NUMERIC(6, 2),
    standard_labor_hrs NUMERIC(6, 2)
);

-- Templates for inspections or preventive checks
CREATE TABLE catalog.checklists (
    checklist_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    asset_type_id INT REFERENCES assets.types(asset_type_id)
);

-- Items within a checklist template
CREATE TABLE catalog.checklist_items (
    item_id BIGSERIAL PRIMARY KEY,
    checklist_id INT NOT NULL REFERENCES catalog.checklists(checklist_id) ON DELETE CASCADE,
    description TEXT NOT NULL,
    item_type VARCHAR(50) NOT NULL, -- 'text', 'yes/no', 'number', 'photo'
    sequence_number INT NOT NULL
);

-- ====================================================================================
-- MÓDULO INVENTORY: Parts & Stock Management
-- ====================================================================================

-- Suppliers for parts and services
CREATE TABLE inventory.suppliers (
    supplier_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    contact_person VARCHAR(255),
    phone VARCHAR(50),
    email VARCHAR(255),
    address TEXT
);

-- Spare parts definitions
CREATE TABLE inventory.parts (
    part_id BIGSERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    sku VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    unit_cost NUMERIC(10, 4) DEFAULT 0,
    uom VARCHAR(50), -- Unit of Measure ('Each', 'Box', 'Meter')
    supplier_id INT REFERENCES inventory.suppliers(supplier_id)
);

-- Physical storage locations for inventory
CREATE TABLE inventory.storerooms (
    storeroom_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    location_id INT REFERENCES core.locations(location_id),
    is_active BOOLEAN DEFAULT TRUE
);

-- Stock levels for parts in specific storerooms
CREATE TABLE inventory.stock (
    stock_id BIGSERIAL PRIMARY KEY,
    part_id BIGINT NOT NULL REFERENCES inventory.parts(part_id) ON DELETE RESTRICT,
    storeroom_id INT NOT NULL REFERENCES inventory.storerooms(storeroom_id) ON DELETE RESTRICT,
    quantity_on_hand NUMERIC(10, 2) NOT NULL DEFAULT 0,
    reorder_point NUMERIC(10, 2) DEFAULT 5,
    max_stock_level NUMERIC(10, 2),
    average_unit_cost NUMERIC(10, 4),
    last_stock_update TIMESTAMP WITH TIME ZONE,
    UNIQUE (part_id, storeroom_id)
);

-- Log of all stock movements (Issue, Receive, Transfer)
CREATE TABLE inventory.transactions (
    transaction_id BIGSERIAL PRIMARY KEY,
    stock_id BIGINT NOT NULL REFERENCES inventory.stock(stock_id) ON DELETE RESTRICT,
    transaction_type VARCHAR(50) NOT NULL, -- 'Issue', 'Receive', 'Transfer', 'Adjustment'
    quantity_change NUMERIC(10, 2) NOT NULL, -- Signed value (+/-)
    unit_cost_at_time NUMERIC(10, 4),
    user_id BIGINT REFERENCES core.users(user_id),
    related_wo_id BIGINT, -- FK added after work_orders table
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- ====================================================================================
-- MÓDULO MAINTENANCE: Work Execution & Scheduling
-- ====================================================================================

-- Definitions for recurring maintenance schedules
CREATE TABLE maintenance.preventive_schedule (
    pm_id BIGSERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    asset_id BIGINT REFERENCES assets.registry(asset_id) ON DELETE CASCADE,
    schedule_type VARCHAR(50) NOT NULL, -- 'Time-based', 'Meter-based'
    interval_value NUMERIC(10, 2) NOT NULL,
    interval_unit VARCHAR(50) NOT NULL, -- 'Days', 'Weeks', 'Hours', 'Cycles'
    next_due_date DATE,
    next_due_meter NUMERIC(15, 2),
    is_active BOOLEAN DEFAULT TRUE
);

-- Core Work Order records
CREATE TABLE maintenance.work_orders (
    wo_id BIGSERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    type VARCHAR(50) NOT NULL, -- 'PM', 'Corrective', 'Inspection'
    asset_id BIGINT REFERENCES assets.registry(asset_id) ON DELETE RESTRICT,
    location_id INT REFERENCES core.locations(location_id) ON DELETE RESTRICT,
    reported_by_id BIGINT REFERENCES core.users(user_id) ON DELETE RESTRICT,
    assigned_to_id BIGINT REFERENCES core.users(user_id),
    pm_id BIGINT REFERENCES maintenance.preventive_schedule(pm_id) ON DELETE SET NULL,
    
    priority VARCHAR(50) NOT NULL DEFAULT 'Medium', -- 'Low', 'Medium', 'High', 'Urgent'
    status VARCHAR(50) NOT NULL DEFAULT 'Open', -- 'Draft', 'Open', 'In Progress', 'Complete', 'On Hold'
    
    requested_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    due_date TIMESTAMP WITH TIME ZONE,
    start_time TIMESTAMP WITH TIME ZONE,
    completion_time TIMESTAMP WITH TIME ZONE,
    
    labor_cost NUMERIC(15, 2) DEFAULT 0.00,
    material_cost NUMERIC(15, 2) DEFAULT 0.00,
    total_cost NUMERIC(15, 2) GENERATED ALWAYS AS (labor_cost + material_cost) STORED
);

-- Add FK to inventory.transactions after work_orders exists
ALTER TABLE inventory.transactions 
    ADD CONSTRAINT fk_transactions_wo 
    FOREIGN KEY (related_wo_id) REFERENCES maintenance.work_orders(wo_id);

-- Junction table for M:M relationship between WO and Tasks
CREATE TABLE maintenance.wo_tasks (
    wo_task_id BIGSERIAL PRIMARY KEY,
    wo_id BIGINT NOT NULL REFERENCES maintenance.work_orders(wo_id) ON DELETE CASCADE,
    task_id INT NOT NULL REFERENCES catalog.maintenance_tasks(task_id) ON DELETE RESTRICT,
    sequence_number INT NOT NULL,
    is_complete BOOLEAN DEFAULT FALSE,
    actual_time_spent NUMERIC(6, 2), -- In hours
    UNIQUE (wo_id, task_id)
);

-- Stores answers/results for checklists completed as part of a WO
CREATE TABLE maintenance.wo_checklist_answers (
    answer_id BIGSERIAL PRIMARY KEY,
    wo_id BIGINT NOT NULL REFERENCES maintenance.work_orders(wo_id) ON DELETE CASCADE,
    item_id BIGINT NOT NULL REFERENCES catalog.checklist_items(item_id) ON DELETE RESTRICT,
    user_id BIGINT REFERENCES core.users(user_id) ON DELETE RESTRICT,
    answer_value TEXT,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    UNIQUE (wo_id, item_id)
);

-- Tracks parts consumed by a Work Order
CREATE TABLE maintenance.part_usage (
    usage_id BIGSERIAL PRIMARY KEY,
    wo_id BIGINT NOT NULL REFERENCES maintenance.work_orders(wo_id) ON DELETE CASCADE,
    part_id BIGINT NOT NULL REFERENCES inventory.parts(part_id) ON DELETE RESTRICT,
    storeroom_id INT NOT NULL REFERENCES inventory.storerooms(storeroom_id) ON DELETE RESTRICT,
    quantity_used NUMERIC(10, 2) NOT NULL,
    unit_cost_at_time NUMERIC(10, 4) NOT NULL, -- Historical cost capture
    user_id BIGINT REFERENCES core.users(user_id) ON DELETE RESTRICT,
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- ====================================================================================
-- MÓDULO ANALYTICS: Audit, Reports & Intelligence
-- ====================================================================================

-- User alerts and system messages
CREATE TABLE analytics.notifications (
    notification_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES core.users(user_id) ON DELETE CASCADE,
    related_entity_type VARCHAR(50), -- 'WO', 'Asset', 'PM'
    related_entity_id BIGINT,
    message TEXT NOT NULL,
    type VARCHAR(50),
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Definitions for saved or scheduled analytical reports
CREATE TABLE analytics.reports (
    report_id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    definition JSONB, -- Query parameters, filters, display settings
    created_by_id BIGINT REFERENCES core.users(user_id) ON DELETE RESTRICT,
    last_generated TIMESTAMP WITH TIME ZONE
);

-- Comprehensive Audit Trail for key changes
CREATE TABLE analytics.audit_logs (
    log_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT REFERENCES core.users(user_id),
    table_name VARCHAR(100) NOT NULL,
    record_id BIGINT NOT NULL,
    action_type VARCHAR(10) NOT NULL, -- 'INSERT', 'UPDATE', 'DELETE'
    change_details JSONB, -- Before/after values
    timestamp TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- ====================================================================================
-- PERFORMANCE OPTIMIZATION: INDEXES
-- ====================================================================================

-- Core indexes
CREATE INDEX idx_users_email ON core.users(email);
CREATE INDEX idx_users_role ON core.users(role_id);

-- Asset indexes
CREATE INDEX idx_asset_location ON assets.registry(location_id);
CREATE INDEX idx_asset_type ON assets.registry(asset_type_id);
CREATE INDEX idx_asset_tag ON assets.registry(tag_number);
CREATE INDEX idx_asset_status ON assets.registry(status);
CREATE INDEX idx_asset_custom_gin ON assets.registry USING GIN (custom_fields);

-- Readings indexes (time-series optimization)
CREATE INDEX idx_readings_asset_time ON assets.readings(asset_id, timestamp DESC);
CREATE INDEX idx_readings_type ON assets.readings(reading_type);

-- Inventory indexes
CREATE INDEX idx_stock_part ON inventory.stock(part_id);
CREATE INDEX idx_stock_storeroom ON inventory.stock(storeroom_id);
CREATE INDEX idx_transactions_stock ON inventory.transactions(stock_id);
CREATE INDEX idx_transactions_time ON inventory.transactions(timestamp DESC);

-- Work Order indexes (most queried table)
CREATE INDEX idx_wo_asset ON maintenance.work_orders(asset_id);
CREATE INDEX idx_wo_status ON maintenance.work_orders(status);
CREATE INDEX idx_wo_priority ON maintenance.work_orders(priority);
CREATE INDEX idx_wo_assigned ON maintenance.work_orders(assigned_to_id);
CREATE INDEX idx_wo_due_date ON maintenance.work_orders(due_date);
CREATE INDEX idx_wo_pm ON maintenance.work_orders(pm_id);

-- Part usage indexes
CREATE INDEX idx_part_usage_wo ON maintenance.part_usage(wo_id);
CREATE INDEX idx_part_usage_part ON maintenance.part_usage(part_id);

-- Analytics indexes
CREATE INDEX idx_audit_table_record ON analytics.audit_logs(table_name, record_id);
CREATE INDEX idx_audit_timestamp ON analytics.audit_logs(timestamp DESC);
CREATE INDEX idx_notifications_user ON analytics.notifications(user_id, is_read);

-- ====================================================================================
-- ANALYTICS VIEW: The "Ficha Maestra" (Palantir Philosophy)
-- ====================================================================================

CREATE OR REPLACE VIEW analytics.v_asset_360 AS
SELECT 
    -- 1. Asset Identity
    a.asset_id,
    a.name AS asset_name,
    a.tag_number,
    a.serial_number,
    a.status,
    a.criticality,
    t.name AS asset_type,
    l.name AS location_name,
    a.manufacturer,
    a.model,
    a.install_date,
    
    -- 2. Total Cost of Ownership (TCO)
    a.purchase_cost,
    COALESCE(wo_stats.total_maintenance_cost, 0) AS total_maintenance_cost,
    (COALESCE(a.purchase_cost, 0) + COALESCE(wo_stats.total_maintenance_cost, 0)) AS total_lifecycle_cost,
    
    -- 3. Operational Metrics
    COALESCE(wo_stats.total_work_orders, 0) AS total_work_orders,
    COALESCE(wo_stats.open_work_orders, 0) AS open_work_orders,
    COALESCE(wo_stats.completed_work_orders, 0) AS completed_work_orders,
    wo_stats.last_wo_date,
    
    -- 4. Preventive Maintenance Status
    pm.next_pm_date,
    pm.active_pm_count,
    
    -- 5. Health Score (Business Logic in SQL)
    CASE 
        WHEN a.status = 'Down' THEN 'CRITICAL'
        WHEN pm.next_pm_date < CURRENT_DATE THEN 'OVERDUE'
        WHEN wo_stats.open_work_orders > 3 THEN 'AT_RISK'
        WHEN wo_stats.open_work_orders > 0 THEN 'ATTENTION'
        ELSE 'HEALTHY'
    END AS health_score,
    
    -- 6. Last Telemetry Reading (IoT)
    lr.reading_type AS last_reading_type,
    lr.value AS last_reading_value,
    lr.unit AS last_reading_unit,
    lr.timestamp AS last_reading_time,
    lr.source AS last_reading_source,
    
    -- 7. Custom Fields (Flexible Data)
    a.custom_fields

FROM assets.registry a
    JOIN assets.types t ON a.asset_type_id = t.asset_type_id
    JOIN core.locations l ON a.location_id = l.location_id
    
    -- Aggregated Work Order statistics
    LEFT JOIN (
        SELECT 
            asset_id,
            COUNT(*) AS total_work_orders,
            COUNT(*) FILTER (WHERE status NOT IN ('Complete', 'Cancelled')) AS open_work_orders,
            COUNT(*) FILTER (WHERE status = 'Complete') AS completed_work_orders,
            SUM(total_cost) AS total_maintenance_cost,
            MAX(completion_time) AS last_wo_date
        FROM maintenance.work_orders
        GROUP BY asset_id
    ) wo_stats ON a.asset_id = wo_stats.asset_id
    
    -- Preventive Maintenance stats
    LEFT JOIN (
        SELECT 
            asset_id, 
            MIN(next_due_date) AS next_pm_date,
            COUNT(*) FILTER (WHERE is_active = true) AS active_pm_count
        FROM maintenance.preventive_schedule
        GROUP BY asset_id
    ) pm ON a.asset_id = pm.asset_id
    
    -- Latest sensor reading (Lateral Join for efficiency)
    LEFT JOIN LATERAL (
        SELECT reading_type, value, unit, timestamp, source
        FROM assets.readings r
        WHERE r.asset_id = a.asset_id
        ORDER BY timestamp DESC
        LIMIT 1
    ) lr ON true;

-- ====================================================================================
-- COMMENTS: Schema Documentation
-- ====================================================================================

COMMENT ON SCHEMA core IS 'Identity, authentication, and organizational context';
COMMENT ON SCHEMA assets IS 'Asset ontology, registry, and telemetry data';
COMMENT ON SCHEMA catalog IS 'Reusable templates: tasks, checklists, procedures';
COMMENT ON SCHEMA inventory IS 'Parts, suppliers, stock levels, and transactions';
COMMENT ON SCHEMA maintenance IS 'Work order execution, preventive schedules, and part usage';
COMMENT ON SCHEMA analytics IS 'Audit trails, reports, notifications, and intelligence views';

COMMENT ON VIEW analytics.v_asset_360 IS 'Unified asset intelligence view - the "Ficha Maestra"';
