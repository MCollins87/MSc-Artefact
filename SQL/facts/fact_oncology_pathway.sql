
DROP TABLE IF EXISTS warehouse.fact_oncology_pathway;

CREATE TABLE warehouse.fact_oncology_pathway AS

SELECT
    s.nhs_number,
    s.r_number,
    s.oncologist,
    s.tumour_site,
    s.no_opa,
    s.clinic_type,

    -- Core dates
    s.date_referred AS referral_date,
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

    CURRENT_TIMESTAMP AS load_timestamp

FROM staging.stg_oncology_intake s
WHERE s.date_referred IS NOT NULL;