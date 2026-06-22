DROP VIEW IF EXISTS warehouse.int_rt_treat_summary;

CREATE VIEW warehouse.int_rt_treat_summary AS
SELECT
    r_number,

    -- Any completed treatment?
    MAX(CASE WHEN appointment_status_group = 'Completed' THEN 1 ELSE 0 END) AS has_completed,

    -- Any future / open appointment?
    MAX(CASE
        WHEN appointment_status_group IN ('Open', 'In Progress')
            AND first_treat_date >= CURRENT_DATE
        THEN 1 ELSE 0 END) AS has_active_booking,

    -- Any Cancellations?
    MAX(CASE
        WHEN appointment_status_group = 'Cancelled'
        THEN 1 ELSE 0 END) AS has_cancelled,
    
    -- First valid treatment date (completed only)
    MIN(CASE
        WHEN appointment_status_group = 'Completed'
        THEN first_treat_date END) AS first_completed_treat_date

FROM warehouse.int_rt_treat_events
GROUP BY r_number;