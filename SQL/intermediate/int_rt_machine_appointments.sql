DROP VIEW IF EXISTS warehouse.int_rt_machine_appointments;

CREATE VIEW warehouse.int_rt_machine_appointments AS
SELECT
    activity_instance_id,
    machine,
    DATE(appt_start) AS appt_date,
    appt_start,
    appt_end,
    r_number,
    activity_name,

    EXTRACT(EPOCH FROM (appt_end - appt_start)) / 60 AS duration_minutes,

    
CASE
    WHEN activity_name ILIKE '%Closed%' THEN 'CLOSE'
    WHEN appointment_status ILIKE '%Cancelled%' THEN 'CANCELLED'
    WHEN r_number IS NULL THEN 'CATCHUP'
    ELSE 'PATIENT'
END AS appt_type


FROM staging.aria_machine_appointments;
