
DROP VIEW IF EXISTS warehouse.int_rt_treat_events;

CREATE VIEW warehouse.int_rt_treat_events AS

SELECT
    t.activity_instance_id,
    t.nhs_number,
    t.r_number,
    t.first_treat_date,
    t.appointment_status,
    t.resource_name,
    t.treat_activity_name,
    t.oncologist,
    t.activity_note,
    
CASE
    WHEN t.appointment_status ILIKE '%cancel%' THEN 'Cancelled'
    WHEN t.appointment_status ILIKE 'Completed%' THEN 'Completed'
    WHEN t.appointment_status ILIKE 'Manually Completed%' THEN 'Completed'
    WHEN t.appointment_status ILIKE 'Partially Completed%' THEN 'In Progress'
    WHEN t.appointment_status ILIKE '%Open%' THEN 'Open'
    ELSE 'Other'
END AS appointment_status_group



FROM staging.stg_aria_treat t
WHERE t.first_treat_date IS NOT NULL;
