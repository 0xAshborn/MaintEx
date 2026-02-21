-- ====================================================================================
-- SYNAPTIA TECHNOLOGIES - CORTEX MASTER DATABASE SCHEMA
-- Includes: Core Schema, KPI Views, and Backlog Analysis
-- Motor: PostgreSQL 14+
-- ====================================================================================

-- ####################################################################################
-- PART 1: CORE SCHEMA (from CORTEX.sql)
-- ####################################################################################

-- 1. SCHEMA DEFINITIONS (Bounded Contexts)
CREATE SCHEMA IF NOT EXISTS core;        -- Identity, Auth, Locations
CREATE SCHEMA IF NOT EXISTS assets;      -- Asset Ontology & Telemetry
CREATE SCHEMA IF NOT EXISTS catalog;     -- Templates & Definitions
CREATE SCHEMA IF NOT EXISTS inventory;   -- Parts, Stock, Transactions
CREATE SCHEMA IF NOT EXISTS maintenance; -- Work Orders, PMs, Execution
CREATE SCHEMA IF NOT EXISTS analytics;   -- Audit, Reports, Intelligence

-- MÓDULO CORE: Identity & Context
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

-- MÓDULO ASSETS: The Ontology Layer
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

-- MÓDULO CATALOG: Templates & Definitions
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

-- MÓDULO INVENTORY: Parts & Stock Management
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

-- MÓDULO MAINTENANCE: Work Execution & Scheduling
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

-- MÓDULO ANALYTICS: Audit, Reports & Intelligence
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

-- PERFORMANCE OPTIMIZATION: INDEXES
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

-- ANALYTICS VIEW: The \"Ficha Maestra\" (Palantir Philosophy)
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

-- COMMENTS: Schema Documentation
COMMENT ON SCHEMA core IS 'Identity, authentication, and organizational context';
COMMENT ON SCHEMA assets IS 'Asset ontology, registry, and telemetry data';
COMMENT ON SCHEMA catalog IS 'Reusable templates: tasks, checklists, procedures';
COMMENT ON SCHEMA inventory IS 'Parts, suppliers, stock levels, and transactions';
COMMENT ON SCHEMA maintenance IS 'Work order execution, preventive schedules, and part usage';
COMMENT ON SCHEMA analytics IS 'Audit trails, reports, notifications, and intelligence views';
COMMENT ON VIEW analytics.v_asset_360 IS 'Unified asset intelligence view - the \"Ficha Maestra\"';

-- ####################################################################################
-- PART 2: KPI VIEWS & DOWNTIME TRACKING (from kpi_views.sql)
-- ####################################################################################

-- NEW TABLE: Downtime Events (For accurate KPI calculation)
CREATE TABLE assets.downtime_events (
    event_id BIGSERIAL PRIMARY KEY,
    asset_id BIGINT NOT NULL REFERENCES assets.registry(asset_id) ON DELETE CASCADE,
    started_at TIMESTAMP WITH TIME ZONE NOT NULL,
    ended_at TIMESTAMP WITH TIME ZONE,
    reason VARCHAR(100) NOT NULL, -- 'Breakdown', 'PM', 'Changeover', 'Setup'
    failure_code VARCHAR(100),
    wo_id BIGINT REFERENCES maintenance.work_orders(wo_id),
    notes TEXT,
    created_by BIGINT REFERENCES core.users(user_id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_downtime_asset ON assets.downtime_events(asset_id);
CREATE INDEX idx_downtime_dates ON assets.downtime_events(started_at, ended_at);
CREATE INDEX idx_downtime_reason ON assets.downtime_events(reason);

-- VIEW: Downtime Events with Calculated Duration
CREATE OR REPLACE VIEW analytics.v_downtime_events AS
SELECT 
    event_id,
    asset_id,
    started_at,
    ended_at,
    ROUND(EXTRACT(EPOCH FROM (COALESCE(ended_at, NOW()) - started_at)) / 3600, 2) AS duration_hours,
    reason,
    failure_code,
    wo_id,
    notes,
    created_by,
    created_at
FROM assets.downtime_events;

-- VIEW: Asset Failure Events (Breakdowns Only)
CREATE OR REPLACE VIEW analytics.v_asset_failures AS
SELECT 
    asset_id,
    event_id,
    started_at AS failure_start,
    ended_at AS failure_end,
    duration_hours AS repair_time_hours,
    failure_code,
    wo_id
FROM analytics.v_downtime_events
WHERE reason = 'Breakdown'
  AND ended_at IS NOT NULL;

-- VIEW: MTTR (Mean Time To Repair)
CREATE OR REPLACE VIEW analytics.v_asset_mttr AS
SELECT 
    a.asset_id,
    a.name AS asset_name,
    a.tag_number,
    t.name AS asset_type,
    COUNT(f.event_id) AS failure_count,
    COALESCE(SUM(f.repair_time_hours), 0) AS total_repair_hours,
    CASE 
        WHEN COUNT(f.event_id) > 0 
        THEN ROUND(SUM(f.repair_time_hours) / COUNT(f.event_id), 2)
        ELSE 0 
    END AS mttr_hours
FROM assets.registry a
    JOIN assets.types t ON a.asset_type_id = t.asset_type_id
    LEFT JOIN analytics.v_asset_failures f ON a.asset_id = f.asset_id
GROUP BY a.asset_id, a.name, a.tag_number, t.name;

-- VIEW: MTBF (Mean Time Between Failures)
CREATE OR REPLACE VIEW analytics.v_asset_mtbf AS
WITH asset_timeline AS (
    SELECT 
        a.asset_id,
        a.name AS asset_name,
        a.tag_number,
        t.name AS asset_type,
        a.install_date,
        EXTRACT(EPOCH FROM (NOW() - a.install_date::timestamp)) / 3600 AS total_hours,
        COALESCE(SUM(d.duration_hours), 0) AS total_downtime_hours,
        COUNT(d.event_id) FILTER (WHERE d.reason = 'Breakdown') AS failure_count
    FROM assets.registry a
        JOIN assets.types t ON a.asset_type_id = t.asset_type_id
        LEFT JOIN analytics.v_downtime_events d ON a.asset_id = d.asset_id
    WHERE a.install_date IS NOT NULL
    GROUP BY a.asset_id, a.name, a.tag_number, t.name, a.install_date
)
SELECT 
    asset_id,
    asset_name,
    tag_number,
    asset_type,
    install_date,
    ROUND(total_hours, 2) AS total_hours,
    ROUND(total_downtime_hours, 2) AS downtime_hours,
    ROUND(total_hours - total_downtime_hours, 2) AS operating_hours,
    failure_count,
    CASE 
        WHEN failure_count > 0 
        THEN ROUND((total_hours - total_downtime_hours) / failure_count, 2)
        ELSE NULL 
    END AS mtbf_hours
FROM asset_timeline;

-- VIEW: MTTF (Mean Time To Failure)
CREATE OR REPLACE VIEW analytics.v_asset_mttf AS
WITH first_failures AS (
    SELECT 
        asset_id,
        MIN(started_at) AS first_failure_date
    FROM assets.downtime_events
    WHERE reason = 'Breakdown'
    GROUP BY asset_id
)
SELECT 
    a.asset_id,
    a.name AS asset_name,
    a.tag_number,
    a.install_date,
    ff.first_failure_date,
    CASE 
        WHEN ff.first_failure_date IS NOT NULL 
        THEN ROUND(EXTRACT(EPOCH FROM (ff.first_failure_date - a.install_date::timestamp)) / 3600, 2)
        ELSE NULL 
    END AS mttf_hours
FROM assets.registry a
    LEFT JOIN first_failures ff ON a.asset_id = ff.asset_id
WHERE a.install_date IS NOT NULL;

-- VIEW: Availability
CREATE OR REPLACE VIEW analytics.v_asset_availability AS
WITH availability_calc AS (
    SELECT 
        a.asset_id,
        a.name AS asset_name,
        a.tag_number,
        t.name AS asset_type,
        a.install_date,
        EXTRACT(EPOCH FROM (NOW() - a.install_date::timestamp)) / 3600 AS total_hours,
        COALESCE(SUM(d.duration_hours), 0) AS downtime_hours
    FROM assets.registry a
        JOIN assets.types t ON a.asset_type_id = t.asset_type_id
        LEFT JOIN analytics.v_downtime_events d ON a.asset_id = d.asset_id
    WHERE a.install_date IS NOT NULL
    GROUP BY a.asset_id, a.name, a.tag_number, t.name, a.install_date
)
SELECT 
    asset_id,
    asset_name,
    tag_number,
    asset_type,
    ROUND(total_hours, 2) AS total_hours,
    ROUND(downtime_hours, 2) AS downtime_hours,
    ROUND(total_hours - downtime_hours, 2) AS uptime_hours,
    CASE 
        WHEN total_hours > 0 
        THEN ROUND(((total_hours - downtime_hours) / total_hours) * 100, 2)
        ELSE 100.00
    END AS availability_percent
FROM availability_calc;

-- VIEW: Utilization
CREATE OR REPLACE VIEW analytics.v_asset_utilization AS
WITH runtime_data AS (
    SELECT 
        a.asset_id,
        a.name AS asset_name,
        a.tag_number,
        (SELECT value FROM assets.readings r 
         WHERE r.asset_id = a.asset_id 
         AND r.reading_type IN ('Runtime', 'Operating Hours', 'Hourmeter')
         ORDER BY timestamp DESC LIMIT 1) AS actual_runtime_hours,
        EXTRACT(EPOCH FROM (NOW() - a.install_date::timestamp)) / 3600 * (8.0/24.0) AS planned_hours
    FROM assets.registry a
    WHERE a.install_date IS NOT NULL
)
SELECT 
    asset_id,
    asset_name,
    tag_number,
    ROUND(COALESCE(actual_runtime_hours, 0), 2) AS actual_runtime_hours,
    ROUND(planned_hours, 2) AS planned_hours,
    CASE 
        WHEN planned_hours > 0 AND actual_runtime_hours IS NOT NULL
        THEN ROUND((actual_runtime_hours / planned_hours) * 100, 2)
        ELSE NULL
    END AS utilization_percent
FROM runtime_data;

-- VIEW: Reliability
CREATE OR REPLACE VIEW analytics.v_asset_reliability AS
SELECT 
    asset_id,
    asset_name,
    tag_number,
    asset_type,
    mtbf_hours,
    CASE 
        WHEN mtbf_hours IS NOT NULL AND mtbf_hours > 0
        THEN ROUND(EXP(-720.0 / mtbf_hours) * 100, 2)
        ELSE 100.00 
    END AS reliability_30day_percent,
    CASE 
        WHEN mtbf_hours IS NOT NULL AND mtbf_hours > 0
        THEN ROUND(EXP(-168.0 / mtbf_hours) * 100, 2)
        ELSE 100.00
    END AS reliability_7day_percent
FROM analytics.v_asset_mtbf;

-- MASTER VIEW: KPI Summary Dashboard
CREATE OR REPLACE VIEW analytics.v_kpi_dashboard AS
SELECT 
    a.asset_id,
    a.asset_name,
    a.tag_number,
    a.asset_type,
    a.availability_percent,
    r.reliability_30day_percent,
    r.reliability_7day_percent,
    u.utilization_percent,
    m.mttr_hours,
    b.mtbf_hours,
    f.mttf_hours,
    m.failure_count,
    CASE 
        WHEN a.availability_percent < 80 THEN 'CRITICAL'
        WHEN a.availability_percent < 90 THEN 'WARNING'
        WHEN r.reliability_30day_percent < 70 THEN 'AT_RISK'
        ELSE 'HEALTHY'
    END AS kpi_health_status
FROM analytics.v_asset_availability a
    LEFT JOIN analytics.v_asset_reliability r ON a.asset_id = r.asset_id
    LEFT JOIN analytics.v_asset_utilization u ON a.asset_id = u.asset_id
    LEFT JOIN analytics.v_asset_mttr m ON a.asset_id = m.asset_id
    LEFT JOIN analytics.v_asset_mtbf b ON a.asset_id = b.asset_id
    LEFT JOIN analytics.v_asset_mttf f ON a.asset_id = f.asset_id;

-- FUNCTION: Get KPIs for Date Range
CREATE OR REPLACE FUNCTION analytics.get_asset_kpis(
    p_asset_id BIGINT,
    p_start_date DATE DEFAULT NULL,
    p_end_date DATE DEFAULT NULL
)
RETURNS TABLE (
    asset_id BIGINT,
    asset_name VARCHAR,
    availability_percent NUMERIC,
    mttr_hours NUMERIC,
    mtbf_hours NUMERIC,
    failure_count BIGINT,
    period_start DATE,
    period_end DATE
) AS $$
BEGIN
    RETURN QUERY
    WITH period_downtime AS (
        SELECT 
            d.asset_id,
            COUNT(d.event_id) FILTER (WHERE d.reason = 'Breakdown') AS failures,
            COALESCE(SUM(d.duration_hours), 0) AS downtime_hrs,
            COALESCE(SUM(d.duration_hours) FILTER (WHERE d.reason = 'Breakdown'), 0) AS repair_hrs
        FROM assets.downtime_events d
        WHERE d.asset_id = p_asset_id
          AND (p_start_date IS NULL OR d.started_at >= p_start_date)
          AND (p_end_date IS NULL OR d.started_at <= p_end_date)
        GROUP BY d.asset_id
    ),
    period_hours AS (
        SELECT 
            EXTRACT(EPOCH FROM (
                COALESCE(p_end_date::timestamp, NOW()) - 
                COALESCE(p_start_date::timestamp, a.install_date::timestamp)
            )) / 3600 AS total_hrs
        FROM assets.registry a
        WHERE a.asset_id = p_asset_id
    )
    SELECT 
        a.asset_id,
        a.name,
        ROUND(((ph.total_hrs - COALESCE(pd.downtime_hrs, 0)) / ph.total_hrs) * 100, 2),
        CASE WHEN pd.failures > 0 THEN ROUND(pd.repair_hrs / pd.failures, 2) ELSE 0 END,
        CASE WHEN pd.failures > 0 THEN ROUND((ph.total_hrs - COALESCE(pd.downtime_hrs, 0)) / pd.failures, 2) ELSE NULL END,
        COALESCE(pd.failures, 0),
        COALESCE(p_start_date, a.install_date),
        COALESCE(p_end_date, CURRENT_DATE)
    FROM assets.registry a
        CROSS JOIN period_hours ph
        LEFT JOIN period_downtime pd ON a.asset_id = pd.asset_id
    WHERE a.asset_id = p_asset_id;
END;
$$ LANGUAGE plpgsql;

-- COMMENTS
COMMENT ON TABLE assets.downtime_events IS 'Tracks all asset downtime periods for KPI calculation';
COMMENT ON VIEW analytics.v_asset_mttr IS 'Mean Time To Repair - average repair duration';
COMMENT ON VIEW analytics.v_asset_mtbf IS 'Mean Time Between Failures - reliability metric';
COMMENT ON VIEW analytics.v_asset_availability IS 'Asset availability percentage based on uptime';
COMMENT ON VIEW analytics.v_kpi_dashboard IS 'Master KPI dashboard combining all metrics';
COMMENT ON FUNCTION analytics.get_asset_kpis IS 'Calculate KPIs for a specific asset and date range';

-- ####################################################################################
-- PART 3: BACKLOG VIEWS (from backlog_views.sql)
-- ####################################################################################

-- VIEW: Work Order Backlog (All open/pending work)
CREATE OR REPLACE VIEW analytics.v_wo_backlog AS
SELECT 
    wo.wo_id,
    wo.title,
    wo.description,
    wo.type,
    wo.priority,
    wo.status,
    wo.requested_date,
    wo.due_date,
    wo.start_time,
    a.name AS asset_name,
    a.tag_number,
    a.criticality AS asset_criticality,
    l.name AS location_name,
    TRIM(CONCAT(req.first_name, ' ', req.last_name)) AS requested_by,
    TRIM(CONCAT(asn.first_name, ' ', asn.last_name)) AS assigned_to,
    ROUND(EXTRACT(EPOCH FROM (NOW() - wo.requested_date)) / 86400, 1) AS age_days,
    CASE 
        WHEN wo.due_date IS NOT NULL AND wo.due_date < NOW()
        THEN ROUND(EXTRACT(EPOCH FROM (NOW() - wo.due_date)) / 86400, 1)
        ELSE 0
    END AS overdue_days,
    CASE 
        WHEN wo.due_date IS NOT NULL AND wo.due_date < NOW() THEN TRUE
        ELSE FALSE
    END AS is_overdue,
    CASE 
        WHEN wo.priority = 'Urgent' THEN 1
        WHEN wo.due_date IS NOT NULL AND wo.due_date < NOW() THEN 2
        WHEN wo.priority = 'High' THEN 3
        WHEN wo.priority = 'Medium' THEN 4
        ELSE 5
    END AS urgency_rank,
    CASE 
        WHEN wo.priority = 'Urgent' THEN 'CRITICAL'
        WHEN wo.due_date IS NOT NULL AND wo.due_date < NOW() AND wo.priority IN ('High', 'Urgent') THEN 'CRITICAL'
        WHEN wo.due_date IS NOT NULL AND wo.due_date < NOW() THEN 'OVERDUE'
        WHEN wo.due_date IS NOT NULL AND wo.due_date < NOW() + INTERVAL '3 days' THEN 'DUE_SOON'
        WHEN wo.priority = 'High' THEN 'HIGH'
        ELSE 'NORMAL'
    END AS urgency_level
FROM maintenance.work_orders wo
    LEFT JOIN assets.registry a ON wo.asset_id = a.asset_id
    LEFT JOIN core.locations l ON wo.location_id = l.location_id
    LEFT JOIN core.users req ON wo.reported_by_id = req.user_id
    LEFT JOIN core.users asn ON wo.assigned_to_id = asn.user_id
WHERE wo.status NOT IN ('Complete', 'Cancelled')
ORDER BY urgency_rank ASC, wo.requested_date ASC;

-- VIEW: PM Backlog (Overdue + Unscheduled Preventive Maintenance)
CREATE OR REPLACE VIEW analytics.v_pm_backlog AS
SELECT 
    pm.pm_id,
    pm.name AS pm_name,
    pm.schedule_type,
    pm.interval_value,
    pm.interval_unit,
    pm.next_due_date,
    pm.next_due_meter,
    a.asset_id,
    a.name AS asset_name,
    a.tag_number,
    a.criticality AS asset_criticality,
    CASE 
        WHEN pm.next_due_date IS NOT NULL AND pm.next_due_date < CURRENT_DATE
        THEN (CURRENT_DATE - pm.next_due_date)
        ELSE 0
    END AS overdue_days,
    CASE 
        WHEN pm.next_due_date IS NULL THEN 'UNSCHEDULED'
        WHEN pm.next_due_date < CURRENT_DATE - INTERVAL '30 days' THEN 'CRITICAL_OVERDUE'
        WHEN pm.next_due_date < CURRENT_DATE - INTERVAL '7 days' THEN 'OVERDUE'
        WHEN pm.next_due_date < CURRENT_DATE THEN 'RECENTLY_OVERDUE'
        WHEN pm.next_due_date <= CURRENT_DATE + INTERVAL '7 days' THEN 'DUE_SOON'
        ELSE 'SCHEDULED'
    END AS backlog_status,
    CASE 
        WHEN pm.next_due_date IS NULL THEN 3
        WHEN pm.next_due_date < CURRENT_DATE - INTERVAL '30 days' THEN 1
        WHEN pm.next_due_date < CURRENT_DATE THEN 2
        ELSE 4
    END AS urgency_rank
FROM maintenance.preventive_schedule pm
    JOIN assets.registry a ON pm.asset_id = a.asset_id
WHERE pm.is_active = TRUE
ORDER BY urgency_rank ASC, pm.next_due_date ASC NULLS FIRST;

-- VIEW: Combined Backlog Summary
CREATE OR REPLACE VIEW analytics.v_backlog_summary AS
SELECT 
    (SELECT COUNT(*) FROM maintenance.work_orders 
     WHERE status NOT IN ('Complete', 'Cancelled')) AS total_open_wo,
    (SELECT COUNT(*) FROM maintenance.work_orders 
     WHERE status NOT IN ('Complete', 'Cancelled') 
     AND due_date IS NOT NULL AND due_date < NOW()) AS overdue_wo,
    (SELECT COUNT(*) FROM maintenance.work_orders 
     WHERE status = 'Open') AS unstarted_wo,
    (SELECT COUNT(*) FROM maintenance.work_orders 
     WHERE status = 'In Progress') AS in_progress_wo,
    (SELECT COUNT(*) FROM maintenance.work_orders 
     WHERE status = 'On Hold') AS on_hold_wo,
    (SELECT COUNT(*) FROM maintenance.preventive_schedule 
     WHERE is_active = TRUE AND next_due_date IS NOT NULL 
     AND next_due_date < CURRENT_DATE) AS overdue_pm,
    (SELECT COUNT(*) FROM maintenance.preventive_schedule 
     WHERE is_active = TRUE AND next_due_date IS NULL) AS unscheduled_pm,
    (SELECT COUNT(*) FROM maintenance.preventive_schedule 
     WHERE is_active = TRUE AND next_due_date BETWEEN CURRENT_DATE 
     AND CURRENT_DATE + INTERVAL '7 days') AS pm_due_this_week,
    (SELECT COUNT(*) FROM maintenance.work_orders 
     WHERE status NOT IN ('Complete', 'Cancelled'))
    + 
    (SELECT COUNT(*) FROM maintenance.preventive_schedule 
     WHERE is_active = TRUE AND next_due_date IS NOT NULL 
     AND next_due_date < CURRENT_DATE) AS total_backlog,
    (SELECT ROUND(AVG(EXTRACT(EPOCH FROM (NOW() - requested_date)) / 86400), 1)
     FROM maintenance.work_orders 
     WHERE status NOT IN ('Complete', 'Cancelled')) AS avg_wo_age_days;

-- VIEW: Backlog by Priority
CREATE OR REPLACE VIEW analytics.v_backlog_by_priority AS
SELECT 
    wo.priority,
    COUNT(*) AS total_count,
    COUNT(*) FILTER (WHERE wo.due_date IS NOT NULL AND wo.due_date < NOW()) AS overdue_count,
    COUNT(*) FILTER (WHERE wo.status = 'Open') AS open_count,
    COUNT(*) FILTER (WHERE wo.status = 'In Progress') AS in_progress_count,
    ROUND(AVG(EXTRACT(EPOCH FROM (NOW() - wo.requested_date)) / 86400), 1) AS avg_age_days
FROM maintenance.work_orders wo
WHERE wo.status NOT IN ('Complete', 'Cancelled')
GROUP BY wo.priority
ORDER BY 
    CASE wo.priority 
        WHEN 'Urgent' THEN 1 
        WHEN 'High' THEN 2 
        WHEN 'Medium' THEN 3 
        WHEN 'Low' THEN 4 
    END;

-- VIEW: Backlog by Asset
CREATE OR REPLACE VIEW analytics.v_backlog_by_asset AS
SELECT 
    a.asset_id,
    a.name AS asset_name,
    a.tag_number,
    a.criticality,
    COUNT(wo.wo_id) AS open_wo_count,
    COUNT(wo.wo_id) FILTER (WHERE wo.due_date IS NOT NULL AND wo.due_date < NOW()) AS overdue_wo_count,
    (SELECT COUNT(*) FROM maintenance.preventive_schedule pm 
     WHERE pm.asset_id = a.asset_id AND pm.is_active = TRUE 
     AND pm.next_due_date IS NOT NULL AND pm.next_due_date < CURRENT_DATE) AS overdue_pm_count,
    COUNT(wo.wo_id) + 
    (SELECT COUNT(*) FROM maintenance.preventive_schedule pm 
     WHERE pm.asset_id = a.asset_id AND pm.is_active = TRUE 
     AND pm.next_due_date IS NOT NULL AND pm.next_due_date < CURRENT_DATE) AS total_backlog
FROM assets.registry a
    LEFT JOIN maintenance.work_orders wo ON a.asset_id = wo.asset_id 
        AND wo.status NOT IN ('Complete', 'Cancelled')
GROUP BY a.asset_id, a.name, a.tag_number, a.criticality
HAVING COUNT(wo.wo_id) > 0 
    OR (SELECT COUNT(*) FROM maintenance.preventive_schedule pm 
        WHERE pm.asset_id = a.asset_id AND pm.is_active = TRUE 
        AND pm.next_due_date IS NOT NULL AND pm.next_due_date < CURRENT_DATE) > 0
ORDER BY total_backlog DESC;

-- VIEW: Backlog Aging Buckets
CREATE OR REPLACE VIEW analytics.v_backlog_aging AS
SELECT 
    bucket,
    bucket_order,
    COUNT(*) AS wo_count,
    SUM(CASE WHEN priority = 'Urgent' THEN 1 ELSE 0 END) AS urgent_count,
    SUM(CASE WHEN priority = 'High' THEN 1 ELSE 0 END) AS high_count
FROM (
    SELECT 
        wo.priority,
        CASE 
            WHEN EXTRACT(EPOCH FROM (NOW() - wo.requested_date)) / 86400 <= 1 THEN 'Today'
            WHEN EXTRACT(EPOCH FROM (NOW() - wo.requested_date)) / 86400 <= 3 THEN '1-3 Days'
            WHEN EXTRACT(EPOCH FROM (NOW() - wo.requested_date)) / 86400 <= 7 THEN '4-7 Days'
            WHEN EXTRACT(EPOCH FROM (NOW() - wo.requested_date)) / 86400 <= 14 THEN '1-2 Weeks'
            WHEN EXTRACT(EPOCH FROM (NOW() - wo.requested_date)) / 86400 <= 30 THEN '2-4 Weeks'
            ELSE '30+ Days'
        END AS bucket,
        CASE 
            WHEN EXTRACT(EPOCH FROM (NOW() - wo.requested_date)) / 86400 <= 1 THEN 1
            WHEN EXTRACT(EPOCH FROM (NOW() - wo.requested_date)) / 86400 <= 3 THEN 2
            WHEN EXTRACT(EPOCH FROM (NOW() - wo.requested_date)) / 86400 <= 7 THEN 3
            WHEN EXTRACT(EPOCH FROM (NOW() - wo.requested_date)) / 86400 <= 14 THEN 4
            WHEN EXTRACT(EPOCH FROM (NOW() - wo.requested_date)) / 86400 <= 30 THEN 5
            ELSE 6
        END AS bucket_order
    FROM maintenance.work_orders wo
    WHERE wo.status NOT IN ('Complete', 'Cancelled')
) aged
GROUP BY bucket, bucket_order
ORDER BY bucket_order;

-- FUNCTION: Get Backlog Trend
CREATE OR REPLACE FUNCTION analytics.get_backlog_trend(
    p_start_date DATE DEFAULT CURRENT_DATE - INTERVAL '30 days',
    p_end_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    report_date DATE,
    opened_count BIGINT,
    closed_count BIGINT,
    net_change BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        d.dt::DATE AS report_date,
        (SELECT COUNT(*) FROM maintenance.work_orders 
         WHERE requested_date::DATE = d.dt::DATE) AS opened_count,
        (SELECT COUNT(*) FROM maintenance.work_orders 
         WHERE completion_time::DATE = d.dt::DATE) AS closed_count,
        (SELECT COUNT(*) FROM maintenance.work_orders 
         WHERE requested_date::DATE = d.dt::DATE)
        -
        (SELECT COUNT(*) FROM maintenance.work_orders 
         WHERE completion_time::DATE = d.dt::DATE) AS net_change
    FROM generate_series(p_start_date, p_end_date, '1 day'::interval) d(dt)
    ORDER BY d.dt;
END;
$$ LANGUAGE plpgsql;

-- COMMENTS
COMMENT ON VIEW analytics.v_wo_backlog IS 'All open/pending work orders with aging and urgency classification';
COMMENT ON VIEW analytics.v_pm_backlog IS 'Overdue and unscheduled preventive maintenance tasks';
COMMENT ON VIEW analytics.v_backlog_summary IS 'Single-row dashboard summary of all backlog counts';
COMMENT ON VIEW analytics.v_backlog_by_priority IS 'Backlog breakdown by work order priority';
COMMENT ON VIEW analytics.v_backlog_by_asset IS 'Which assets have the most pending work';
COMMENT ON VIEW analytics.v_backlog_aging IS 'Age distribution of open work orders in time buckets';
COMMENT ON FUNCTION analytics.get_backlog_trend IS 'Daily trend of opened vs closed work orders for backlog analysis';
