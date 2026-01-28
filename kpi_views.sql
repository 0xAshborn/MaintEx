-- ====================================================================================
-- SYNAPTIA TECHNOLOGIES - KPI VIEWS & DOWNTIME TRACKING
-- Extension for CORTEX.sql
-- Motor: PostgreSQL 14+
-- ====================================================================================

-- ====================================================================================
-- NEW TABLE: Downtime Events (For accurate KPI calculation)
-- ====================================================================================

CREATE TABLE assets.downtime_events (
    event_id BIGSERIAL PRIMARY KEY,
    asset_id BIGINT NOT NULL REFERENCES assets.registry(asset_id) ON DELETE CASCADE,
    started_at TIMESTAMP WITH TIME ZONE NOT NULL,
    ended_at TIMESTAMP WITH TIME ZONE,
    -- NOTE: duration_hours calculated in views/queries, not as generated column
    -- (PostgreSQL requires immutable functions for generated columns, NOW() is not immutable)
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

-- ====================================================================================
-- VIEW: Downtime Events with Calculated Duration
-- ====================================================================================

CREATE OR REPLACE VIEW analytics.v_downtime_events AS
SELECT 
    event_id,
    asset_id,
    started_at,
    ended_at,
    -- Calculate duration: if ended_at is NULL, use current time
    ROUND(EXTRACT(EPOCH FROM (COALESCE(ended_at, NOW()) - started_at)) / 3600, 2) AS duration_hours,
    reason,
    failure_code,
    wo_id,
    notes,
    created_by,
    created_at
FROM assets.downtime_events;

-- ====================================================================================
-- VIEW: Asset Failure Events (Breakdowns Only)
-- ====================================================================================

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

-- ====================================================================================
-- VIEW: MTTR (Mean Time To Repair)
-- Formula: Total Repair Time / Number of Repairs
-- ====================================================================================

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

-- ====================================================================================
-- VIEW: MTBF (Mean Time Between Failures)
-- Formula: Total Operating Time / Number of Failures
-- Requires: Asset install_date and downtime events
-- ====================================================================================

CREATE OR REPLACE VIEW analytics.v_asset_mtbf AS
WITH asset_timeline AS (
    SELECT 
        a.asset_id,
        a.name AS asset_name,
        a.tag_number,
        t.name AS asset_type,
        a.install_date,
        -- Total calendar hours since install
        EXTRACT(EPOCH FROM (NOW() - a.install_date::timestamp)) / 3600 AS total_hours,
        -- Total downtime hours
        COALESCE(SUM(d.duration_hours), 0) AS total_downtime_hours,
        -- Number of breakdown events
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
        ELSE NULL -- No failures = infinite MTBF (display as NULL)
    END AS mtbf_hours
FROM asset_timeline;

-- ====================================================================================
-- VIEW: MTTF (Mean Time To Failure)
-- For non-repairable assets or first failure analysis
-- Formula: Total Operating Time Until Failures / Number of Failures
-- ====================================================================================

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
        ELSE NULL -- Never failed
    END AS mttf_hours
FROM assets.registry a
    LEFT JOIN first_failures ff ON a.asset_id = ff.asset_id
WHERE a.install_date IS NOT NULL;

-- ====================================================================================
-- VIEW: Availability
-- Formula: Uptime / (Uptime + Downtime) × 100
-- ====================================================================================

CREATE OR REPLACE VIEW analytics.v_asset_availability AS
WITH availability_calc AS (
    SELECT 
        a.asset_id,
        a.name AS asset_name,
        a.tag_number,
        t.name AS asset_type,
        a.install_date,
        -- Total hours since install
        EXTRACT(EPOCH FROM (NOW() - a.install_date::timestamp)) / 3600 AS total_hours,
        -- Total downtime hours (all reasons)
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

-- ====================================================================================
-- VIEW: Utilization (Based on Runtime Readings)
-- Formula: Actual Runtime / Planned Runtime × 100
-- Requires: Runtime readings in assets.readings
-- ====================================================================================

CREATE OR REPLACE VIEW analytics.v_asset_utilization AS
WITH runtime_data AS (
    SELECT 
        a.asset_id,
        a.name AS asset_name,
        a.tag_number,
        -- Get latest runtime reading
        (SELECT value FROM assets.readings r 
         WHERE r.asset_id = a.asset_id 
         AND r.reading_type IN ('Runtime', 'Operating Hours', 'Hourmeter')
         ORDER BY timestamp DESC LIMIT 1) AS actual_runtime_hours,
        -- Planned hours (8 hrs/day since install)
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

-- ====================================================================================
-- VIEW: Reliability (Probability of No Failure in Next 30 Days)
-- Formula: R(t) = e^(-t/MTBF)
-- ====================================================================================

CREATE OR REPLACE VIEW analytics.v_asset_reliability AS
SELECT 
    asset_id,
    asset_name,
    tag_number,
    asset_type,
    mtbf_hours,
    -- Reliability for next 720 hours (30 days)
    CASE 
        WHEN mtbf_hours IS NOT NULL AND mtbf_hours > 0
        THEN ROUND(EXP(-720.0 / mtbf_hours) * 100, 2)
        ELSE 100.00 -- Never failed = 100% reliability
    END AS reliability_30day_percent,
    -- Reliability for next 168 hours (7 days)
    CASE 
        WHEN mtbf_hours IS NOT NULL AND mtbf_hours > 0
        THEN ROUND(EXP(-168.0 / mtbf_hours) * 100, 2)
        ELSE 100.00
    END AS reliability_7day_percent
FROM analytics.v_asset_mtbf;

-- ====================================================================================
-- MASTER VIEW: KPI Summary Dashboard
-- Combines all KPIs for comprehensive asset view
-- ====================================================================================

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
    -- Overall Health Score based on KPIs
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

-- ====================================================================================
-- FUNCTION: Get KPIs for Date Range (For API Use)
-- ====================================================================================

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

-- ====================================================================================
-- COMMENTS
-- ====================================================================================

COMMENT ON TABLE assets.downtime_events IS 'Tracks all asset downtime periods for KPI calculation';
COMMENT ON VIEW analytics.v_asset_mttr IS 'Mean Time To Repair - average repair duration';
COMMENT ON VIEW analytics.v_asset_mtbf IS 'Mean Time Between Failures - reliability metric';
COMMENT ON VIEW analytics.v_asset_availability IS 'Asset availability percentage based on uptime';
COMMENT ON VIEW analytics.v_kpi_dashboard IS 'Master KPI dashboard combining all metrics';
COMMENT ON FUNCTION analytics.get_asset_kpis IS 'Calculate KPIs for a specific asset and date range';
