-- ====================================================================================
-- CORTEX SECURITY HOTFIX — Function Search Path Lock
-- Run this in the Supabase SQL Editor to fix the 4 "Function Search Path Mutable"
-- warnings from the Security Advisor WITHOUT wiping any data.
-- ====================================================================================

-- 1. core.current_tenant_id
--    Reads app.current_tenant session variable for RLS.
CREATE OR REPLACE FUNCTION core.current_tenant_id()
RETURNS BIGINT LANGUAGE sql STABLE
SET search_path = core, public
AS $$
    SELECT NULLIF(current_setting('app.current_tenant', TRUE), '')::BIGINT;
$$;

-- 2. analytics.get_asset_kpis
--    Returns MTTR, MTBF, availability for a given asset.
CREATE OR REPLACE FUNCTION analytics.get_asset_kpis(
    p_asset_id   BIGINT,
    p_start_date DATE DEFAULT NULL,
    p_end_date   DATE DEFAULT NULL
)
RETURNS TABLE (
    asset_id             BIGINT, asset_name VARCHAR,
    availability_percent NUMERIC, mttr_hours NUMERIC,
    mtbf_hours NUMERIC, failure_count BIGINT,
    period_start DATE, period_end DATE
)
LANGUAGE plpgsql
SET search_path = analytics, assets, maintenance, core, public
AS $$
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
$$;

-- 3. analytics.get_backlog_trend
--    Returns daily opened/closed/net WO counts for a date range.
CREATE OR REPLACE FUNCTION analytics.get_backlog_trend(
    p_start_date DATE DEFAULT CURRENT_DATE - INTERVAL '30 days',
    p_end_date   DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (report_date DATE, opened_count BIGINT, closed_count BIGINT, net_change BIGINT)
LANGUAGE plpgsql
SET search_path = analytics, maintenance, public
AS $$
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
$$;

-- 4. core.provision_tenant
--    Creates a tenant + 4 default roles. Run as synaptia_admin.
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

-- Verify: these should now show 0 warnings in Security Advisor
-- SELECT proname, prosecdef, proconfig FROM pg_proc
-- WHERE proname IN ('current_tenant_id','get_asset_kpis','get_backlog_trend','provision_tenant');
