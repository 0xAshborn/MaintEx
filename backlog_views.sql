-- ====================================================================================
-- SYNAPTIA TECHNOLOGIES - BACKLOG VIEWS
-- Extension for CORTEX.sql
-- Motor: PostgreSQL 14+
-- ====================================================================================

-- ====================================================================================
-- VIEW: Work Order Backlog (All open/pending work)
-- Shows every WO that hasn't been completed yet with aging info
-- ====================================================================================

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
    -- Aging: days since request
    ROUND(EXTRACT(EPOCH FROM (NOW() - wo.requested_date)) / 86400, 1) AS age_days,
    -- Overdue: days past due date
    CASE 
        WHEN wo.due_date IS NOT NULL AND wo.due_date < NOW()
        THEN ROUND(EXTRACT(EPOCH FROM (NOW() - wo.due_date)) / 86400, 1)
        ELSE 0
    END AS overdue_days,
    -- Is overdue flag
    CASE 
        WHEN wo.due_date IS NOT NULL AND wo.due_date < NOW() THEN TRUE
        ELSE FALSE
    END AS is_overdue,
    -- Urgency classification
    CASE 
        WHEN wo.priority = 'Urgent' THEN 1
        WHEN wo.due_date IS NOT NULL AND wo.due_date < NOW() THEN 2
        WHEN wo.priority = 'High' THEN 3
        WHEN wo.priority = 'Medium' THEN 4
        ELSE 5
    END AS urgency_rank,
    -- Urgency label
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

-- ====================================================================================
-- VIEW: PM Backlog (Overdue + Unscheduled Preventive Maintenance)
-- ====================================================================================

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
    -- Overdue days (NULL if not overdue or no due date)
    CASE 
        WHEN pm.next_due_date IS NOT NULL AND pm.next_due_date < CURRENT_DATE
        THEN (CURRENT_DATE - pm.next_due_date)
        ELSE 0
    END AS overdue_days,
    -- Backlog category
    CASE 
        WHEN pm.next_due_date IS NULL THEN 'UNSCHEDULED'
        WHEN pm.next_due_date < CURRENT_DATE - INTERVAL '30 days' THEN 'CRITICAL_OVERDUE'
        WHEN pm.next_due_date < CURRENT_DATE - INTERVAL '7 days' THEN 'OVERDUE'
        WHEN pm.next_due_date < CURRENT_DATE THEN 'RECENTLY_OVERDUE'
        WHEN pm.next_due_date <= CURRENT_DATE + INTERVAL '7 days' THEN 'DUE_SOON'
        ELSE 'SCHEDULED'
    END AS backlog_status,
    -- Urgency rank for sorting
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

-- ====================================================================================
-- VIEW: Combined Backlog Summary (Dashboard KPI)
-- Single row with total backlog counts
-- ====================================================================================

CREATE OR REPLACE VIEW analytics.v_backlog_summary AS
SELECT 
    -- Work Order counts
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
    
    -- PM counts
    (SELECT COUNT(*) FROM maintenance.preventive_schedule 
     WHERE is_active = TRUE AND next_due_date IS NOT NULL 
     AND next_due_date < CURRENT_DATE) AS overdue_pm,
    
    (SELECT COUNT(*) FROM maintenance.preventive_schedule 
     WHERE is_active = TRUE AND next_due_date IS NULL) AS unscheduled_pm,

    (SELECT COUNT(*) FROM maintenance.preventive_schedule 
     WHERE is_active = TRUE AND next_due_date BETWEEN CURRENT_DATE 
     AND CURRENT_DATE + INTERVAL '7 days') AS pm_due_this_week,
    
    -- Totals
    (SELECT COUNT(*) FROM maintenance.work_orders 
     WHERE status NOT IN ('Complete', 'Cancelled'))
    + 
    (SELECT COUNT(*) FROM maintenance.preventive_schedule 
     WHERE is_active = TRUE AND next_due_date IS NOT NULL 
     AND next_due_date < CURRENT_DATE) AS total_backlog,

    -- Average age of open WOs (days)
    (SELECT ROUND(AVG(EXTRACT(EPOCH FROM (NOW() - requested_date)) / 86400), 1)
     FROM maintenance.work_orders 
     WHERE status NOT IN ('Complete', 'Cancelled')) AS avg_wo_age_days;

-- ====================================================================================
-- VIEW: Backlog by Priority (For charts)
-- ====================================================================================

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

-- ====================================================================================
-- VIEW: Backlog by Asset (Which assets have the most pending work)
-- ====================================================================================

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

-- ====================================================================================
-- VIEW: Backlog Aging Buckets (How old is the pending work)
-- ====================================================================================

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

-- ====================================================================================
-- FUNCTION: Get Backlog for a Date Range (API use)
-- ====================================================================================

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

-- ====================================================================================
-- COMMENTS
-- ====================================================================================

COMMENT ON VIEW analytics.v_wo_backlog IS 'All open/pending work orders with aging and urgency classification';
COMMENT ON VIEW analytics.v_pm_backlog IS 'Overdue and unscheduled preventive maintenance tasks';
COMMENT ON VIEW analytics.v_backlog_summary IS 'Single-row dashboard summary of all backlog counts';
COMMENT ON VIEW analytics.v_backlog_by_priority IS 'Backlog breakdown by work order priority';
COMMENT ON VIEW analytics.v_backlog_by_asset IS 'Which assets have the most pending work';
COMMENT ON VIEW analytics.v_backlog_aging IS 'Age distribution of open work orders in time buckets';
COMMENT ON FUNCTION analytics.get_backlog_trend IS 'Daily trend of opened vs closed work orders for backlog analysis';
