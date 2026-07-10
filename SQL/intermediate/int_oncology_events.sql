
DROP VIEW IF EXISTS warehouse.int_oncology_events;

CREATE VIEW warehouse.int_oncology_events AS

WITH oncology_clean AS (
    SELECT
        o.nhs_number,
        o.referral_date,
        o.first_clinic_date,
        o.first_booking_date,
        o.appointment_attendance_status,

        ROW_NUMBER() OVER (
            PARTITION BY o.nhs_number, o.referral_date
            ORDER BY o.referral_date DESC
        ) AS rn

    FROM warehouse.fact_oncology_pathway o
    WHERE o.referral_date IS NOT NULL
)

SELECT
    nhs_number,
    referral_date,
    first_booking_date,
    first_clinic_date,
    appointment_attendance_status

FROM oncology_clean
WHERE rn = 1;
