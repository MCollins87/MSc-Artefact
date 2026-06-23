DROP TABLE IF EXISTS warehouse.fact_rt_machine_capacity;

CREATE TABLE warehouse.fact_rt_machine_capacity AS

WITH deduped AS (
    SELECT DISTINCT ON (
        machine,
        appt_date,
        appt_start,
        appt_end
    )
        machine,
        appt_date,
        appt_start,
        appt_end,
        duration_minutes,
        appt_type,
        r_number
    FROM warehouse.int_rt_machine_appointments
    ORDER BY
        machine,
        appt_date,
        appt_start,
        appt_end,
        duration_minutes DESC
),

demand AS (
    SELECT
        a.machine,
        a.appt_date,
        SUM(a.duration_minutes) AS demand_minutes
    FROM deduped a
    JOIN warehouse.int_rt_machine_capacity_window c
        ON a.machine = c.machine
        AND a.appt_date = c.appt_date
    WHERE a.appt_type = 'PATIENT'
      AND a.appt_start >= c.capacity_start
      AND a.appt_start < c.capacity_end
    GROUP BY a.machine, a.appt_date
),

lost_capacity AS (
    SELECT
        a.machine,
        a.appt_date,
        SUM(a.duration_minutes) AS lost_minutes
    FROM deduped a
    JOIN warehouse.int_rt_machine_capacity_window c
        ON a.machine = c.machine
        AND a.appt_date = c.appt_date
    WHERE a.appt_type IN ('CATCHUP', 'CANCELLED')
      AND a.appt_start >= c.capacity_start
      AND a.appt_start < c.capacity_end
    GROUP BY a.machine, a.appt_date
)

SELECT
    c.machine,
    c.appt_date,

    c.capacity_start,
    c.capacity_end,

    c.capacity_minutes,

    COALESCE(lc.lost_minutes, 0) AS lost_minutes,

    (c.capacity_minutes - COALESCE(lc.lost_minutes, 0)) AS net_capacity_minutes,

    d.demand_minutes,

    ROUND(
        d.demand_minutes /
        NULLIF(
            Greatest((c.capacity_minutes - COALESCE(lc.lost_minutes, 0)), 1),
            0
         ) * 100,
        1
    ) AS utilisation_pct,

    (d.demand_minutes -
     (c.capacity_minutes - COALESCE(lc.lost_minutes, 0))) AS variance_minutes,

    CASE
        WHEN d.demand_minutes > (c.capacity_minutes - COALESCE(lc.lost_minutes, 0)) THEN 'Over Capacity'
        WHEN d.demand_minutes > (c.capacity_minutes - COALESCE(lc.lost_minutes, 0)) * 0.9 THEN 'High Pressure'
        WHEN d.demand_minutes > (c.capacity_minutes - COALESCE(lc.lost_minutes, 0)) * 0.75 THEN 'Moderate'
        ELSE 'OK'
    END AS capacity_status

FROM warehouse.int_rt_machine_capacity_window c

LEFT JOIN demand d
    ON c.machine = d.machine
    AND c.appt_date = d.appt_date

LEFT JOIN lost_capacity lc
    ON c.machine = lc.machine
    AND c.appt_date = lc.appt_date;
