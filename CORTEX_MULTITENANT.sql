-- ====================================================================================
-- SYNAPTIA TECHNOLOGIES - CORTEX MULTI-TENANT MIGRATION
-- Run AFTER CORTEX_MASTER.sql (this is a pure migration layer)
-- Motor: PostgreSQL 14+
-- Architecture: Strict Multi-Tenant via Row-Level Security (RLS)
-- Session Variable: SET app.current_tenant = '<tenant_id>';
-- ====================================================================================

-- ####################################################################################
-- PART 0: TENANT FOUNDATION
-- Global DB role + core.tenants table + helper function
-- ####################################################################################

-- ─────────────────────────────────────────────────────────────────────────────────────
-- 0.1  Database roles
--      synaptia_admin  → platform superuser, bypasses RLS
--      app_user        → the single role used by the Laravel application
-- ─────────────────────────────────────────────────────────────────────────────────────

-- NOTE: Run as a superuser. Adjust passwords before deploying to production.
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'synaptia_admin') THEN
        CREATE ROLE synaptia_admin NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_user') THEN
        CREATE ROLE app_user NOLOGIN;
    END IF;
END
$$;

-- Grant schema usage to app_user
GRANT USAGE ON SCHEMA core, assets, catalog, inventory, maintenance, analytics TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA core TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA assets TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA catalog TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA inventory TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA maintenance TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA analytics TO app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA core TO app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA assets TO app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA catalog TO app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA inventory TO app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA maintenance TO app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA analytics TO app_user;

-- synaptia_admin bypasses RLS on all tables it owns / has BYPASSRLS on
ALTER ROLE synaptia_admin BYPASSRLS;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- 0.2  core.tenants — the root B2B client entity
-- ─────────────────────────────────────────────────────────────────────────────────────

CREATE TABLE core.tenants (
    tenant_id   BIGSERIAL PRIMARY KEY,
    company_name VARCHAR(255) NOT NULL,
    subdomain   VARCHAR(100) UNIQUE NOT NULL,        -- e.g. 'acme' → acme.cortex.app
    plan        VARCHAR(50) NOT NULL DEFAULT 'Starter', -- 'Starter', 'Pro', 'Enterprise'
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT chk_subdomain CHECK (subdomain ~ '^[a-z0-9\-]+$')
);

COMMENT ON TABLE core.tenants IS 'Root B2B client entity. Every data row in the system belongs to a tenant.';

-- ─────────────────────────────────────────────────────────────────────────────────────
-- 0.3  Session helper function
--      Returns the tenant_id set in the current DB session.
--      Laravel calls: SET LOCAL app.current_tenant = '<id>' inside every transaction.
-- ─────────────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION core.current_tenant_id()
RETURNS BIGINT
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.current_tenant', TRUE), '')::BIGINT;
$$;

COMMENT ON FUNCTION core.current_tenant_id IS
    'Returns the tenant_id from the PostgreSQL session variable app.current_tenant. '
    'Must be set by the application before executing any tenant-scoped query.';

-- ####################################################################################
-- PART 1: PROPAGATE tenant_id — ALTER TABLE (non-destructive additions)
-- NOTE: We add columns as nullable first, backfill with the seed tenant,
--       then add the NOT NULL + FK constraint.
-- ####################################################################################

-- ─────────────────────────────────────────────────────────────────────────────────────
-- 1.0  Seed tenant for existing data
-- ─────────────────────────────────────────────────────────────────────────────────────
INSERT INTO core.tenants (company_name, subdomain, plan)
VALUES ('Default Tenant', 'default', 'Enterprise')
ON CONFLICT DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- CORE MODULE
-- ─────────────────────────────────────────────────────────────────────────────────────

-- core.roles: NULL tenant_id = global Synaptia-managed role
ALTER TABLE core.roles
    ADD COLUMN IF NOT EXISTS tenant_id BIGINT REFERENCES core.tenants(tenant_id) ON DELETE CASCADE;
-- tenant_id stays nullable intentionally (NULL = system-wide role)
CREATE INDEX idx_roles_tenant ON core.roles(tenant_id);
COMMENT ON COLUMN core.roles.tenant_id IS
    'NULL = global system role (Synaptia). Non-null = role created by and for a specific tenant.';

-- core.permissions: purely global, no tenant scoping needed.
-- No change to core.permissions — platform-wide definitions.

-- core.role_permissions: follows core.roles, no direct tenant_id needed.

-- core.users
ALTER TABLE core.users
    ADD COLUMN IF NOT EXISTS tenant_id BIGINT;
UPDATE core.users SET tenant_id = 1 WHERE tenant_id IS NULL;
ALTER TABLE core.users
    ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_users_tenant FOREIGN KEY (tenant_id) REFERENCES core.tenants(tenant_id) ON DELETE CASCADE;

-- core.locations
ALTER TABLE core.locations
    ADD COLUMN IF NOT EXISTS tenant_id BIGINT;
UPDATE core.locations SET tenant_id = 1 WHERE tenant_id IS NULL;
ALTER TABLE core.locations
    ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_locations_tenant FOREIGN KEY (tenant_id) REFERENCES core.tenants(tenant_id) ON DELETE CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- ASSETS MODULE
-- ─────────────────────────────────────────────────────────────────────────────────────

-- assets.types
ALTER TABLE assets.types
    ADD COLUMN IF NOT EXISTS tenant_id BIGINT;
UPDATE assets.types SET tenant_id = 1 WHERE tenant_id IS NULL;
ALTER TABLE assets.types
    ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_asset_types_tenant FOREIGN KEY (tenant_id) REFERENCES core.tenants(tenant_id) ON DELETE CASCADE;

-- assets.registry
ALTER TABLE assets.registry
    ADD COLUMN IF NOT EXISTS tenant_id BIGINT;
UPDATE assets.registry SET tenant_id = 1 WHERE tenant_id IS NULL;
ALTER TABLE assets.registry
    ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_asset_registry_tenant FOREIGN KEY (tenant_id) REFERENCES core.tenants(tenant_id) ON DELETE CASCADE;

-- assets.readings
ALTER TABLE assets.readings
    ADD COLUMN IF NOT EXISTS tenant_id BIGINT;
UPDATE assets.readings SET tenant_id = 1 WHERE tenant_id IS NULL;
ALTER TABLE assets.readings
    ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_readings_tenant FOREIGN KEY (tenant_id) REFERENCES core.tenants(tenant_id) ON DELETE CASCADE;

-- assets.downtime_events
ALTER TABLE assets.downtime_events
    ADD COLUMN IF NOT EXISTS tenant_id BIGINT;
UPDATE assets.downtime_events SET tenant_id = 1 WHERE tenant_id IS NULL;
ALTER TABLE assets.downtime_events
    ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_downtime_tenant FOREIGN KEY (tenant_id) REFERENCES core.tenants(tenant_id) ON DELETE CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- CATALOG MODULE
-- ─────────────────────────────────────────────────────────────────────────────────────

-- catalog.maintenance_tasks
ALTER TABLE catalog.maintenance_tasks
    ADD COLUMN IF NOT EXISTS tenant_id BIGINT;
UPDATE catalog.maintenance_tasks SET tenant_id = 1 WHERE tenant_id IS NULL;
ALTER TABLE catalog.maintenance_tasks
    ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_tasks_tenant FOREIGN KEY (tenant_id) REFERENCES core.tenants(tenant_id) ON DELETE CASCADE;

-- catalog.checklists
ALTER TABLE catalog.checklists
    ADD COLUMN IF NOT EXISTS tenant_id BIGINT;
UPDATE catalog.checklists SET tenant_id = 1 WHERE tenant_id IS NULL;
ALTER TABLE catalog.checklists
    ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_checklists_tenant FOREIGN KEY (tenant_id) REFERENCES core.tenants(tenant_id) ON DELETE CASCADE;

-- catalog.checklist_items — inherits tenant via checklist FK, but add column for direct RLS
ALTER TABLE catalog.checklist_items
    ADD COLUMN IF NOT EXISTS tenant_id BIGINT;
UPDATE catalog.checklist_items ci
    SET tenant_id = c.tenant_id
    FROM catalog.checklists c
    WHERE ci.checklist_id = c.checklist_id;
ALTER TABLE catalog.checklist_items
    ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_checklist_items_tenant FOREIGN KEY (tenant_id) REFERENCES core.tenants(tenant_id) ON DELETE CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- INVENTORY MODULE
-- ─────────────────────────────────────────────────────────────────────────────────────

-- inventory.suppliers
ALTER TABLE inventory.suppliers
    ADD COLUMN IF NOT EXISTS tenant_id BIGINT;
UPDATE inventory.suppliers SET tenant_id = 1 WHERE tenant_id IS NULL;
ALTER TABLE inventory.suppliers
    ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_suppliers_tenant FOREIGN KEY (tenant_id) REFERENCES core.tenants(tenant_id) ON DELETE CASCADE;

-- inventory.parts
ALTER TABLE inventory.parts
    ADD COLUMN IF NOT EXISTS tenant_id BIGINT;
UPDATE inventory.parts SET tenant_id = 1 WHERE tenant_id IS NULL;
ALTER TABLE inventory.parts
    ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_parts_tenant FOREIGN KEY (tenant_id) REFERENCES core.tenants(tenant_id) ON DELETE CASCADE;

-- inventory.storerooms
ALTER TABLE inventory.storerooms
    ADD COLUMN IF NOT EXISTS tenant_id BIGINT;
UPDATE inventory.storerooms SET tenant_id = 1 WHERE tenant_id IS NULL;
ALTER TABLE inventory.storerooms
    ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_storerooms_tenant FOREIGN KEY (tenant_id) REFERENCES core.tenants(tenant_id) ON DELETE CASCADE;

-- inventory.stock
ALTER TABLE inventory.stock
    ADD COLUMN IF NOT EXISTS tenant_id BIGINT;
UPDATE inventory.stock s
    SET tenant_id = st.tenant_id
    FROM inventory.storerooms st
    WHERE s.storeroom_id = st.storeroom_id;
ALTER TABLE inventory.stock
    ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_stock_tenant FOREIGN KEY (tenant_id) REFERENCES core.tenants(tenant_id) ON DELETE CASCADE;

-- inventory.transactions
ALTER TABLE inventory.transactions
    ADD COLUMN IF NOT EXISTS tenant_id BIGINT;
UPDATE inventory.transactions t2
    SET tenant_id = s.tenant_id
    FROM inventory.stock s
    WHERE t2.stock_id = s.stock_id;
ALTER TABLE inventory.transactions
    ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_transactions_tenant FOREIGN KEY (tenant_id) REFERENCES core.tenants(tenant_id) ON DELETE CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- MAINTENANCE MODULE
-- ─────────────────────────────────────────────────────────────────────────────────────

-- maintenance.preventive_schedule
ALTER TABLE maintenance.preventive_schedule
    ADD COLUMN IF NOT EXISTS tenant_id BIGINT;
UPDATE maintenance.preventive_schedule SET tenant_id = 1 WHERE tenant_id IS NULL;
ALTER TABLE maintenance.preventive_schedule
    ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_pm_tenant FOREIGN KEY (tenant_id) REFERENCES core.tenants(tenant_id) ON DELETE CASCADE;

-- maintenance.work_orders
ALTER TABLE maintenance.work_orders
    ADD COLUMN IF NOT EXISTS tenant_id BIGINT;
UPDATE maintenance.work_orders SET tenant_id = 1 WHERE tenant_id IS NULL;
ALTER TABLE maintenance.work_orders
    ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_wo_tenant FOREIGN KEY (tenant_id) REFERENCES core.tenants(tenant_id) ON DELETE CASCADE;

-- maintenance.wo_tasks
ALTER TABLE maintenance.wo_tasks
    ADD COLUMN IF NOT EXISTS tenant_id BIGINT;
UPDATE maintenance.wo_tasks wt
    SET tenant_id = wo.tenant_id
    FROM maintenance.work_orders wo
    WHERE wt.wo_id = wo.wo_id;
ALTER TABLE maintenance.wo_tasks
    ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_wo_tasks_tenant FOREIGN KEY (tenant_id) REFERENCES core.tenants(tenant_id) ON DELETE CASCADE;

-- maintenance.wo_checklist_answers
ALTER TABLE maintenance.wo_checklist_answers
    ADD COLUMN IF NOT EXISTS tenant_id BIGINT;
UPDATE maintenance.wo_checklist_answers wca
    SET tenant_id = wo.tenant_id
    FROM maintenance.work_orders wo
    WHERE wca.wo_id = wo.wo_id;
ALTER TABLE maintenance.wo_checklist_answers
    ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_wo_answers_tenant FOREIGN KEY (tenant_id) REFERENCES core.tenants(tenant_id) ON DELETE CASCADE;

-- maintenance.part_usage
ALTER TABLE maintenance.part_usage
    ADD COLUMN IF NOT EXISTS tenant_id BIGINT;
UPDATE maintenance.part_usage pu
    SET tenant_id = wo.tenant_id
    FROM maintenance.work_orders wo
    WHERE pu.wo_id = wo.wo_id;
ALTER TABLE maintenance.part_usage
    ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_part_usage_tenant FOREIGN KEY (tenant_id) REFERENCES core.tenants(tenant_id) ON DELETE CASCADE;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- ANALYTICS MODULE
-- ─────────────────────────────────────────────────────────────────────────────────────

-- analytics.notifications
ALTER TABLE analytics.notifications
    ADD COLUMN IF NOT EXISTS tenant_id BIGINT;
UPDATE analytics.notifications SET tenant_id = 1 WHERE tenant_id IS NULL;
ALTER TABLE analytics.notifications
    ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_notifications_tenant FOREIGN KEY (tenant_id) REFERENCES core.tenants(tenant_id) ON DELETE CASCADE;

-- analytics.reports
ALTER TABLE analytics.reports
    ADD COLUMN IF NOT EXISTS tenant_id BIGINT;
UPDATE analytics.reports SET tenant_id = 1 WHERE tenant_id IS NULL;
ALTER TABLE analytics.reports
    ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_reports_tenant FOREIGN KEY (tenant_id) REFERENCES core.tenants(tenant_id) ON DELETE CASCADE;

-- analytics.audit_logs
ALTER TABLE analytics.audit_logs
    ADD COLUMN IF NOT EXISTS tenant_id BIGINT;
UPDATE analytics.audit_logs SET tenant_id = 1 WHERE tenant_id IS NULL;
ALTER TABLE analytics.audit_logs
    ALTER COLUMN tenant_id SET NOT NULL,
    ADD CONSTRAINT fk_audit_tenant FOREIGN KEY (tenant_id) REFERENCES core.tenants(tenant_id) ON DELETE CASCADE;

-- ####################################################################################
-- PART 2: COMPOSITE INDEXES (tenant_id + key filter columns)
-- Existing single-column indexes are dropped and replaced for efficiency.
-- ####################################################################################

-- core
DROP INDEX IF EXISTS idx_users_email;
DROP INDEX IF EXISTS idx_users_role;
CREATE UNIQUE INDEX idx_users_tenant_email ON core.users(tenant_id, email);
CREATE INDEX idx_users_tenant_role   ON core.users(tenant_id, role_id);
CREATE INDEX idx_users_tenant        ON core.users(tenant_id);

CREATE INDEX idx_locations_tenant    ON core.locations(tenant_id);

-- assets
DROP INDEX IF EXISTS idx_asset_location;
DROP INDEX IF EXISTS idx_asset_type;
DROP INDEX IF EXISTS idx_asset_tag;
DROP INDEX IF EXISTS idx_asset_status;
DROP INDEX IF EXISTS idx_asset_custom_gin;
CREATE UNIQUE INDEX idx_asset_tenant_tag    ON assets.registry(tenant_id, tag_number);
CREATE INDEX idx_asset_tenant_status        ON assets.registry(tenant_id, status);
CREATE INDEX idx_asset_tenant_location      ON assets.registry(tenant_id, location_id);
CREATE INDEX idx_asset_tenant_type          ON assets.registry(tenant_id, asset_type_id);
CREATE INDEX idx_asset_tenant_custom_gin    ON assets.registry USING GIN (custom_fields);

DROP INDEX IF EXISTS idx_readings_asset_time;
CREATE INDEX idx_readings_tenant_time ON assets.readings(tenant_id, asset_id, timestamp DESC);

DROP INDEX IF EXISTS idx_downtime_asset;
DROP INDEX IF EXISTS idx_downtime_dates;
DROP INDEX IF EXISTS idx_downtime_reason;
CREATE INDEX idx_downtime_tenant_asset  ON assets.downtime_events(tenant_id, asset_id);
CREATE INDEX idx_downtime_tenant_dates  ON assets.downtime_events(tenant_id, started_at, ended_at);

-- inventory
DROP INDEX IF EXISTS idx_stock_part;
DROP INDEX IF EXISTS idx_stock_storeroom;
DROP INDEX IF EXISTS idx_transactions_stock;
DROP INDEX IF EXISTS idx_transactions_time;
CREATE INDEX idx_stock_tenant_part       ON inventory.stock(tenant_id, part_id);
CREATE INDEX idx_stock_tenant_storeroom  ON inventory.stock(tenant_id, storeroom_id);
CREATE INDEX idx_trans_tenant_stock      ON inventory.transactions(tenant_id, stock_id);
CREATE INDEX idx_trans_tenant_time       ON inventory.transactions(tenant_id, timestamp DESC);

-- maintenance
DROP INDEX IF EXISTS idx_wo_asset;
DROP INDEX IF EXISTS idx_wo_status;
DROP INDEX IF EXISTS idx_wo_priority;
DROP INDEX IF EXISTS idx_wo_assigned;
DROP INDEX IF EXISTS idx_wo_due_date;
DROP INDEX IF EXISTS idx_wo_pm;
CREATE INDEX idx_wo_tenant_status    ON maintenance.work_orders(tenant_id, status);
CREATE INDEX idx_wo_tenant_priority  ON maintenance.work_orders(tenant_id, priority);
CREATE INDEX idx_wo_tenant_asset     ON maintenance.work_orders(tenant_id, asset_id);
CREATE INDEX idx_wo_tenant_assigned  ON maintenance.work_orders(tenant_id, assigned_to_id);
CREATE INDEX idx_wo_tenant_due_date  ON maintenance.work_orders(tenant_id, due_date);
CREATE INDEX idx_wo_tenant_pm        ON maintenance.work_orders(tenant_id, pm_id);

CREATE INDEX idx_pm_tenant           ON maintenance.preventive_schedule(tenant_id);
CREATE INDEX idx_pm_tenant_due       ON maintenance.preventive_schedule(tenant_id, next_due_date);

-- analytics
DROP INDEX IF EXISTS idx_audit_table_record;
DROP INDEX IF EXISTS idx_audit_timestamp;
DROP INDEX IF EXISTS idx_notifications_user;
CREATE INDEX idx_audit_tenant_table  ON analytics.audit_logs(tenant_id, table_name, record_id);
CREATE INDEX idx_audit_tenant_time   ON analytics.audit_logs(tenant_id, timestamp DESC);
CREATE INDEX idx_notif_tenant_user   ON analytics.notifications(tenant_id, user_id, is_read);

-- ####################################################################################
-- PART 3: ENABLE ROW-LEVEL SECURITY
-- FORCE ensures that even table owners respect RLS (except superusers & synaptia_admin)
-- ####################################################################################

-- CORE
ALTER TABLE core.users                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.users                    FORCE ROW LEVEL SECURITY;
ALTER TABLE core.locations                ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.locations                FORCE ROW LEVEL SECURITY;
ALTER TABLE core.roles                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.roles                    FORCE ROW LEVEL SECURITY;

-- ASSETS
ALTER TABLE assets.types                  ENABLE ROW LEVEL SECURITY;
ALTER TABLE assets.types                  FORCE ROW LEVEL SECURITY;
ALTER TABLE assets.registry               ENABLE ROW LEVEL SECURITY;
ALTER TABLE assets.registry               FORCE ROW LEVEL SECURITY;
ALTER TABLE assets.readings               ENABLE ROW LEVEL SECURITY;
ALTER TABLE assets.readings               FORCE ROW LEVEL SECURITY;
ALTER TABLE assets.downtime_events        ENABLE ROW LEVEL SECURITY;
ALTER TABLE assets.downtime_events        FORCE ROW LEVEL SECURITY;

-- CATALOG
ALTER TABLE catalog.maintenance_tasks     ENABLE ROW LEVEL SECURITY;
ALTER TABLE catalog.maintenance_tasks     FORCE ROW LEVEL SECURITY;
ALTER TABLE catalog.checklists            ENABLE ROW LEVEL SECURITY;
ALTER TABLE catalog.checklists            FORCE ROW LEVEL SECURITY;
ALTER TABLE catalog.checklist_items       ENABLE ROW LEVEL SECURITY;
ALTER TABLE catalog.checklist_items       FORCE ROW LEVEL SECURITY;

-- INVENTORY
ALTER TABLE inventory.suppliers           ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory.suppliers           FORCE ROW LEVEL SECURITY;
ALTER TABLE inventory.parts               ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory.parts               FORCE ROW LEVEL SECURITY;
ALTER TABLE inventory.storerooms          ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory.storerooms          FORCE ROW LEVEL SECURITY;
ALTER TABLE inventory.stock               ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory.stock               FORCE ROW LEVEL SECURITY;
ALTER TABLE inventory.transactions        ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory.transactions        FORCE ROW LEVEL SECURITY;

-- MAINTENANCE
ALTER TABLE maintenance.preventive_schedule   ENABLE ROW LEVEL SECURITY;
ALTER TABLE maintenance.preventive_schedule   FORCE ROW LEVEL SECURITY;
ALTER TABLE maintenance.work_orders           ENABLE ROW LEVEL SECURITY;
ALTER TABLE maintenance.work_orders           FORCE ROW LEVEL SECURITY;
ALTER TABLE maintenance.wo_tasks              ENABLE ROW LEVEL SECURITY;
ALTER TABLE maintenance.wo_tasks              FORCE ROW LEVEL SECURITY;
ALTER TABLE maintenance.wo_checklist_answers  ENABLE ROW LEVEL SECURITY;
ALTER TABLE maintenance.wo_checklist_answers  FORCE ROW LEVEL SECURITY;
ALTER TABLE maintenance.part_usage            ENABLE ROW LEVEL SECURITY;
ALTER TABLE maintenance.part_usage            FORCE ROW LEVEL SECURITY;

-- ANALYTICS
ALTER TABLE analytics.notifications       ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.notifications       FORCE ROW LEVEL SECURITY;
ALTER TABLE analytics.reports             ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.reports             FORCE ROW LEVEL SECURITY;
ALTER TABLE analytics.audit_logs          ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.audit_logs          FORCE ROW LEVEL SECURITY;

-- ####################################################################################
-- PART 4: RLS POLICIES
-- Pattern: one policy per operation (SELECT, INSERT, UPDATE, DELETE) per table.
-- Condition: tenant_id = core.current_tenant_id()
-- Special: core.roles allows reading NULL tenant_id (global roles visible to all)
-- ####################################################################################

-- ─── Macro to reduce repetition ────────────────────────────────────────────────────
-- We use a DO block to loop and create standard 4-policy sets programmatically.
-- Then handle special cases (core.roles) manually.
-- ─────────────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
    t TEXT;
    tables TEXT[] := ARRAY[
        'core.users',
        'core.locations',
        'assets.types',
        'assets.registry',
        'assets.readings',
        'assets.downtime_events',
        'catalog.maintenance_tasks',
        'catalog.checklists',
        'catalog.checklist_items',
        'inventory.suppliers',
        'inventory.parts',
        'inventory.storerooms',
        'inventory.stock',
        'inventory.transactions',
        'maintenance.preventive_schedule',
        'maintenance.work_orders',
        'maintenance.wo_tasks',
        'maintenance.wo_checklist_answers',
        'maintenance.part_usage',
        'analytics.notifications',
        'analytics.reports',
        'analytics.audit_logs'
    ];
BEGIN
    FOREACH t IN ARRAY tables LOOP
        -- SELECT
        EXECUTE format(
            'CREATE POLICY tenant_isolation_select ON %s FOR SELECT
             USING (tenant_id = core.current_tenant_id())', t
        );
        -- INSERT
        EXECUTE format(
            'CREATE POLICY tenant_isolation_insert ON %s FOR INSERT
             WITH CHECK (tenant_id = core.current_tenant_id())', t
        );
        -- UPDATE
        EXECUTE format(
            'CREATE POLICY tenant_isolation_update ON %s FOR UPDATE
             USING (tenant_id = core.current_tenant_id())
             WITH CHECK (tenant_id = core.current_tenant_id())', t
        );
        -- DELETE
        EXECUTE format(
            'CREATE POLICY tenant_isolation_delete ON %s FOR DELETE
             USING (tenant_id = core.current_tenant_id())', t
        );
    END LOOP;
END
$$;

-- ─────────────────────────────────────────────────────────────────────────────────────
-- SPECIAL CASE: core.roles
-- Tenants can see their own roles AND global roles (tenant_id IS NULL).
-- Tenants can only INSERT/UPDATE/DELETE their own roles (NOT global ones).
-- ─────────────────────────────────────────────────────────────────────────────────────

CREATE POLICY role_select ON core.roles FOR SELECT
    USING (
        tenant_id IS NULL                       -- global/system roles (visible to all)
        OR tenant_id = core.current_tenant_id() -- tenant's own roles
    );

CREATE POLICY role_insert ON core.roles FOR INSERT
    WITH CHECK (tenant_id = core.current_tenant_id()); -- tenants create their own roles only

CREATE POLICY role_update ON core.roles FOR UPDATE
    USING (tenant_id = core.current_tenant_id())       -- cannot touch global roles
    WITH CHECK (tenant_id = core.current_tenant_id());

CREATE POLICY role_delete ON core.roles FOR DELETE
    USING (tenant_id = core.current_tenant_id());      -- cannot delete global roles

-- ####################################################################################
-- PART 5: ROLE REFACTORING
-- Seed global (Synaptia-managed) roles and a sample tenant-specific role hierarchy.
-- ####################################################################################

-- Global roles (tenant_id = NULL)
INSERT INTO core.roles (role_name, description, tenant_id) VALUES
    ('synaptia_superadmin', 'Platform-level administrator. Full access to all tenants and system settings.', NULL),
    ('synaptia_support',    'Synaptia support agent. Read-only cross-tenant access for support cases.',    NULL)
ON CONFLICT (role_name) DO NOTHING;

-- Default tenant roles (tenant_id = 1 — the seed tenant created in Part 1)
-- These are TEMPLATES; each new tenant should get their own copy on onboarding.
INSERT INTO core.roles (role_name, description, tenant_id) VALUES
    ('Admin',       'Full access to all modules within the tenant account.',      1),
    ('Manager',     'Create/edit work orders, manage assets, view all reports.',   1),
    ('Technician',  'View and execute assigned work orders.',                       1),
    ('Viewer',      'Read-only access to assets, work orders, and reports.',       1)
ON CONFLICT (role_name) DO NOTHING;

-- ####################################################################################
-- PART 6: HELPER FUNCTIONS FOR ONBOARDING & ADMINISTRATION
-- ####################################################################################

-- ─────────────────────────────────────────────────────────────────────────────────────
-- 6.1  Provision a new tenant with default roles
--      Call: SELECT core.provision_tenant('Acme Corp', 'acme', 'Pro');
-- ─────────────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION core.provision_tenant(
    p_company_name VARCHAR(255),
    p_subdomain    VARCHAR(100),
    p_plan         VARCHAR(50) DEFAULT 'Starter'
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER  -- runs as the function owner (synaptia_admin) regardless of caller
AS $$
DECLARE
    v_tenant_id BIGINT;
BEGIN
    -- 1. Create the tenant record
    INSERT INTO core.tenants (company_name, subdomain, plan)
    VALUES (p_company_name, p_subdomain, p_plan)
    RETURNING tenant_id INTO v_tenant_id;

    -- 2. Seed standard roles for this tenant
    INSERT INTO core.roles (role_name, description, tenant_id) VALUES
        ('Admin',       'Full access to all modules within the tenant account.',     v_tenant_id),
        ('Manager',     'Create/edit work orders, manage assets, view all reports.', v_tenant_id),
        ('Technician',  'View and execute assigned work orders.',                    v_tenant_id),
        ('Viewer',      'Read-only access to assets, work orders, and reports.',     v_tenant_id);

    RETURN v_tenant_id;
END;
$$;

COMMENT ON FUNCTION core.provision_tenant IS
    'Creates a new tenant with standard roles. Run as synaptia_admin. '
    'Returns the new tenant_id.';

-- ─────────────────────────────────────────────────────────────────────────────────────
-- 6.2  Verify RLS is active (sanity check query)
-- ─────────────────────────────────────────────────────────────────────────────────────

-- Run this after migration to confirm all tables have RLS:
-- SELECT schemaname, tablename, rowsecurity
-- FROM pg_tables
-- WHERE schemaname IN ('core','assets','catalog','inventory','maintenance','analytics')
--   AND rowsecurity = FALSE;
-- Expected: 0 rows (all tenant-scoped tables protected).

-- ─────────────────────────────────────────────────────────────────────────────────────
-- 6.3  Test isolation helper
-- ─────────────────────────────────────────────────────────────────────────────────────

-- How to verify tenant isolation manually:
--   SET app.current_tenant = '1';
--   SELECT COUNT(*) FROM core.users; -- rows for tenant 1 only
--
--   SET app.current_tenant = '2';
--   SELECT COUNT(*) FROM core.users; -- rows for tenant 2 only
--
-- How to read ALL data (as synaptia_admin):
--   SET ROLE synaptia_admin;
--   SELECT COUNT(*) FROM core.users; -- all rows, RLS bypassed

-- ####################################################################################
-- PART 7: LARAVEL INTEGRATION NOTES
-- ####################################################################################

-- In Laravel, add a middleware (e.g. SetTenantContext) to every API request:
--
--    DB::statement("SET LOCAL app.current_tenant = ?", [$tenant->tenant_id]);
--
-- For Eloquent models, add a GlobalScope:
--
--    class TenantScope implements Scope {
--        public function apply(Builder $builder, Model $model) {
--            $builder->where('tenant_id', app('tenant')->id);
--        }
--    }
--
-- The combination of RLS (DB-level) + GlobalScope (ORM-level) gives you
-- defense in depth: two independent isolation layers.

-- End of CORTEX_MULTITENANT.sql
