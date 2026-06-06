DROP TABLE IF EXISTS warehouse.fact_oncology_pathway;

CREATE TABLE warehouse.fact_oncology_pathway AS
SELECT
    s.nhs_number,
    s.r_number,
    s.tumour_site,
    s.oncologist,
    s.referral_source,
    s.delay_reason,
    s.clinic_type,
	s.no_opa,

    -- Core dates
    s.date_referred,
    s.clinic_date,
    ct.ct_date,
    t.first_treat_date,


    -- ========================
    -- Referral-based intervals
    -- ========================
    (s.clinic_date::DATE - s.date_referred::DATE) AS days_referral_to_clinic,
    (r.rt_referral_date::DATE - s.date_referred::DATE) AS days_referral_to_rt_ref,
    (ct.ct_date::DATE - s.date_referred::DATE) AS days_referral_to_ct,
    (t.first_treat_date::DATE - s.date_referred::DATE) AS days_referral_to_treatment,

    -- ========================
    -- Clinic-based intervals
    -- ========================
    (r.rt_referral_date::DATE - s.clinic_date::DATE) AS days_clinic_to_rt_ref,

    -- ========================
    -- RT referral-based intervals
    -- ========================
    (ct.ct_date::DATE - r.rt_referral_date::DATE) AS days_rt_ref_to_ct,
    (t.first_treat_date::DATE - r.rt_referral_date::DATE) AS days_rt_ref_to_treatment,

    -- ========================
    -- Existing intervals (keep for continuity)
    -- ========================
    (ct.ct_date::DATE - s.clinic_date::DATE) AS days_clinic_to_ct,
    (t.first_treat_date::DATE - ct.ct_date::DATE) AS days_ct_to_treat,

    -- ========================
    -- Breach metrics (critical)
    -- ========================
    (31 - (t.first_treat_date::DATE - s.clinic_date::DATE)) AS days_to_31_breach,
    (62 - (t.first_treat_date::DATE - s.date_referred::DATE)) AS days_to_62_breach,

    CASE 
        WHEN (t.first_treat_date::DATE - s.clinic_date::DATE) > 31 THEN 1 ELSE 0
    END AS breach_31,

    CASE 
        WHEN (t.first_treat_date::DATE - s.date_referred::DATE) > 62 THEN 1 ELSE 0
    END AS breach_62,

    CURRENT_TIMESTAMP AS load_timestamp

FROM staging.stg_oncology_intake s

-- RT referral
LEFT JOIN staging.stg_aria_rt_referral r
    ON s.nhs_number = r.nhs_number
    AND r.rt_referral_date >= s.clinic_date

-- CT
LEFT JOIN staging.stg_aria_ct ct
    ON s.nhs_number = ct.nhs_number
    AND ct.ct_date >= COALESCE(r.rt_referral_date, s.clinic_date)

-- Treatment (robust fallback join)
LEFT JOIN staging.stg_aria_treat t
    ON s.nhs_number = t.nhs_number
    AND t.first_treat_date >= COALESCE(ct.ct_date, r.rt_referral_date, s.clinic_date)

-- Scope control
-- WHERE s.clinic_type = 'Clinical Oncology';