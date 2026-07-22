DROP VIEW IF EXISTS warehouse.int_oncology_clinic_events;

CREATE VIEW warehouse.int_oncology_clinic_events AS

WITH bookings AS(
    SELECT
        pas_number,
        nhs_number,
        MIN(booking_date) AS first_booking_date,
        MIN(appointment_date) AS first_clinic_date,
        MAX(ref_to_local_code) AS clinic_speciality
    FROM staging.oncology_clinic
    WHERE record_source = 'Booking'
    GROUP BY pas_number, nhs_number
),

latest_attendance AS (
    SELECT DISTINCT ON (
        pas_number,
        nhs_number,
        appointment_date
    )
        pas_number,
        nhs_number,
        appointment_date,
        appointment_attended,
        appointment_attendance_status
    FROM staging.oncology_clinic
    WHERE record_source = 'Appointment'
    ORDER BY 
        pas_number, 
        nhs_number, 
        appointment_date, 
        load_timestamp DESC
)

SELECT
    b.pas_number,
    b.nhs_number,
    b.first_booking_date,
    b.first_clinic_date,
    b.clinic_speciality,
    a.appointment_attended,
    a.appointment_attendance_status
FROM bookings b

LEFT JOIN latest_attendance a
    ON b.pas_number = a.pas_number
    AND b.nhs_number = a.nhs_number
    AND b.first_clinic_date = a.appointment_date;
