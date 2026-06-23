DROP VIEW IF EXISTS warehouse.int_rt_machine_capacity_window;

CREATE VIEW warehouse.int_rt_machine_capacity_window AS

WITH base AS (
    SELECT
        machine,
        appt_date,
        appt_start,
        appt_end,
        r_number,
        activity_name
    FROM warehouse.int_rt_machine_appointments
),

start_times AS (
    SELECT
        machine,
        appt_date,
        MIN(appt_end) AS capacity_start
    FROM base
    WHERE r_number LIKE 'ZZZZ%'
    GROUP BY machine, appt_date
),

end_times AS (
    SELECT
        machine,
        appt_date,
        MIN(appt_start) AS capacity_end
    FROM base
    WHERE activity_name ILIKE '%Closed%'
    GROUP BY machine, appt_date
)

SELECT
    s.machine,
    s.appt_date,
    s.capacity_start,
    e.capacity_end,
    EXTRACT(EPOCH FROM (e.capacity_end - s.capacity_start)) / 60 AS capacity_minutes

FROM start_times s
JOIN end_times e
    ON s.machine = e.machine
    AND s.appt_date = e.appt_date

WHERE e.capacity_end > s.capacity_start
AND (e.capacity_end - s.capacity_start) > interval '1 hour';