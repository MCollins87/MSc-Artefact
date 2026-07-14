
DROP TABLE IF EXISTS warehouse.fact_oncology_pathway;

CREATE TABLE warehouse.fact_oncology_pathway AS
WITH BASE AS(
SELECT
    s.nhs_number,
    s.r_number,
    s.oncologist,
    s.speciality_referred,
    s.no_opa,
    s.clinic_type,
    s.referral_source,
    -- c.clinic_speciality,
    clinic.ref_to_local_code AS clinic_speciality,

    -- Core dates
    s.date_referred AS referral_date,
    s.date_received,
    clinic.first_booking_date,
    clinic.first_clinic_date,
    clinic.appointment_attendance_status,

    -- Time dimensions
    DATE_TRUNC('month', s.date_referred)::DATE AS referral_month,
    DATE_TRUNC('week', s.date_referred)::DATE AS referral_week,

    -- Flags
    CASE WHEN clinic.first_clinic_date IS NOT NULL THEN 1 ELSE 0 END AS has_clinic,
    CASE 
        WHEN clinic.first_clinic_date IS NULL
            AND no_opa IS NULL
        THEN 1
        ELSE 0
    END AS active_referral_flag,

    -- Metrics
    CASE
        WHEN clinic.first_clinic_date IS NOT NULL 
        THEN (
            clinic.first_clinic_date::DATE - s.date_referred::DATE
        )
    END AS days_to_clinic,

    CASE
        WHEN clinic.first_clinic_date IS NOT NULL 
        THEN (
            clinic.first_clinic_date::DATE - s.date_referred::DATE
        )
        ELSE (
            CURRENT_DATE - s.date_referred::DATE
        )
    END AS current_wait_days,
    
    -- Intake stage intervals
    
    -- (s.date_received::DATE - s.date_referred::DATE) AS days_referral_to_received,
    (COALESCE(s.date_received::DATE, s.date_referred::DATE) - s.date_referred::DATE) AS days_referral_to_recieved,
    (clinic.first_booking_date::DATE - COALESCE(s.date_received::DATE, s.date_referred::DATE)) AS days_received_to_triage,
    (clinic.first_clinic_date::DATE - clinic.first_booking_date::DATE) AS days_triage_to_clinic,

    CURRENT_TIMESTAMP AS load_timestamp

FROM staging.stg_oncology_intake s

LEFT JOIN LATERAL (
    SELECT
        c.booking_date AS first_booking_date,
        c.appointment_date AS first_clinic_date,
        c.appointment_attendance_status,
        c.ref_to_local_code
    FROM staging.oncology_clinic c
    WHERE REPLACE(c.nhs_number, ' ', '') = REPLACE(s.nhs_number, ' ', '')
    AND c.booking_date >= COALESCE(s.date_received, s.date_referred)
    ORDER BY c.booking_date
    LIMIT 1
) clinic ON TRUE

-- LEFT JOIN warehouse.int_oncology_clinic_events c
--     ON REPLACE(c.nhs_number, ' ', '') = REPLACE(s.nhs_number, ' ', '')

WHERE s.date_referred IS NOT NULL
)


SELECT
    *,

    CASE
        WHEN current_wait_days <= 14 THEN 'GREEN'
        WHEN current_wait_days <= 21 THEN 'AMBER'
        ELSE 'RED'
    END AS clinic_rag
FROM base;