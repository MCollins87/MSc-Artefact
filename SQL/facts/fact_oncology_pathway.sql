
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
    s.date_triaged,
    s.clinic_date AS first_clinic_date,

    -- Time dimensions
    DATE_TRUNC('month', s.date_referred)::DATE AS referral_month,
    DATE_TRUNC('week', s.date_referred)::DATE AS referral_week,

    -- Flags
    CASE WHEN s.clinic_date IS NOT NULL THEN 1 ELSE 0 END AS has_clinic,

    -- Metrics
    CASE
        WHEN s.clinic_date IS NOT NULL
        THEN (s.clinic_date::DATE - s.date_referred::DATE)
    END AS days_to_clinic,

    -- Intake stage intervals
    (s.date_received::DATE - s.date_referred::DATE) AS days_referral_to_received,
    (s.date_triaged::DATE - s.date_received::DATE) AS days_received_to_triage,
    (s.clinic_date::DATE - s.date_triaged::DATE) AS days_triage_to_clinic,

    CURRENT_TIMESTAMP AS load_timestamp

FROM staging.stg_oncology_intake s
WHERE s.date_referred IS NOT NULL;