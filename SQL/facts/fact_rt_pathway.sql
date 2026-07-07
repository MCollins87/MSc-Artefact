DROP TABLE IF EXISTS warehouse.fact_rt_pathway;

CREATE TABLE warehouse.fact_rt_pathway AS
WITH base_raw AS(
    SELECT
        r.*,
        LEFT(REPLACE(UPPER(r.diagnosis_icd10), '.', ''),3) AS icd_prefix,
    
    LEAD(r.rt_referral_date) Over (
        PARTITION BY r.nhs_number
        ORDER BY r.rt_referral_date
    ) AS next_rt_referral_date

    FROM warehouse.int_rt_referral r
),

base AS (
    SELECT
        -- KEYS
        MD5(r.nhs_number || r.rt_referral_date::TEXT) AS rt_pathway_id,
        r.r_number,
        r.nhs_number,

        -- CORE
        r.rt_referral_date,


        -- ONCOLOGY
        o.referral_date AS oncology_referral_date,
        o.first_clinic_date AS oncology_clinic_date,
        o.speciality_referred,

        -- EVENTS
        ecad.ecad_date AS ecad_referral_date,
        ct.ct_date,
        t.first_completed_treat_date,
        t.next_treatment_date,

        -- CONTEXT
        r.diagnosis_icd10,
        r.icd_prefix,
        r.oncologist,
        b_complete.rcr_category,
        t_dim.target_days,
        b_complete.booking_completed_date,
        t.activity_note,

        CASE
            WHEN r.diagnosis_icd10 IS NULL THEN 'Missing ICD'
            WHEN tg.tumour_group IS NULL THEN 'Unmapped'
            ELSE tg.tumour_group
        END AS tumour_group,

        -- FLAGS FROM TREATMENT
        COALESCE(t.has_completed,0) AS has_completed,
        COALESCE(t.has_active_booking,0) AS has_active_booking,
        COALESCE(t.has_cancelled,0) AS has_cancelled

    FROM base_raw r

    LEFT JOIN warehouse.int_rt_booking_events b_complete
        ON b_complete.r_number = r.r_number

    LEFT JOIN warehouse.dim_rcr_targets t_dim  
        ON b_complete.rcr_category = t_dim.rcr_category  

    -- ECAD

    LEFT JOIN LATERAL (
        SELECT e.ecad_date
        FROM warehouse.int_rt_ecad_events e
        WHERE e.r_number = r.r_number
        AND e.ecad_date >= r.rt_referral_date - INTERVAL '7 days'
        AND (
            r.next_rt_referral_date IS NULL
            OR e.ecad_date < r.next_rt_referral_date
        )
        ORDER BY e.ecad_date DESC
        LIMIT 1
    ) ecad ON TRUE


    -- CT
    LEFT JOIN LATERAL (
        SELECT ct.ct_date
        FROM warehouse.int_rt_ct_events ct
        WHERE ct.r_number = r.r_number
          AND ct.ct_date >= r.rt_referral_date
          AND(
            r.next_rt_referral_date IS NULL
            OR ct.ct_date < r.next_rt_referral_date
          )
        ORDER BY ct.ct_date
        LIMIT 1
    ) ct ON TRUE

    -- TREATMENT
    LEFT JOIN LATERAL (
        SELECT
            MAX(CASE WHEN appointment_status_group = 'Completed' THEN 1 ELSE 0 END) AS has_completed,
            MAX(CASE WHEN appointment_status_group IN ('Open','In Progress') THEN 1 ELSE 0 END) AS has_active_booking,
            MIN(CASE WHEN appointment_status_group = 'Completed' THEN first_treat_date END) AS first_completed_treat_date,
            MAX(CASE WHEN appointment_status_group ILIKE 'Cancelled%' THEN 1 ELSE 0 END) AS has_cancelled,
            MIN(CASE WHEN appointment_status_group IN ('Open','In Progress') THEN first_treat_date END) AS next_treatment_date,
            MAX(CASE WHEN appointment_status_group IN ('Open','In Progress') THEN activity_note END) AS activity_note
        FROM warehouse.int_rt_treat_events t
        WHERE t.r_number = r.r_number
          AND t.first_treat_date >= r.rt_referral_date
          AND (
            r.next_rt_referral_date IS NULL
            OR t.first_treat_date < r.next_rt_referral_date
          )
    ) t ON TRUE

    -- ONCOLOGY

    LEFT JOIN LATERAL (
        SELECT 
            o.referral_date, 
            o.first_clinic_date,
            fo.speciality_referred
        FROM warehouse.int_oncology_events o
        LEFT JOIN warehouse.fact_oncology_pathway fo
            ON fo.nhs_number = o.nhs_number
        AND fo.referral_date = o.referral_date
        WHERE o.nhs_number = r.nhs_number
        AND o.referral_date <= r.rt_referral_date
        ORDER BY o.referral_date DESC
        LIMIT 1
    ) o ON TRUE


    -- Tumour group
    LEFT JOIN LATERAL(
        SELECT m.tumour_group
        FROM warehouse.dim_icd10_mapping m
        WHERE r.icd_prefix BETWEEN m.code_start AND m.code_end
        AND m.include_flag = 1
        ORDER BY m.priority
        LIMIT 1
    ) tg ON TRUE
)

, enriched AS (
SELECT
    *,

    -- =====================
    -- PATHWAY STATUS
    -- =====================
    CASE
        WHEN ct_date IS NOT NULL THEN 1
        ELSE 0
    END AS has_ct_flag,
    
    CASE
        WHEN has_completed = 1 THEN 'Treated'
        WHEN has_cancelled = 1 AND has_active_booking = 0 THEN 'Closed - Cancelled'
        WHEN has_active_booking = 1 THEN 'Active'
        WHEN has_completed = 0 
         AND has_active_booking = 0
         AND booking_completed_date IS NOT NULL
        THEN 'Closed - No Treatment'
        ELSE 'Awaiting Booking'
    END AS rt_pathway_status,

    CASE
        WHEN has_completed = 1 THEN 0
        WHEN has_active_booking = 1 THEN 1
        WHEN has_cancelled = 1 AND has_active_booking = 0 THEN 0
        ELSE 0
    END AS is_active_pathway,

    CASE
        WHEN DATE_PART('day', first_completed_treat_date - oncology_referral_date) <=62
        THEN 1 ELSE 0
    END AS cwt_62_day_flag,

    CASE
        WHEN DATE_PART('day', first_completed_treat_date - rt_referral_date) <= 31
        THEN 1 ELSE 0
    END AS cwt_31_day_flag,

    

    -- =====================
    -- INTERVALS
    -- =====================
    DATE_PART('day', next_treatment_date - COALESCE(ecad_referral_date, rt_referral_date)) AS days_ecad_to_treatment,
    CASE 
        WHEN oncology_clinic_date >= oncology_referral_date
        THEN DATE_PART('day', oncology_clinic_date - oncology_referral_date)
        ELSE NULL
    END AS days_onc_to_clinic,
    CASE
        WHEN rt_referral_date >= oncology_clinic_date
        THEN DATE_PART('day', rt_referral_date - oncology_clinic_date)
        ELSE NULL
    END AS days_clinic_to_rt,
    GREATEST(DATE_PART('day', rt_referral_date - oncology_referral_date), 0) AS days_oncology_to_rt,
    CASE
        WHEN booking_completed_date >= rt_referral_date
        THEN DATE_PART('day', booking_completed_date - rt_referral_date)
        ELSE NULL
    END AS days_rt_to_booking,
    CASE
        WHEN ct_date >= rt_referral_date
        THEN DATE_PART('day', ct_date - rt_referral_date)
        ELSE NULL
    END AS days_rt_to_ct,
    CASE 
        WHEN ct_date >= booking_completed_date
        THEN DATE_PART('day', ct_date - booking_completed_date)
        ELSE NULL
    END AS days_booking_to_ct,
    CASE
        WHEN first_completed_treat_date >= rt_referral_date
        THEN DATE_PART('day', first_completed_treat_date - rt_referral_date)
        ELSE NULL
    END AS days_rt_to_treat,
    CASE
        WHEN first_completed_treat_date >= ecad_referral_date
        THEN DATE_PART('day', first_completed_treat_date - ecad_referral_date)
        ELSE NULL
    END AS days_ecad_to_treat,
    CASE
        WHEN first_completed_treat_date >= ct_date
        THEN DATE_PART('day', first_completed_treat_date - ct_date)
        ELSE NULL
    END AS days_ct_to_treat

FROM base
)

SELECT
    *,

    -- =====================
    -- HISTORIC PERFORMANCE (TREATED ONLY)
    -- =====================
    CASE  
        WHEN has_completed = 1
         AND ecad_referral_date IS NOT NULL
         AND DATE_PART('day', first_completed_treat_date - ecad_referral_date) <= target_days
        THEN 1 
        WHEN has_completed = 1 THEN 0
        ELSE NULL
    END AS rcr_within_target_flag,

    CASE  
        WHEN has_completed = 1
         AND ecad_referral_date IS NOT NULL
        THEN DATE_PART('day', first_completed_treat_date - ecad_referral_date) - target_days
        ELSE NULL  
    END AS rcr_breach_days,

    CASE  
        WHEN has_completed = 0 THEN NULL
        WHEN ecad_referral_date IS NULL THEN 'No ECAD'
        WHEN DATE_PART('day', first_completed_treat_date - ecad_referral_date) - target_days <= 0 THEN 'Within Target'
        WHEN DATE_PART('day', first_completed_treat_date - ecad_referral_date) - target_days <= 7 THEN 'Minor Breach'
        ELSE 'Major Breach'
    END AS rcr_performance_band,



    -- =====================
    -- FUTURE RISK (ACTIVE ONLY)
    -- =====================
    CASE
        WHEN has_completed = 0
         AND has_active_booking = 1
         AND ecad_referral_date IS NOT NULL
         AND booking_completed_date IS NOT NULL
         AND DATE_PART('day', booking_completed_date - ecad_referral_date) > target_days
        THEN 1 ELSE 0
    END AS predicted_breach_flag,

    CASE
        WHEN has_completed = 0
         AND has_active_booking = 1
         AND ecad_referral_date IS NOT NULL
         AND booking_completed_date IS NOT NULL
        THEN DATE_PART('day', booking_completed_date - ecad_referral_date) - target_days
        ELSE NULL
    END AS predicted_breach_days,

    CASE
        WHEN has_completed = 0
        AND DATE_PART('day', CURRENT_DATE - COALESCE(ecad_referral_date, rt_referral_date)) > target_days
        THEN 1 ELSE 0
    END AS active_rcr_breach_flag,

    CASE
        WHEN has_completed = 0 THEN
        DATE_PART('day', CURRENT_DATE - COALESCE(ecad_referral_date, rt_referral_date))
        ELSE NULL
    END AS active_days_since_ECAD,

    CASE
        WHEN next_treatment_date IS NULL
        THEN 'Unbooked'
        WHEN DATE_PART('day', next_treatment_date - COALESCE(ecad_referral_date, rt_referral_date)) <= target_days
        THEN 'GREEN'
        WHEN DATE_PART('day', next_treatment_date - COALESCE(ecad_referral_date, rt_referral_date)) <= 31
        THEN 'AMBER'
        ELSE 'RED'
    END AS booking_rag_status,


    -- =====================
    -- OVERDUE (ACTIVE ONLY)
    -- =====================
    CASE
        WHEN has_completed = 0
         AND has_active_booking = 1
         AND rt_referral_date < CURRENT_DATE - INTERVAL '62 days'
        THEN 1 ELSE 0
    END AS overdue_62_day,

    -- =====================
    -- SEGMENTATION FLAGS
    -- =====================
    CASE
        WHEN has_completed = 1 THEN 'Historic'
        WHEN has_active_booking = 1 THEN 'Active'
        ELSE 'Exclude'
    END AS performance_group,

    CASE
        WHEN has_completed = 1 THEN 1
        WHEN has_active_booking = 1 THEN 1
        ELSE 0
    END AS include_in_analysis_flag,

    CASE WHEN has_completed = 1 THEN 1 ELSE 0 END AS treated_flag,

    CASE
        WHEN booking_completed_date IS NULL THEN 1 ELSE 0
    END AS booking_open_flag,

    CASE
        WHEN has_completed = 0
        AND 62 - DATE_PART('day', CURRENT_DATE - oncology_referral_date) < 0
        THEN 1 ELSE 0
    END AS currently_breaching_62_flag,

    -- NHS Targets
    DATE_PART('day', first_completed_treat_date - oncology_referral_date) AS days_oncology_to_treatment,
    DATE_PART('day', first_completed_treat_date - rt_referral_date) AS days_rt_to_treatment,
    
    CASE
        WHEN DATE_PART('day', first_completed_treat_date - rt_referral_date) > 31
        AND ecad_referral_date IS NOT NULL
        AND DATE_PART('day', first_completed_treat_date - ecad_referral_date) <= target_days
        THEN 1 ELSE 0
    END AS valid_clinical_delay_flag,


    -- Live Operations
    CASE
        WHEN has_completed = 0 THEN
            62 - DATE_PART('day', CURRENT_DATE - oncology_referral_date)
        ELSE NULL
    END AS days_to_62_breach,

    CASE
        WHEN has_completed = 0 THEN
            target_days - DATE_PART('day', CURRENT_DATE - COALESCE(ecad_referral_date, rt_referral_date))
    END AS days_to_rcr_breach,

    COALESCE(ecad_referral_date, rt_referral_date) AS operational_start_date,

    CASE
        WHEN has_completed = 1
            THEN 'Completed'
        WHEN DATE_PART('day', CURRENT_DATE - COALESCE(ecad_referral_date, rt_referral_date)) > target_days
            THEN 'Breaching'
        WHEN DATE_PART('day', CURRENT_DATE - COALESCE(ecad_referral_date, rt_referral_date)) > target_days - 7
            THEN 'At Risk'
        ELSE 'Within Target'
    END AS operational_risk_group,



    CURRENT_TIMESTAMP AS load_timestamp

FROM enriched;