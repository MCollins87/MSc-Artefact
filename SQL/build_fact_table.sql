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
    r.rt_referral_date,

    -- Wek start dates

    DATE_TRUNC('week', s.date_referred)::DATE AS referral_week_start,
    
    CASE
        WHEN r.rt_referral_date IS NOT NULL
        THEN DATE_TRUNC('week', r.rt_referral_date)::DATE 
    END AS rt_referral_week_start,


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

    -- ========================
    -- Breach Risks (Open pathways)
    -- ========================

    CASE
        WHEN s.no_opa IS NOT NULL THEN
            (s.date_triaged::DATE - s.date_referred::DATE)
        
        WHEN s.clinic_date IS NULL OR s.no_opa IS NULL THEN
            (CURRENT_DATE - s.date_referred::DATE)
        
        ELSE
            (s.clinic_date::DATE - s.date_referred::DATE)
    END AS pathway_days,

    CASE
        WHEN s.no_opa IS NOT NULL THEN 'Closed'

        WHEN s.clinic_date IS NULL AND s.no_opa IS NULL THEN 'Active'

        ELSE 'Progressed'
    END AS pathway_status,

    -- ======================
    -- Pathway Flags
    -- ======================
    CASE WHEN s.date_referred IS NOT NULL THEN 1 ELSE 0 END AS has_referral,

    CASE WHEN s.clinic_date IS NOT NULL THEN 1 ELSE 0 END AS has_clinic,

    CASE WHEN r.rt_referral_date IS NOT NULL THEN 1 ELSE 0 END AS has_rt_referral,

    CASE WHEN t.first_treat_date IS NOT NULL THEN 1 ELSE 0 END AS has_treatment,

    CASE
        WHEN s.clinic_date IS NOT NULL AND r.rt_referral_date IS NOT NULL
        THEN 1 ELSE 0
    END AS clinic_to_rt_conversion,

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