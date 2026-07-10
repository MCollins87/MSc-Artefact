
DROP TABLE IF EXISTS warehouse.fact_oncology_pathway;

CREATE TABLE warehouse.fact_oncology_pathway AS

SELECT
    s.nhs_number,
    s.r_number,
    s.oncologist,
    s.speciality_referred,
    s.no_opa,
    s.clinic_type,

    -- Core dates
    s.date_referred AS referral_date,
    s.date_received,
    -- s.date_triaged,
    -- s.clinic_date AS first_clinic_date,
    c.first_booking_date,
    c.first_appointment_date AS first_clinic_date,
    c.appointment_attendance_status,

    -- Time dimensions
    DATE_TRUNC('month', s.date_referred)::DATE AS referral_month,
    DATE_TRUNC('week', s.date_referred)::DATE AS referral_week,

    -- Flags
    CASE WHEN c.first_appointment_date IS NOT NULL THEN 1 ELSE 0 END AS has_clinic,

    -- Metrics
    CASE
        WHEN c.first_appointment_date IS NOT NULL 
        THEN (
            c.first_appointment_date::DATE - s.date_referred::DATE
        )
    END AS days_to_clinic,

    -- Intake stage intervals
    (s.date_received::DATE - s.date_referred::DATE) AS days_referral_to_received,
    (c.first_booking_date::DATE - s.date_received::DATE) AS days_received_to_triage,
    (c.first_appointment_date::DATE - c.first_booking_date::DATE) AS days_triage_to_clinic,

    CURRENT_TIMESTAMP AS load_timestamp

FROM staging.stg_oncology_intake s

LEFT JOIN warehouse.int_oncology_clinic_events c
    ON c.nhs_number = s.nhs_number

WHERE s.date_referred IS NOT NULL;

