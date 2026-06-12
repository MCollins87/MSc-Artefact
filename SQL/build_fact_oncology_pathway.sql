DROP TABLE IF EXISTS warehouse.fact_oncology_pathway;

CREATE TABLE warehouse.fact_oncology_pathway AS
SELECT
    s.nhs_number,
    s.pas_number,
    s.oncologist
    s.tumour_site,

    -- Core Dates
    s.date_referred,
    s.clinic_date,

    -- RT linkage
    -- Only used ot identify Portsmouth linked RT
    MIN(r.rt_referral_date) AS rt_referral_date,

    -- Time dimensions
    DATE_TRUNC('month', s.date_referred)::DATE AS referral_month,
    DATE_TRUNC('week', s.date_referred)::DATE AS referral_week,

    -- Flags
    CASE WHEN s.date_referred IS NOT NULL THN 1 ELSE 0 END AS is_referral,
    CASE WHEN s.clinic_date IS NOT NULL THEN 1 ELSE 0 END AS has_clinic,
    CASE WHEN MIN(r.rt_referral_date) IS NOT NULL THEN 1 ELSE 0 END AS has_rt_referral,

    -- Pathway metrics
    CASE
        WHEN s.clinic_date IS NOT NULL THEN
            (s.clinic_date::DATE - s.date_referred::DATE)
    END AS days to clinic,

    
CASE
        WHEN MIN(r.rt_referral_date) IS NOT NULL THEN
            (MIN(r.rt_referral_date)::DATE - s.date_referred::DATE)
    END AS days_to_rt,

    -- ========================
    -- Metadata
    -- ========================
    CURRENT_TIMESTAMP AS load_timestamp

FROM staging.stg_oncology_intake s

LEFT JOIN staging.stg_aria_rt_referral r
    ON s.nhs_number = r.nhs_number
    AND r.rt_referral_date >= s.date_referred 

GROUP BY
    s.nhs_number,
    s.pas_number,
    s.oncologist,
    s.tumour_site,
    s.date_referred,
    s.clinic_date;
