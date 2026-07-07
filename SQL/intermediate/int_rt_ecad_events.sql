DROP VIEW IF EXISTS warehouse.int_rt_ecad_events;

CREATE VIEW warehouse.int_rt_ecad_events AS

SELECT
    e.activity_instance_id,
    e.r_number,
    e.ecad AS ecad_date,
    e.oncologist,
    e.nhs_number,
    e.pas_number,
    e.diagnosis_icd10,
    e.appointment_status
FROM staging.aria_ecad e
WHERE e.ecad IS NOT NULL
AND COALESCE(e.appointment_status, 'Completed') <> 'Cancelled';