DROP TABLE IF EXISTS warehouse.fact_rt_pathway;

CREATE TABLE warehouse.fact_rt_pathway AS

SELECT
    -- =====================
    -- KEYS
    -- =====================
    MD5(r.nhs_number || r.rt_referral_date::TEXT) AS rt_pathway_id,
    r.r_number,
    r.nhs_number,

    -- =====================
    -- CORE EVENT
    -- =====================
    r.rt_referral_date,

    -- =====================
    -- ONCOLOGY CONTEXT (closest BEFORE)
    -- =====================
    o.referral_date       AS oncology_referral_date,
    o.first_clinic_date   AS oncology_clinic_date,



    -- =====================
    -- ECAD (before + after)
    -- =====================
    
    ecad.ecad_date AS ecad_referral_date, -- clock start

    -- =====================
    -- CT + TREATMENT
    -- =====================
    ct.ct_date,
    t.first_completed_treat_date,

    -- =====================
    -- CONTEXT
    -- =====================
    r.diagnosis_icd10,
    r.oncologist,
    b_complete.rcr_category,

    -- =====================
    -- INTERVALS
    -- =====================

    -- Oncology → RT
    DATE_PART('day', r.rt_referral_date - o.referral_date) AS days_oncology_to_rt,

    -- RT pathway
    DATE_PART('day', r.rt_referral_date - ecad.ecad_date) AS days_ecad_to_referral,
    DATE_PART('day', b_complete.booking_completed_date - r.rt_referral_date) AS days_rt_to_booking,
    DATE_PART('day', ecad.ecad_date - r.rt_referral_date) AS days_rt_to_ecad,
    DATE_PART('day', ct.ct_date - r.rt_referral_date) AS days_rt_to_ct,
    DATE_PART('day', t.first_completed_treat_date - r.rt_referral_date) AS days_rt_to_treat,
    DATE_PART('day', t.first_completed_treat_date - ecad.ecad_date) AS days_ecad_to_treat,

    -- CT → Treat
    DATE_PART('day', t.first_completed_treat_date - ct.ct_date) AS days_ct_to_treat,

    -- ====================
    -- RCR Performance
    -- ====================


   
     t_dim.target_days AS RCR_target_days,


CASE  
    WHEN t.first_completed_treat_date IS NULL THEN NULL  
    WHEN ecad.ecad_date IS NULL THEN NULL  
    WHEN DATE_PART('day', t.first_completed_treat_date - ecad.ecad_date) <= t_dim.target_days  
    THEN 1 ELSE 0  
END AS rcr_within_target_flag,



CASE  
    WHEN t.first_completed_treat_date IS NULL 
         OR ecad.ecad_date IS NULL THEN NULL  
    ELSE DATE_PART('day', t.first_completed_treat_date - ecad.ecad_date) - t_dim.target_days  
END AS rcr_breach_days,


CASE  
    WHEN ecad.ecad_date IS NULL THEN 'No ECAD'  
    WHEN COALESCE(t.has_completed,0) = 0 THEN 'Not Treated'  
    WHEN DATE_PART('day', t.first_completed_treat_date - ecad.ecad_date) - t_dim.target_days <= 0 THEN 'Within Target'  
    WHEN DATE_PART('day', t.first_completed_treat_date - ecad.ecad_date) - t_dim.target_days <= 7 THEN 'Minor Breach'  
    ELSE 'Major Breach'  
END AS rcr_performance_band,



    -- =====================
    -- OPERATIONAL FLAGS
    -- =====================

    -- Active pathway
    CASE 
        WHEN COALESCE(t.has_completed,0) = 1 THEN 0
        WHEN COALESCE(t.has_active_booking,0) = 1 THEN 1
        ELSE 0
    END AS is_active_pathway,

    CASE
        -- Treated
        WHEN COALESCE(t.has_completed,0) = 1 THEN 'Treated'
        -- Active: booking completed AND future treatment exists
        WHEN b_complete.booking_completed_date IS NOT NULL
            AND EXISTS(
                SELECT 1
                FROM warehouse.int_rt_treat_events t2
                WHERE t2.r_number = r.r_number
                AND t2.first_treat_date > b_complete.booking_completed_date
            )
        THEN 'Active'
        -- Not Treated: Booking done but nothing after
        WHEN b_complete.booking_completed_date IS NOT NULL
        THEN 'Not Treated'
        -- Awaiting booking
        ELSE 'Awaiting RT Booking'
    END AS rt_pathway_status,

    CASE
        WHEN COALESCE(t.has_completed,0) = 1 THEN 1 ELSE 0
    END AS treated_flag,

    -- Booking open
    CASE
        WHEN b_complete.booking_completed_date IS NULL
        THEN 1 ELSE 0
    END AS booking_open_flag,

    -- Overdue (62-day style proxy)
    CASE
        WHEN t.first_completed_treat_date IS NULL
        AND r.rt_referral_date < CURRENT_DATE - INTERVAL '62 days'
        THEN 1 ELSE 0
    END AS overdue_62_day,

    CURRENT_TIMESTAMP AS load_timestamp

FROM warehouse.int_rt_referral r

-- =====================
-- BOOKING (first after)
-- =====================
LEFT JOIN warehouse.int_rt_booking_events b_complete
ON b_complete.r_number = r.r_number


LEFT JOIN warehouse.dim_rcr_targets t_dim  
    ON b_complete.rcr_category = t_dim.rcr_category  



-- =====================
-- ECAD
-- =====================
LEFT JOIN LATERAL (
    SELECT e.ecad_date
    FROM warehouse.int_rt_ecad_events e
    WHERE e.r_number = r.r_number
    ORDER BY ABS(EXTRACT(EPOCH FROM (e.ecad_date - r.rt_referral_date)))
    LIMIT 1
) ecad ON TRUE

-- =====================
-- CT
-- =====================
LEFT JOIN LATERAL (
    SELECT ct.ct_date
    FROM warehouse.int_rt_ct_events ct
    WHERE ct.r_number = r.r_number
      AND ct.ct_date >= r.rt_referral_date
    ORDER BY ct.ct_date
    LIMIT 1
) ct ON TRUE

-- =====================
-- TREATMENT
-- =====================
LEFT JOIN LATERAL (
    SELECT
        MAX(CASE WHEN appointment_status_group = 'Completed' THEN 1 ELSE 0 END) AS has_completed,
        MAX(CASE
            WHEN appointment_status_group IN ('Open', 'In Progress')
            THEN 1 ELSE 0 END) AS has_active_booking,
        MAX(CASE
            WHEN appointment_status_group = 'Cancelled'
            THEN 1 ELSE 0 END) AS has_cancelled,
        MIN(CASE
            WHEN appointment_status_group = 'Completed'
            THEN first_treat_date END) AS first_completed_treat_date
    FROM warehouse.int_rt_treat_events t
    WHERE t.r_number = r.r_number
        AND t.first_treat_date >= r.rt_referral_date
) t ON TRUE

-- =====================
-- ONCOLOGY
-- =====================
LEFT JOIN LATERAL (
    SELECT o.referral_date, o.first_clinic_date
    FROM warehouse.int_oncology_events o
    WHERE o.nhs_number = r.nhs_number
      AND o.referral_date <= r.rt_referral_date
    ORDER BY o.referral_date DESC
    LIMIT 1
) o ON TRUE;