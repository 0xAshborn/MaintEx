-- ====================================================================================
-- SYNAPTIA TECHNOLOGIES - CORTEX MASTER v1.2
-- Full CMMS Database Schema — Multi-Tenant (Row-Level Security)
-- Motor: PostgreSQL 14+
-- Architecture: 6 Bounded Contexts + Strict Multi-Tenancy via RLS
-- ====================================================================================
-- EXECUTION ORDER (run entire file top-to-bottom):
--   1. Schemas & DB roles
--   2. core (tenants, roles, permissions, users, locations)
--   3. assets (types, registry, readings, downtime_events)
--   4. catalog (tasks, checklists, items)
--   5. inventory (suppliers, parts, storerooms, stock, transactions)
--   6. maintenance (preventive_schedule, work_orders, details)
--   7. analytics (notifications, reports, audit_logs)
--   8. Indexes
--   9. Analytics views (v_asset_360, KPI, Backlog)
--  10. Row-Level Security (enable + policies)
--  11. Seed data & helper functions
-- ====================================================================================

-- ####################################################################################
-- STEP 0: CLEAN SLATE — Drop existing schemas in dependency order
-- WARNING: This destroys ALL existing CORTEX data. This file is a full rebuild.
-- Comment out this block if you want to preserve existing data.
-- ####################################################################################

DROP SCHEMA IF EXISTS analytics  CASCADE;
DROP SCHEMA IF EXISTS maintenance CASCADE;
DROP SCHEMA IF EXISTS inventory   CASCADE;
DROP SCHEMA IF EXISTS catalog     CASCADE;
DROP SCHEMA IF EXISTS assets      CASCADE;
DROP SCHEMA IF EXISTS core        CASCADE;

-- ####################################################################################
-- STEP 1: SCHEMAS & DATABASE ROLES
-- ####################################################################################

CREATE SCHEMA IF NOT EXISTS core;        -- Identity, Auth, Locations, Tenants
CREATE SCHEMA IF NOT EXISTS assets;      -- Asset Ontology & Telemetry
CREATE SCHEMA IF NOT EXISTS catalog;     -- Templates & Definitions
CREATE SCHEMA IF NOT EXISTS inventory;   -- Parts, Stock, Transactions
CREATE SCHEMA IF NOT EXISTS maintenance; -- Work Orders, PMs, Execution
CREATE SCHEMA IF NOT EXISTS analytics;   -- Audit, Reports, Intelligence

-- DB Roles
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'synaptia_admin') THEN
        CREATE ROLE synaptia_admin NOLOGIN BYPASSRLS;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_user') THEN
        CREATE ROLE app_user NOLOGIN;
    END IF;
END
$$;

-- ####################################################################################
-- STEP 2: CORE MODULE
-- ####################################################################################

-- ─── core.tenants ────────────────────────────────────────────────────────────────────
-- Root B2B client entity. Every data row in the system belongs to a tenant.
CREATE TABLE IF NOT EXISTS core.tenants (
    tenant_id    BIGSERIAL PRIMARY KEY,
    company_name VARCHAR(255) NOT NULL,
    subdomain    VARCHAR(100) UNIQUE NOT NULL,          -- e.g. 'acme' → acme.cortex.app
    plan         VARCHAR(50)  NOT NULL DEFAULT 'Starter', -- 'Starter', 'Pro', 'Enterprise'
    is_active    BOOLEAN NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT chk_subdomain CHECK (subdomain ~ '^[a-z0-9\-]+$')
);

-- ─── core.roles ──────────────────────────────────────────────────────────────────────
-- tenant_id = NULL  → global Synaptia-managed role (visible to all tenants, read-only)
-- tenant_id = X     → role created by and for tenant X
CREATE TABLE IF NOT EXISTS core.roles (
    role_id     SERIAL PRIMARY KEY,
    role_name   VARCHAR(100) NOT NULL,
    description TEXT,
    tenant_id   BIGINT REFERENCES core.tenants(tenant_id) ON DELETE CASCADE,
    UNIQUE (role_name, tenant_id)
);

-- ─── core.permissions ────────────────────────────────────────────────────────────────
-- Platform-wide permission definitions (no tenant scoping — these are global labels)
CREATE TABLE IF NOT EXISTS core.permissions (
    permission_id   SERIAL PRIMARY KEY,
    permission_name VARCHAR(100) UNIQUE NOT NULL  -- e.g. 'wo_create', 'asset_edit'
);

-- ─── core.role_permissions ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS core.role_permissions (
    role_id       INT NOT NULL REFERENCES core.roles(role_id) ON DELETE CASCADE,
    permission_id INT NOT NULL REFERENCES core.permissions(permission_id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

-- ─── core.users ──────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS core.users (
    user_id       BIGSERIAL PRIMARY KEY,
    tenant_id     BIGINT NOT NULL REFERENCES core.tenants(tenant_id) ON DELETE CASCADE,
    username      VARCHAR(100) NOT NULL,
    email         VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name    VARCHAR(100),
    last_name     VARCHAR(100),
    role_id       INT NOT NULL REFERENCES core.roles(role_id),
    is_active     BOOLEAN DEFAULT TRUE,
    last_login    TIMESTAMP WITH TIME ZONE,
    created_at    TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE (tenant_id, username),
    UNIQUE (tenant_id, email)
);

-- ─── core.locations ──────────────────────────────────────────────────────────────────
-- Hierarchical (Sites → Buildings → Zones), fully tenant-scoped
CREATE TABLE IF NOT EXISTS core.locations (
    location_id        SERIAL PRIMARY KEY,
    tenant_id          BIGINT NOT NULL REFERENCES core.tenants(tenant_id) ON DELETE CASCADE,
    name               VARCHAR(255) NOT NULL,
    address            TEXT,
    parent_location_id INT REFERENCES core.locations(location_id),
    latitude           NUMERIC(10, 8),
    longitude          NUMERIC(11, 8)
);

-- ####################################################################################
-- STEP 3: ASSETS MODULE
-- ####################################################################################

-- ─── assets.types ────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS assets.types (
    asset_type_id SERIAL PRIMARY KEY,
    tenant_id     BIGINT NOT NULL REFERENCES core.tenants(tenant_id) ON DELETE CASCADE,
    name          VARCHAR(100) NOT NULL,
    description   TEXT,
    UNIQUE (tenant_id, name)
);

-- ─── assets.registry ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS assets.registry (
    asset_id      BIGSERIAL PRIMARY KEY,
    tenant_id     BIGINT NOT NULL REFERENCES core.tenants(tenant_id) ON DELETE CASCADE,
    name          VARCHAR(255) NOT NULL,
    tag_number    VARCHAR(100) NOT NULL,
    serial_number VARCHAR(100),
    asset_type_id INT NOT NULL REFERENCES assets.types(asset_type_id),
    location_id   INT NOT NULL REFERENCES core.locations(location_id),
    status        VARCHAR(50) NOT NULL DEFAULT 'Operational', -- 'Operational', 'Down', 'Maintenance'
    criticality   VARCHAR(50) DEFAULT 'Medium',               -- 'High', 'Medium', 'Low'
    manufacturer  VARCHAR(100),
    model         VARCHAR(100),
    install_date  DATE,
    purchase_cost NUMERIC(15, 2) DEFAULT 0,
    last_meter_reading NUMERIC(15, 2),
    custom_fields JSONB,
    UNIQUE (tenant_id, tag_number)
);

-- ─── assets.readings ─────────────────────────────────────────────────────────────────
-- IoT sensor readings and manual meter inputs
CREATE TABLE IF NOT EXISTS assets.readings (
    reading_id   BIGSERIAL PRIMARY KEY,
    tenant_id    BIGINT NOT NULL REFERENCES core.tenants(tenant_id) ON DELETE CASCADE,
    asset_id     BIGINT NOT NULL REFERENCES assets.registry(asset_id) ON DELETE CASCADE,
    reading_type VARCHAR(100) NOT NULL, -- 'Runtime', 'Temperature', 'Vibration'
    value        NUMERIC(15, 2) NOT NULL,
    unit         VARCHAR(50),
    timestamp    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    source       VARCHAR(50) DEFAULT 'Manual' -- 'Manual', 'IoT', 'System'
);

-- ─── assets.downtime_events ──────────────────────────────────────────────────────────
-- All asset downtime periods — the source of truth for KPI calculation
CREATE TABLE IF NOT EXISTS assets.downtime_events (
    event_id   BIGSERIAL PRIMARY KEY,
    tenant_id  BIGINT NOT NULL REFERENCES core.tenants(tenant_id) ON DELETE CASCADE,
    asset_id   BIGINT NOT NULL REFERENCES assets.registry(asset_id) ON DELETE CASCADE,
    started_at TIMESTAMP WITH TIME ZONE NOT NULL,
    ended_at   TIMESTAMP WITH TIME ZONE,
    reason     VARCHAR(100) NOT NULL, -- 'Breakdown', 'PM', 'Changeover', 'Setup'
    failure_code VARCHAR(100),
    wo_id      BIGINT,                -- FK to maintenance.work_orders added later
    notes      TEXT,
    created_by BIGINT REFERENCES core.users(user_id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ####################################################################################
-- STEP 4: CATALOG MODULE
-- ####################################################################################

-- ─── catalog.maintenance_tasks ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS catalog.maintenance_tasks (
    task_id              SERIAL PRIMARY KEY,
    tenant_id            BIGINT NOT NULL REFERENCES core.tenants(tenant_id) ON DELETE CASCADE,
    name                 VARCHAR(255) NOT NULL,
    description          TEXT,
    estimated_duration_min NUMERIC(6, 2),
    standard_labor_hrs   NUMERIC(6, 2)
);

-- ─── catalog.checklists ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS catalog.checklists (
    checklist_id  SERIAL PRIMARY KEY,
    tenant_id     BIGINT NOT NULL REFERENCES core.tenants(tenant_id) ON DELETE CASCADE,
    name          VARCHAR(255) NOT NULL,
    description   TEXT,
    asset_type_id INT REFERENCES assets.types(asset_type_id)
);

-- ─── catalog.checklist_items ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS catalog.checklist_items (
    item_id         BIGSERIAL PRIMARY KEY,
    tenant_id       BIGINT NOT NULL REFERENCES core.tenants(tenant_id) ON DELETE CASCADE,
    checklist_id    INT NOT NULL REFERENCES catalog.checklists(checklist_id) ON DELETE CASCADE,
    description     TEXT NOT NULL,
    item_type       VARCHAR(50) NOT NULL, -- 'text', 'yes/no', 'number', 'photo'
    sequence_number INT NOT NULL
);

-- ####################################################################################
-- STEP 5: INVENTORY MODULE
-- ####################################################################################

-- ─── inventory.suppliers ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS inventory.suppliers (
    supplier_id    SERIAL PRIMARY KEY,
    tenant_id      BIGINT NOT NULL REFERENCES core.tenants(tenant_id) ON DELETE CASCADE,
    name           VARCHAR(255) NOT NULL,
    contact_person VARCHAR(255),
    phone          VARCHAR(50),
    email          VARCHAR(255),
    address        TEXT
);

-- ─── inventory.parts ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS inventory.parts (
    part_id     BIGSERIAL PRIMARY KEY,
    tenant_id   BIGINT NOT NULL REFERENCES core.tenants(tenant_id) ON DELETE CASCADE,
    name        VARCHAR(255) NOT NULL,
    sku         VARCHAR(100) NOT NULL,
    description TEXT,
    unit_cost   NUMERIC(10, 4) DEFAULT 0,
    uom         VARCHAR(50),              -- 'Each', 'Box', 'Meter'
    supplier_id INT REFERENCES inventory.suppliers(supplier_id),
    UNIQUE (tenant_id, sku)
);

-- ─── inventory.storerooms ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS inventory.storerooms (
    storeroom_id SERIAL PRIMARY KEY,
    tenant_id    BIGINT NOT NULL REFERENCES core.tenants(tenant_id) ON DELETE CASCADE,
    name         VARCHAR(255) NOT NULL,
    location_id  INT REFERENCES core.locations(location_id),
    is_active    BOOLEAN DEFAULT TRUE
);

-- ─── inventory.stock ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS inventory.stock (
    stock_id         BIGSERIAL PRIMARY KEY,
    tenant_id        BIGINT NOT NULL REFERENCES core.tenants(tenant_id) ON DELETE CASCADE,
    part_id          BIGINT NOT NULL REFERENCES inventory.parts(part_id) ON DELETE RESTRICT,
    storeroom_id     INT NOT NULL REFERENCES inventory.storerooms(storeroom_id) ON DELETE RESTRICT,
    quantity_on_hand NUMERIC(10, 2) NOT NULL DEFAULT 0,
    reorder_point    NUMERIC(10, 2) DEFAULT 5,
    max_stock_level  NUMERIC(10, 2),
    average_unit_cost NUMERIC(10, 4),
    last_stock_update TIMESTAMP WITH TIME ZONE,
    UNIQUE (tenant_id, part_id, storeroom_id)
);

-- ─── inventory.transactions ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS inventory.transactions (
    transaction_id    BIGSERIAL PRIMARY KEY,
    tenant_id         BIGINT NOT NULL REFERENCES core.tenants(tenant_id) ON DELETE CASCADE,
    stock_id          BIGINT NOT NULL REFERENCES inventory.stock(stock_id) ON DELETE RESTRICT,
    transaction_type  VARCHAR(50) NOT NULL, -- 'Issue', 'Receive', 'Transfer', 'Adjustment'
    quantity_change   NUMERIC(10, 2) NOT NULL,
    unit_cost_at_time NUMERIC(10, 4),
    user_id           BIGINT REFERENCES core.users(user_id),
    related_wo_id     BIGINT,              -- FK added after work_orders
    timestamp         TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- ####################################################################################
-- STEP 6: MAINTENANCE MODULE
-- ####################################################################################

-- ─── maintenance.preventive_schedule ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS maintenance.preventive_schedule (
    pm_id          BIGSERIAL PRIMARY KEY,
    tenant_id      BIGINT NOT NULL REFERENCES core.tenants(tenant_id) ON DELETE CASCADE,
    name           VARCHAR(255) NOT NULL,
    description    TEXT,
    asset_id       BIGINT REFERENCES assets.registry(asset_id) ON DELETE CASCADE,
    schedule_type  VARCHAR(50) NOT NULL,          -- 'Time-based', 'Meter-based'
    interval_value NUMERIC(10, 2) NOT NULL,
    interval_unit  VARCHAR(50) NOT NULL,          -- 'Days', 'Weeks', 'Hours', 'Cycles'
    next_due_date  DATE,
    next_due_meter NUMERIC(15, 2),
    is_active      BOOLEAN DEFAULT TRUE
);

-- ─── maintenance.work_orders ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS maintenance.work_orders (
    wo_id           BIGSERIAL PRIMARY KEY,
    tenant_id       BIGINT NOT NULL REFERENCES core.tenants(tenant_id) ON DELETE CASCADE,
    title           VARCHAR(255) NOT NULL,
    description     TEXT,
    type            VARCHAR(50) NOT NULL,          -- 'PM', 'Corrective', 'Inspection'
    asset_id        BIGINT REFERENCES assets.registry(asset_id) ON DELETE RESTRICT,
    location_id     INT REFERENCES core.locations(location_id) ON DELETE RESTRICT,
    reported_by_id  BIGINT REFERENCES core.users(user_id) ON DELETE RESTRICT,
    assigned_to_id  BIGINT REFERENCES core.users(user_id),
    pm_id           BIGINT REFERENCES maintenance.preventive_schedule(pm_id) ON DELETE SET NULL,
    priority        VARCHAR(50) NOT NULL DEFAULT 'Medium', -- 'Low', 'Medium', 'High', 'Urgent'
    status          VARCHAR(50) NOT NULL DEFAULT 'Open',   -- 'Draft', 'Open', 'In Progress', 'Complete', 'On Hold'
    requested_date  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    due_date        TIMESTAMP WITH TIME ZONE,
    start_time      TIMESTAMP WITH TIME ZONE,
    completion_time TIMESTAMP WITH TIME ZONE,
    labor_cost      NUMERIC(15, 2) DEFAULT 0.00,
    material_cost   NUMERIC(15, 2) DEFAULT 0.00,
    total_cost      NUMERIC(15, 2) GENERATED ALWAYS AS (labor_cost + material_cost) STORED
);

-- Deferred FKs now that work_orders exists (idempotent guards)
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints
                   WHERE constraint_name = 'fk_transactions_wo') THEN
        ALTER TABLE inventory.transactions
            ADD CONSTRAINT fk_transactions_wo
            FOREIGN KEY (related_wo_id) REFERENCES maintenance.work_orders(wo_id);
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.table_constraints
                   WHERE constraint_name = 'fk_downtime_wo') THEN
        ALTER TABLE assets.downtime_events
            ADD CONSTRAINT fk_downtime_wo
            FOREIGN KEY (wo_id) REFERENCES maintenance.work_orders(wo_id);
    END IF;
END $$;

-- ─── maintenance.wo_tasks ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS maintenance.wo_tasks (
    wo_task_id       BIGSERIAL PRIMARY KEY,
    tenant_id        BIGINT NOT NULL REFERENCES core.tenants(tenant_id) ON DELETE CASCADE,
    wo_id            BIGINT NOT NULL REFERENCES maintenance.work_orders(wo_id) ON DELETE CASCADE,
    task_id          INT NOT NULL REFERENCES catalog.maintenance_tasks(task_id) ON DELETE RESTRICT,
    sequence_number  INT NOT NULL,
    is_complete      BOOLEAN DEFAULT FALSE,
    actual_time_spent NUMERIC(6, 2),
    UNIQUE (wo_id, task_id)
);

-- ─── maintenance.wo_checklist_answers ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS maintenance.wo_checklist_answers (
    answer_id    BIGSERIAL PRIMARY KEY,
    tenant_id    BIGINT NOT NULL REFERENCES core.tenants(tenant_id) ON DELETE CASCADE,
    wo_id        BIGINT NOT NULL REFERENCES maintenance.work_orders(wo_id) ON DELETE CASCADE,
    item_id      BIGINT NOT NULL REFERENCES catalog.checklist_items(item_id) ON DELETE RESTRICT,
    user_id      BIGINT REFERENCES core.users(user_id) ON DELETE RESTRICT,
    answer_value TEXT,
    timestamp    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    UNIQUE (wo_id, item_id)
);

-- ─── maintenance.part_usage ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS maintenance.part_usage (
    usage_id          BIGSERIAL PRIMARY KEY,
    tenant_id         BIGINT NOT NULL REFERENCES core.tenants(tenant_id) ON DELETE CASCADE,
    wo_id             BIGINT NOT NULL REFERENCES maintenance.work_orders(wo_id) ON DELETE CASCADE,
    part_id           BIGINT NOT NULL REFERENCES inventory.parts(part_id) ON DELETE RESTRICT,
    storeroom_id      INT NOT NULL REFERENCES inventory.storerooms(storeroom_id) ON DELETE RESTRICT,
    quantity_used     NUMERIC(10, 2) NOT NULL,
    unit_cost_at_time NUMERIC(10, 4) NOT NULL,
    user_id           BIGINT REFERENCES core.users(user_id) ON DELETE RESTRICT,
    timestamp         TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- ####################################################################################
-- STEP 7: ANALYTICS MODULE
-- ####################################################################################

-- ─── analytics.notifications ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS analytics.notifications (
    notification_id     BIGSERIAL PRIMARY KEY,
    tenant_id           BIGINT NOT NULL REFERENCES core.tenants(tenant_id) ON DELETE CASCADE,
    user_id             BIGINT NOT NULL REFERENCES core.users(user_id) ON DELETE CASCADE,
    related_entity_type VARCHAR(50), -- 'WO', 'Asset', 'PM'
    related_entity_id   BIGINT,
    message             TEXT NOT NULL,
    type                VARCHAR(50),
    is_read             BOOLEAN DEFAULT FALSE,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- ─── analytics.reports ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS analytics.reports (
    report_id       SERIAL PRIMARY KEY,
    tenant_id       BIGINT NOT NULL REFERENCES core.tenants(tenant_id) ON DELETE CASCADE,
    name            VARCHAR(255) NOT NULL,
    definition      JSONB,
    created_by_id   BIGINT REFERENCES core.users(user_id) ON DELETE RESTRICT,
    last_generated  TIMESTAMP WITH TIME ZONE
);

-- ─── analytics.audit_logs ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS analytics.audit_logs (
    log_id         BIGSERIAL PRIMARY KEY,
    tenant_id      BIGINT NOT NULL REFERENCES core.tenants(tenant_id) ON DELETE CASCADE,
    user_id        BIGINT REFERENCES core.users(user_id),
    table_name     VARCHAR(100) NOT NULL,
    record_id      BIGINT NOT NULL,
    action_type    VARCHAR(10) NOT NULL, -- 'INSERT', 'UPDATE', 'DELETE'
    change_details JSONB,
    timestamp      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- ####################################################################################
-- STEP 8: INDEXES (Multi-tenant composite — tenant_id always first)
-- ####################################################################################

-- core
CREATE INDEX IF NOT EXISTS idx_users_tenant           ON core.users(tenant_id);
-- NOTE: idx_users_tenant_email removed — UNIQUE(tenant_id, email) in table DDL already creates this index
CREATE INDEX IF NOT EXISTS idx_users_tenant_role      ON core.users(tenant_id, role_id);
CREATE INDEX IF NOT EXISTS idx_roles_tenant           ON core.roles(tenant_id);
CREATE INDEX IF NOT EXISTS idx_locations_tenant       ON core.locations(tenant_id);

-- assets
-- NOTE: idx_asset_tenant_tag removed — UNIQUE(tenant_id, tag_number) in table DDL already creates this index
CREATE INDEX IF NOT EXISTS idx_asset_tenant_status        ON assets.registry(tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_asset_tenant_location      ON assets.registry(tenant_id, location_id);
CREATE INDEX IF NOT EXISTS idx_asset_tenant_type          ON assets.registry(tenant_id, asset_type_id);
CREATE INDEX IF NOT EXISTS idx_asset_tenant_custom_gin    ON assets.registry USING GIN (custom_fields);
CREATE INDEX IF NOT EXISTS idx_readings_tenant_time       ON assets.readings(tenant_id, asset_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_downtime_tenant_asset      ON assets.downtime_events(tenant_id, asset_id);
CREATE INDEX IF NOT EXISTS idx_downtime_tenant_dates      ON assets.downtime_events(tenant_id, started_at, ended_at);
CREATE INDEX IF NOT EXISTS idx_downtime_tenant_reason     ON assets.downtime_events(tenant_id, reason);

-- catalog
CREATE INDEX IF NOT EXISTS idx_tasks_tenant               ON catalog.maintenance_tasks(tenant_id);
CREATE INDEX IF NOT EXISTS idx_checklists_tenant          ON catalog.checklists(tenant_id);
CREATE INDEX IF NOT EXISTS idx_checklist_items_tenant     ON catalog.checklist_items(tenant_id);

-- inventory
-- NOTE: idx_parts_tenant_sku removed — UNIQUE(tenant_id, sku) in table DDL already creates this index
CREATE INDEX IF NOT EXISTS idx_stock_tenant_part          ON inventory.stock(tenant_id, part_id);
CREATE INDEX IF NOT EXISTS idx_stock_tenant_storeroom     ON inventory.stock(tenant_id, storeroom_id);
CREATE INDEX IF NOT EXISTS idx_trans_tenant_stock         ON inventory.transactions(tenant_id, stock_id);
CREATE INDEX IF NOT EXISTS idx_trans_tenant_time          ON inventory.transactions(tenant_id, timestamp DESC);

-- maintenance
CREATE INDEX IF NOT EXISTS idx_pm_tenant                  ON maintenance.preventive_schedule(tenant_id);
CREATE INDEX IF NOT EXISTS idx_pm_tenant_due              ON maintenance.preventive_schedule(tenant_id, next_due_date);
CREATE INDEX IF NOT EXISTS idx_wo_tenant_status           ON maintenance.work_orders(tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_wo_tenant_priority         ON maintenance.work_orders(tenant_id, priority);
CREATE INDEX IF NOT EXISTS idx_wo_tenant_asset            ON maintenance.work_orders(tenant_id, asset_id);
CREATE INDEX IF NOT EXISTS idx_wo_tenant_assigned         ON maintenance.work_orders(tenant_id, assigned_to_id);
CREATE INDEX IF NOT EXISTS idx_wo_tenant_due_date         ON maintenance.work_orders(tenant_id, due_date);
CREATE INDEX IF NOT EXISTS idx_wo_tenant_pm               ON maintenance.work_orders(tenant_id, pm_id);
CREATE INDEX IF NOT EXISTS idx_part_usage_tenant_wo       ON maintenance.part_usage(tenant_id, wo_id);

-- analytics
CREATE INDEX IF NOT EXISTS idx_notif_tenant_user          ON analytics.notifications(tenant_id, user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_audit_tenant_table         ON analytics.audit_logs(tenant_id, table_name, record_id);
CREATE INDEX IF NOT EXISTS idx_audit_tenant_time          ON analytics.audit_logs(tenant_id, timestamp DESC);

-- ####################################################################################
-- STEP 9: ANALYTICS VIEWS (Ficha Maestra + KPI + Backlog)
-- NOTE: Views query all tenants; RLS on the underlying tables enforces isolation.
-- ####################################################################################

-- ─── Session helper ──────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION core.current_tenant_id()
RETURNS BIGINT LANGUAGE sql STABLE
SET search_path = core, public
AS $$
    SELECT NULLIF(current_setting('app.current_tenant', TRUE), '')::BIGINT;
$$;

-- ─── v_asset_360 : The "Ficha Maestra" ───────────────────────────────────────────────
CREATE OR REPLACE VIEW analytics.v_asset_360 AS
SELECT
    a.asset_id,
    a.tenant_id,
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
    a.purchase_cost,
    COALESCE(wo_stats.total_maintenance_cost, 0) AS total_maintenance_cost,
    (COALESCE(a.purchase_cost, 0) + COALESCE(wo_stats.total_maintenance_cost, 0)) AS total_lifecycle_cost,
    COALESCE(wo_stats.total_work_orders, 0) AS total_work_orders,
    COALESCE(wo_stats.open_work_orders, 0) AS open_work_orders,
    COALESCE(wo_stats.completed_work_orders, 0) AS completed_work_orders,
    wo_stats.last_wo_date,
    pm.next_pm_date,
    pm.active_pm_count,
    CASE
        WHEN a.status = 'Down' THEN 'CRITICAL'
        WHEN pm.next_pm_date < CURRENT_DATE THEN 'OVERDUE'
        WHEN wo_stats.open_work_orders > 3 THEN 'AT_RISK'
        WHEN wo_stats.open_work_orders > 0 THEN 'ATTENTION'
        ELSE 'HEALTHY'
    END AS health_score,
    lr.reading_type AS last_reading_type,
    lr.value AS last_reading_value,
    lr.unit AS last_reading_unit,
    lr.timestamp AS last_reading_time,
    a.custom_fields
FROM assets.registry a
    JOIN assets.types t ON a.asset_type_id = t.asset_type_id
    JOIN core.locations l ON a.location_id = l.location_id
    LEFT JOIN (
        SELECT asset_id,
            COUNT(*) AS total_work_orders,
            COUNT(*) FILTER (WHERE status NOT IN ('Complete','Cancelled')) AS open_work_orders,
            COUNT(*) FILTER (WHERE status = 'Complete') AS completed_work_orders,
            SUM(total_cost) AS total_maintenance_cost,
            MAX(completion_time) AS last_wo_date
        FROM maintenance.work_orders GROUP BY asset_id
    ) wo_stats ON a.asset_id = wo_stats.asset_id
    LEFT JOIN (
        SELECT asset_id,
            MIN(next_due_date) AS next_pm_date,
            COUNT(*) FILTER (WHERE is_active = TRUE) AS active_pm_count
        FROM maintenance.preventive_schedule GROUP BY asset_id
    ) pm ON a.asset_id = pm.asset_id
    LEFT JOIN LATERAL (
        SELECT reading_type, value, unit, timestamp
        FROM assets.readings r
        WHERE r.asset_id = a.asset_id ORDER BY timestamp DESC LIMIT 1
    ) lr ON TRUE;

-- ─── v_downtime_events ───────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW analytics.v_downtime_events AS
SELECT
    event_id, tenant_id, asset_id, started_at, ended_at,
    ROUND(EXTRACT(EPOCH FROM (COALESCE(ended_at, NOW()) - started_at)) / 3600, 2) AS duration_hours,
    reason, failure_code, wo_id, notes, created_by, created_at
FROM assets.downtime_events;

-- ─── v_asset_failures ────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW analytics.v_asset_failures AS
SELECT asset_id, tenant_id, event_id,
    started_at AS failure_start, ended_at AS failure_end,
    duration_hours AS repair_time_hours, failure_code, wo_id
FROM analytics.v_downtime_events
WHERE reason = 'Breakdown' AND ended_at IS NOT NULL;

-- ─── KPI Views ───────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW analytics.v_asset_mttr AS
SELECT a.asset_id, a.tenant_id, a.name AS asset_name, a.tag_number, t.name AS asset_type,
    COUNT(f.event_id) AS failure_count,
    COALESCE(SUM(f.repair_time_hours), 0) AS total_repair_hours,
    CASE WHEN COUNT(f.event_id) > 0
        THEN ROUND(SUM(f.repair_time_hours) / COUNT(f.event_id), 2)
        ELSE 0 END AS mttr_hours
FROM assets.registry a
    JOIN assets.types t ON a.asset_type_id = t.asset_type_id
    LEFT JOIN analytics.v_asset_failures f ON a.asset_id = f.asset_id
GROUP BY a.asset_id, a.tenant_id, a.name, a.tag_number, t.name;

CREATE OR REPLACE VIEW analytics.v_asset_mtbf AS
WITH tl AS (
    SELECT a.asset_id, a.tenant_id, a.name AS asset_name, a.tag_number,
        t.name AS asset_type, a.install_date,
        EXTRACT(EPOCH FROM (NOW() - a.install_date::timestamp)) / 3600 AS total_hours,
        COALESCE(SUM(d.duration_hours), 0) AS total_downtime_hours,
        COUNT(d.event_id) FILTER (WHERE d.reason = 'Breakdown') AS failure_count
    FROM assets.registry a
        JOIN assets.types t ON a.asset_type_id = t.asset_type_id
        LEFT JOIN analytics.v_downtime_events d ON a.asset_id = d.asset_id
    WHERE a.install_date IS NOT NULL
    GROUP BY a.asset_id, a.tenant_id, a.name, a.tag_number, t.name, a.install_date
)
SELECT asset_id, tenant_id, asset_name, tag_number, asset_type, install_date,
    ROUND(total_hours, 2) AS total_hours,
    ROUND(total_downtime_hours, 2) AS downtime_hours,
    ROUND(total_hours - total_downtime_hours, 2) AS operating_hours,
    failure_count,
    CASE WHEN failure_count > 0
        THEN ROUND((total_hours - total_downtime_hours) / failure_count, 2)
        ELSE NULL END AS mtbf_hours
FROM tl;

CREATE OR REPLACE VIEW analytics.v_asset_availability AS
WITH ac AS (
    SELECT a.asset_id, a.tenant_id, a.name AS asset_name, a.tag_number,
        t.name AS asset_type, a.install_date,
        EXTRACT(EPOCH FROM (NOW() - a.install_date::timestamp)) / 3600 AS total_hours,
        COALESCE(SUM(d.duration_hours), 0) AS downtime_hours
    FROM assets.registry a
        JOIN assets.types t ON a.asset_type_id = t.asset_type_id
        LEFT JOIN analytics.v_downtime_events d ON a.asset_id = d.asset_id
    WHERE a.install_date IS NOT NULL
    GROUP BY a.asset_id, a.tenant_id, a.name, a.tag_number, t.name, a.install_date
)
SELECT asset_id, tenant_id, asset_name, tag_number, asset_type,
    ROUND(total_hours, 2) AS total_hours,
    ROUND(downtime_hours, 2) AS downtime_hours,
    ROUND(total_hours - downtime_hours, 2) AS uptime_hours,
    CASE WHEN total_hours > 0
        THEN ROUND(((total_hours - downtime_hours) / total_hours) * 100, 2)
        ELSE 100.00 END AS availability_percent
FROM ac;

CREATE OR REPLACE VIEW analytics.v_asset_reliability AS
SELECT asset_id, tenant_id, asset_name, tag_number, asset_type, mtbf_hours,
    CASE WHEN mtbf_hours IS NOT NULL AND mtbf_hours > 0
        THEN ROUND(EXP(-720.0  / mtbf_hours) * 100, 2) ELSE 100.00 END AS reliability_30day_percent,
    CASE WHEN mtbf_hours IS NOT NULL AND mtbf_hours > 0
        THEN ROUND(EXP(-168.0  / mtbf_hours) * 100, 2) ELSE 100.00 END AS reliability_7day_percent
FROM analytics.v_asset_mtbf;

CREATE OR REPLACE VIEW analytics.v_kpi_dashboard AS
SELECT a.asset_id, a.tenant_id, a.asset_name, a.tag_number, a.asset_type,
    a.availability_percent, r.reliability_30day_percent, r.reliability_7day_percent,
    m.mttr_hours, b.mtbf_hours, m.failure_count,
    CASE
        WHEN a.availability_percent < 80 THEN 'CRITICAL'
        WHEN a.availability_percent < 90 THEN 'WARNING'
        WHEN r.reliability_30day_percent < 70 THEN 'AT_RISK'
        ELSE 'HEALTHY'
    END AS kpi_health_status
FROM analytics.v_asset_availability a
    LEFT JOIN analytics.v_asset_reliability r ON a.asset_id = r.asset_id
    LEFT JOIN analytics.v_asset_mttr m ON a.asset_id = m.asset_id
    LEFT JOIN analytics.v_asset_mtbf b ON a.asset_id = b.asset_id;

-- ─── Backlog Views ────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW analytics.v_wo_backlog AS
SELECT
    wo.wo_id, wo.tenant_id, wo.title, wo.description, wo.type, wo.priority,
    wo.status, wo.requested_date, wo.due_date, wo.start_time,
    a.name AS asset_name, a.tag_number, a.criticality AS asset_criticality,
    l.name AS location_name,
    TRIM(CONCAT(req.first_name, ' ', req.last_name)) AS requested_by,
    TRIM(CONCAT(asn.first_name, ' ', asn.last_name)) AS assigned_to,
    ROUND(EXTRACT(EPOCH FROM (NOW() - wo.requested_date)) / 86400, 1) AS age_days,
    CASE WHEN wo.due_date IS NOT NULL AND wo.due_date < NOW()
        THEN ROUND(EXTRACT(EPOCH FROM (NOW() - wo.due_date)) / 86400, 1) ELSE 0 END AS overdue_days,
    CASE WHEN wo.due_date IS NOT NULL AND wo.due_date < NOW() THEN TRUE ELSE FALSE END AS is_overdue,
    CASE
        WHEN wo.priority = 'Urgent' THEN 1
        WHEN wo.due_date IS NOT NULL AND wo.due_date < NOW() THEN 2
        WHEN wo.priority = 'High' THEN 3
        WHEN wo.priority = 'Medium' THEN 4
        ELSE 5
    END AS urgency_rank,
    CASE
        WHEN wo.priority = 'Urgent' THEN 'CRITICAL'
        WHEN wo.due_date IS NOT NULL AND wo.due_date < NOW() AND wo.priority IN ('High','Urgent') THEN 'CRITICAL'
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
WHERE wo.status NOT IN ('Complete','Cancelled')
ORDER BY urgency_rank ASC, wo.requested_date ASC;

CREATE OR REPLACE VIEW analytics.v_pm_backlog AS
SELECT
    pm.pm_id, pm.tenant_id, pm.name AS pm_name, pm.schedule_type,
    pm.interval_value, pm.interval_unit, pm.next_due_date, pm.next_due_meter,
    a.asset_id, a.name AS asset_name, a.tag_number, a.criticality AS asset_criticality,
    CASE WHEN pm.next_due_date IS NOT NULL AND pm.next_due_date < CURRENT_DATE
        THEN (CURRENT_DATE - pm.next_due_date) ELSE 0 END AS overdue_days,
    CASE
        WHEN pm.next_due_date IS NULL THEN 'UNSCHEDULED'
        WHEN pm.next_due_date < CURRENT_DATE - INTERVAL '30 days' THEN 'CRITICAL_OVERDUE'
        WHEN pm.next_due_date < CURRENT_DATE - INTERVAL '7 days'  THEN 'OVERDUE'
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

CREATE OR REPLACE VIEW analytics.v_backlog_summary AS
SELECT
    (SELECT COUNT(*) FROM maintenance.work_orders
     WHERE tenant_id = core.current_tenant_id() AND status NOT IN ('Complete','Cancelled')) AS total_open_wo,
    (SELECT COUNT(*) FROM maintenance.work_orders
     WHERE tenant_id = core.current_tenant_id() AND status NOT IN ('Complete','Cancelled')
       AND due_date IS NOT NULL AND due_date < NOW()) AS overdue_wo,
    (SELECT COUNT(*) FROM maintenance.work_orders
     WHERE tenant_id = core.current_tenant_id() AND status = 'Open') AS unstarted_wo,
    (SELECT COUNT(*) FROM maintenance.work_orders
     WHERE tenant_id = core.current_tenant_id() AND status = 'In Progress') AS in_progress_wo,
    (SELECT COUNT(*) FROM maintenance.work_orders
     WHERE tenant_id = core.current_tenant_id() AND status = 'On Hold') AS on_hold_wo,
    (SELECT COUNT(*) FROM maintenance.preventive_schedule
     WHERE tenant_id = core.current_tenant_id() AND is_active = TRUE
       AND next_due_date IS NOT NULL AND next_due_date < CURRENT_DATE) AS overdue_pm,
    (SELECT COUNT(*) FROM maintenance.preventive_schedule
     WHERE tenant_id = core.current_tenant_id() AND is_active = TRUE
       AND next_due_date IS NULL) AS unscheduled_pm,
    (SELECT COUNT(*) FROM maintenance.preventive_schedule
     WHERE tenant_id = core.current_tenant_id() AND is_active = TRUE
       AND next_due_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '7 days') AS pm_due_this_week,
    (SELECT ROUND(AVG(EXTRACT(EPOCH FROM (NOW() - requested_date)) / 86400), 1)
     FROM maintenance.work_orders
     WHERE tenant_id = core.current_tenant_id()
       AND status NOT IN ('Complete','Cancelled')) AS avg_wo_age_days;

CREATE OR REPLACE VIEW analytics.v_backlog_by_priority AS
SELECT wo.priority,
    COUNT(*) AS total_count,
    COUNT(*) FILTER (WHERE wo.due_date IS NOT NULL AND wo.due_date < NOW()) AS overdue_count,
    COUNT(*) FILTER (WHERE wo.status = 'Open') AS open_count,
    COUNT(*) FILTER (WHERE wo.status = 'In Progress') AS in_progress_count,
    ROUND(AVG(EXTRACT(EPOCH FROM (NOW() - wo.requested_date)) / 86400), 1) AS avg_age_days
FROM maintenance.work_orders wo
WHERE wo.status NOT IN ('Complete','Cancelled')
GROUP BY wo.priority
ORDER BY CASE wo.priority WHEN 'Urgent' THEN 1 WHEN 'High' THEN 2 WHEN 'Medium' THEN 3 ELSE 4 END;

CREATE OR REPLACE VIEW analytics.v_backlog_by_asset AS
SELECT
    a.asset_id, a.tenant_id, a.name AS asset_name, a.tag_number, a.criticality,
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
        AND wo.status NOT IN ('Complete','Cancelled')
GROUP BY a.asset_id, a.tenant_id, a.name, a.tag_number, a.criticality
HAVING COUNT(wo.wo_id) > 0
    OR (SELECT COUNT(*) FROM maintenance.preventive_schedule pm
        WHERE pm.asset_id = a.asset_id AND pm.is_active = TRUE
          AND pm.next_due_date IS NOT NULL AND pm.next_due_date < CURRENT_DATE) > 0
ORDER BY total_backlog DESC;

CREATE OR REPLACE VIEW analytics.v_backlog_aging AS
SELECT bucket, bucket_order, COUNT(*) AS wo_count,
    SUM(CASE WHEN priority = 'Urgent' THEN 1 ELSE 0 END) AS urgent_count,
    SUM(CASE WHEN priority = 'High'   THEN 1 ELSE 0 END) AS high_count
FROM (
    SELECT wo.priority,
        CASE
            WHEN EXTRACT(EPOCH FROM (NOW()-wo.requested_date))/86400 <= 1  THEN 'Today'
            WHEN EXTRACT(EPOCH FROM (NOW()-wo.requested_date))/86400 <= 3  THEN '1-3 Days'
            WHEN EXTRACT(EPOCH FROM (NOW()-wo.requested_date))/86400 <= 7  THEN '4-7 Days'
            WHEN EXTRACT(EPOCH FROM (NOW()-wo.requested_date))/86400 <= 14 THEN '1-2 Weeks'
            WHEN EXTRACT(EPOCH FROM (NOW()-wo.requested_date))/86400 <= 30 THEN '2-4 Weeks'
            ELSE '30+ Days'
        END AS bucket,
        CASE
            WHEN EXTRACT(EPOCH FROM (NOW()-wo.requested_date))/86400 <= 1  THEN 1
            WHEN EXTRACT(EPOCH FROM (NOW()-wo.requested_date))/86400 <= 3  THEN 2
            WHEN EXTRACT(EPOCH FROM (NOW()-wo.requested_date))/86400 <= 7  THEN 3
            WHEN EXTRACT(EPOCH FROM (NOW()-wo.requested_date))/86400 <= 14 THEN 4
            WHEN EXTRACT(EPOCH FROM (NOW()-wo.requested_date))/86400 <= 30 THEN 5
            ELSE 6
        END AS bucket_order
    FROM maintenance.work_orders wo
    WHERE wo.status NOT IN ('Complete','Cancelled')
) aged
GROUP BY bucket, bucket_order
ORDER BY bucket_order;

-- ─── KPI & Backlog Functions ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION analytics.get_asset_kpis(
    p_asset_id   BIGINT,
    p_start_date DATE DEFAULT NULL,
    p_end_date   DATE DEFAULT NULL
)
RETURNS TABLE (
    asset_id            BIGINT, asset_name VARCHAR,
    availability_percent NUMERIC, mttr_hours NUMERIC,
    mtbf_hours NUMERIC, failure_count BIGINT,
    period_start DATE, period_end DATE
) AS $$
BEGIN
    RETURN QUERY
    WITH pd AS (
        SELECT d.asset_id,
            COUNT(d.event_id) FILTER (WHERE d.reason='Breakdown') AS failures,
            COALESCE(SUM(d.duration_hours), 0) AS downtime_hrs,
            COALESCE(SUM(d.duration_hours) FILTER (WHERE d.reason='Breakdown'), 0) AS repair_hrs
        FROM assets.downtime_events d
        WHERE d.asset_id = p_asset_id
          AND (p_start_date IS NULL OR d.started_at >= p_start_date)
          AND (p_end_date   IS NULL OR d.started_at <= p_end_date)
        GROUP BY d.asset_id
    ),
    ph AS (
        SELECT EXTRACT(EPOCH FROM (
            COALESCE(p_end_date::timestamp, NOW()) -
            COALESCE(p_start_date::timestamp, a.install_date::timestamp)
        )) / 3600 AS total_hrs
        FROM assets.registry a WHERE a.asset_id = p_asset_id
    )
    SELECT a.asset_id, a.name,
        ROUND(((ph.total_hrs - COALESCE(pd.downtime_hrs,0)) / ph.total_hrs) * 100, 2),
        CASE WHEN pd.failures > 0 THEN ROUND(pd.repair_hrs / pd.failures, 2) ELSE 0 END,
        CASE WHEN pd.failures > 0 THEN ROUND((ph.total_hrs - COALESCE(pd.downtime_hrs,0)) / pd.failures, 2) ELSE NULL END,
        COALESCE(pd.failures, 0),
        COALESCE(p_start_date, a.install_date),
        COALESCE(p_end_date, CURRENT_DATE)
    FROM assets.registry a CROSS JOIN ph LEFT JOIN pd ON a.asset_id = pd.asset_id
    WHERE a.asset_id = p_asset_id;
END;
$$ LANGUAGE plpgsql
SET search_path = analytics, assets, maintenance, core, public;

CREATE OR REPLACE FUNCTION analytics.get_backlog_trend(
    p_start_date DATE DEFAULT CURRENT_DATE - INTERVAL '30 days',
    p_end_date   DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (report_date DATE, opened_count BIGINT, closed_count BIGINT, net_change BIGINT) AS $$
BEGIN
    RETURN QUERY
    SELECT d.dt::DATE,
        (SELECT COUNT(*) FROM maintenance.work_orders WHERE requested_date::DATE = d.dt::DATE),
        (SELECT COUNT(*) FROM maintenance.work_orders WHERE completion_time::DATE = d.dt::DATE),
        (SELECT COUNT(*) FROM maintenance.work_orders WHERE requested_date::DATE = d.dt::DATE) -
        (SELECT COUNT(*) FROM maintenance.work_orders WHERE completion_time::DATE = d.dt::DATE)
    FROM generate_series(p_start_date, p_end_date, '1 day'::interval) d(dt)
    ORDER BY d.dt;
END;
$$ LANGUAGE plpgsql
SET search_path = analytics, maintenance, public;

-- ####################################################################################
-- STEP 10: ROW-LEVEL SECURITY
-- ####################################################################################

-- Enable + Force RLS on all tenant-scoped tables
ALTER TABLE core.users                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.users                   FORCE ROW LEVEL SECURITY;
ALTER TABLE core.locations               ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.locations               FORCE ROW LEVEL SECURITY;
ALTER TABLE core.roles                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.roles                   FORCE ROW LEVEL SECURITY;
ALTER TABLE assets.types                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE assets.types                 FORCE ROW LEVEL SECURITY;
ALTER TABLE assets.registry              ENABLE ROW LEVEL SECURITY;
ALTER TABLE assets.registry              FORCE ROW LEVEL SECURITY;
ALTER TABLE assets.readings              ENABLE ROW LEVEL SECURITY;
ALTER TABLE assets.readings              FORCE ROW LEVEL SECURITY;
ALTER TABLE assets.downtime_events       ENABLE ROW LEVEL SECURITY;
ALTER TABLE assets.downtime_events       FORCE ROW LEVEL SECURITY;
ALTER TABLE catalog.maintenance_tasks    ENABLE ROW LEVEL SECURITY;
ALTER TABLE catalog.maintenance_tasks    FORCE ROW LEVEL SECURITY;
ALTER TABLE catalog.checklists           ENABLE ROW LEVEL SECURITY;
ALTER TABLE catalog.checklists           FORCE ROW LEVEL SECURITY;
ALTER TABLE catalog.checklist_items      ENABLE ROW LEVEL SECURITY;
ALTER TABLE catalog.checklist_items      FORCE ROW LEVEL SECURITY;
ALTER TABLE inventory.suppliers          ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory.suppliers          FORCE ROW LEVEL SECURITY;
ALTER TABLE inventory.parts              ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory.parts              FORCE ROW LEVEL SECURITY;
ALTER TABLE inventory.storerooms         ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory.storerooms         FORCE ROW LEVEL SECURITY;
ALTER TABLE inventory.stock              ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory.stock              FORCE ROW LEVEL SECURITY;
ALTER TABLE inventory.transactions       ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory.transactions       FORCE ROW LEVEL SECURITY;
ALTER TABLE maintenance.preventive_schedule  ENABLE ROW LEVEL SECURITY;
ALTER TABLE maintenance.preventive_schedule  FORCE ROW LEVEL SECURITY;
ALTER TABLE maintenance.work_orders          ENABLE ROW LEVEL SECURITY;
ALTER TABLE maintenance.work_orders          FORCE ROW LEVEL SECURITY;
ALTER TABLE maintenance.wo_tasks             ENABLE ROW LEVEL SECURITY;
ALTER TABLE maintenance.wo_tasks             FORCE ROW LEVEL SECURITY;
ALTER TABLE maintenance.wo_checklist_answers ENABLE ROW LEVEL SECURITY;
ALTER TABLE maintenance.wo_checklist_answers FORCE ROW LEVEL SECURITY;
ALTER TABLE maintenance.part_usage           ENABLE ROW LEVEL SECURITY;
ALTER TABLE maintenance.part_usage           FORCE ROW LEVEL SECURITY;
ALTER TABLE analytics.notifications          ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.notifications          FORCE ROW LEVEL SECURITY;
ALTER TABLE analytics.reports                ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.reports                FORCE ROW LEVEL SECURITY;
ALTER TABLE analytics.audit_logs             ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.audit_logs             FORCE ROW LEVEL SECURITY;

-- RLS Policies — programmatic loop for standard tables
DO $$
DECLARE
    t TEXT;
    tables TEXT[] := ARRAY[
        'core.users', 'core.locations',
        'assets.types', 'assets.registry', 'assets.readings', 'assets.downtime_events',
        'catalog.maintenance_tasks', 'catalog.checklists', 'catalog.checklist_items',
        'inventory.suppliers', 'inventory.parts', 'inventory.storerooms',
        'inventory.stock', 'inventory.transactions',
        'maintenance.preventive_schedule', 'maintenance.work_orders',
        'maintenance.wo_tasks', 'maintenance.wo_checklist_answers', 'maintenance.part_usage',
        'analytics.notifications', 'analytics.reports', 'analytics.audit_logs'
    ];
BEGIN
    FOREACH t IN ARRAY tables LOOP
        EXECUTE format('CREATE POLICY tenant_select ON %s FOR SELECT USING (tenant_id = core.current_tenant_id())', t);
        EXECUTE format('CREATE POLICY tenant_insert ON %s FOR INSERT WITH CHECK (tenant_id = core.current_tenant_id())', t);
        EXECUTE format('CREATE POLICY tenant_update ON %s FOR UPDATE USING (tenant_id = core.current_tenant_id()) WITH CHECK (tenant_id = core.current_tenant_id())', t);
        EXECUTE format('CREATE POLICY tenant_delete ON %s FOR DELETE USING (tenant_id = core.current_tenant_id())', t);
    END LOOP;
END $$;

-- Special: core.roles — tenants see their own roles + all global (NULL) roles
CREATE POLICY role_select ON core.roles FOR SELECT
    USING (tenant_id IS NULL OR tenant_id = core.current_tenant_id());
CREATE POLICY role_insert ON core.roles FOR INSERT
    WITH CHECK (tenant_id = core.current_tenant_id());
CREATE POLICY role_update ON core.roles FOR UPDATE
    USING (tenant_id = core.current_tenant_id())
    WITH CHECK (tenant_id = core.current_tenant_id());
CREATE POLICY role_delete ON core.roles FOR DELETE
    USING (tenant_id = core.current_tenant_id());

-- ####################################################################################
-- STEP 11: SEED DATA & ONBOARDING FUNCTION
-- ####################################################################################

-- Global system roles (tenant_id = NULL — visible to all, managed by Synaptia)
INSERT INTO core.roles (role_name, description, tenant_id) VALUES
    ('synaptia_superadmin', 'Platform-level administrator. Full cross-tenant access.', NULL),
    ('synaptia_support',    'Synaptia support. Read-only cross-tenant access.',         NULL)
ON CONFLICT DO NOTHING;

-- Provision tenant function: creates tenant + 4 standard roles in one call
-- Usage: SELECT core.provision_tenant('Acme Corp', 'acme', 'Pro');
CREATE OR REPLACE FUNCTION core.provision_tenant(
    p_company_name VARCHAR(255),
    p_subdomain    VARCHAR(100),
    p_plan         VARCHAR(50) DEFAULT 'Starter'
)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER
SET search_path = core, public
AS $$
DECLARE v_id BIGINT;
BEGIN
    INSERT INTO core.tenants (company_name, subdomain, plan)
    VALUES (p_company_name, p_subdomain, p_plan)
    RETURNING tenant_id INTO v_id;

    INSERT INTO core.roles (role_name, description, tenant_id) VALUES
        ('Admin',      'Full access to all modules.',                   v_id),
        ('Manager',    'Create/edit WOs, manage assets, view reports.', v_id),
        ('Technician', 'View and execute assigned work orders.',         v_id),
        ('Viewer',     'Read-only access.',                              v_id);

    RETURN v_id;
END;
$$;

-- ####################################################################################
-- STEP 12: SCHEMA DOCUMENTATION
-- ####################################################################################

COMMENT ON SCHEMA core        IS 'Identity, authentication, tenants, and organizational context';
COMMENT ON SCHEMA assets      IS 'Asset ontology, registry, telemetry, and downtime';
COMMENT ON SCHEMA catalog     IS 'Reusable templates: tasks, checklists, procedures';
COMMENT ON SCHEMA inventory   IS 'Parts, suppliers, stock levels, and transactions';
COMMENT ON SCHEMA maintenance IS 'Work order execution, preventive schedules, and part usage';
COMMENT ON SCHEMA analytics   IS 'Audit trails, reports, notifications, KPI views, and backlog intelligence';

COMMENT ON TABLE  core.tenants               IS 'Root B2B client entity. Every data row chains to a tenant.';
COMMENT ON FUNCTION core.current_tenant_id   IS 'Returns tenant_id from session var app.current_tenant.';
COMMENT ON FUNCTION core.provision_tenant    IS 'Creates a tenant + 4 default roles. Run as synaptia_admin.';
COMMENT ON VIEW analytics.v_asset_360        IS 'Unified asset intelligence — the Ficha Maestra.';
COMMENT ON VIEW analytics.v_kpi_dashboard    IS 'Master KPI dashboard: availability, MTTR, MTBF, reliability.';
COMMENT ON VIEW analytics.v_wo_backlog       IS 'All open WOs with aging, urgency ranking, and overdue flags.';
COMMENT ON VIEW analytics.v_backlog_summary  IS 'Single-row dashboard KPI: total backlog counts.';

-- ====================================================================================
-- END OF CORTEX MASTER v1.2
-- ====================================================================================
