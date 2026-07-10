DROP VIEW IF EXISTS warehouse.int_oncology_clinic_events;

CREATE VIEW warehouse.int_oncology_clinic_events AS

WITH clinic_rollup AS(
    SELECT
        pas_number,
        nhs_number,
        MIN(booking_date) AS first_booking_date,
        MIN(appointment_date) AS first_appointment_date
     FROM staging.oncology_clinic
     GROUP BY pas_number, nhs_number
)

SELECT
    r.*,
    c.appointment_attendance_status
FROM clinic_rollup r

LEFT JOIN staging.oncology_clinic c
    ON r.pas_number = c.pas_number
    AND r.first_appointment_date = c.appointment_date;