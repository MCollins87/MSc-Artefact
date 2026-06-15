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
    -- BOOKING
    -- =====================
    b_first.booking_due_date     AS first_booking_date,
    b_latest.booking_status      AS latest_booking_status,

    -- =====================
    -- ECAD (before + after)
    -- =====================
    ecad_pre.ecad_date  AS ecad_pre_referral,
    ecad_post.ecad_date AS ecad_post_referral,

    -- =====================
    -- CT + TREATMENT
    -- =====================
    ct.ct_date,
    t.first_treat_date,

    -- =====================
    -- CONTEXT
    -- =====================
    r.diagnosis_icd10,
    r.oncologist,

    -- =====================
    -- INTERVALS
    -- =====================

    -- Oncology → RT
    DATE_PART('day', r.rt_referral_date - o.referral_date) AS days_oncology_to_rt,

    -- RT pathway
    DATE_PART('day', b_first.booking_due_date - r.rt_referral_date) AS days_rt_to_booking,
    DATE_PART('day', ecad_post.ecad_date - r.rt_referral_date) AS days_rt_to_ecad,
    DATE_PART('day', ct.ct_date - r.rt_referral_date) AS days_rt_to_ct,
    DATE_PART('day', t.first_treat_date - r.rt_referral_date) AS days_rt_to_treat,

    -- CT → Treat
    DATE_PART('day', t.first_treat_date - ct.ct_date) AS days_ct_to_treat,

    -- =====================
    -- OPERATIONAL FLAGS
    -- =====================

    -- Active pathway
    CASE WHEN t.first_treat_date IS NULL THEN 1 ELSE 0 END AS is_active_pathway,

    -- Booking open
    CASE
        WHEN b_latest.booking_status NOT IN ('Completed', 'Cancelled')
             OR b_latest.booking_status IS NULL
        THEN 1 ELSE 0
    END AS booking_open_flag,

    -- Overdue (62-day style proxy)
    CASE
        WHEN t.first_treat_date IS NULL
        AND r.rt_referral_date < CURRENT_DATE - INTERVAL '62 days'
        THEN 1 ELSE 0
    END AS overdue_62_day,

    CURRENT_TIMESTAMP AS load_timestamp

FROM warehouse.int_rt_referral r

-- =====================
-- BOOKING (first after)
-- =====================
LEFT JOIN LATERAL (
    SELECT b.booking_due_date
    FROM warehouse.int_rt_booking_events b
    WHERE b.r_number = r.r_number
      AND b.booking_due_date >= r.rt_referral_date
    ORDER BY b.booking_due_date
    LIMIT 1
) b_first ON TRUE

-- Latest booking status
LEFT JOIN LATERAL (
    SELECT b.booking_status
    FROM warehouse.int_rt_booking_events b
    WHERE b.r_number = r.r_number
    ORDER BY b.booking_due_date DESC
    LIMIT 1
) b_latest ON TRUE

-- =====================
-- ECAD
-- =====================
LEFT JOIN LATERAL (
    SELECT e.ecad_date
    FROM warehouse.int_rt_ecad_events e
    WHERE e.r_number = r.r_number
      AND e.ecad_date <= r.rt_referral_date
    ORDER BY e.ecad_date DESC
    LIMIT 1
) ecad_pre ON TRUE

LEFT JOIN LATERAL (
    SELECT e.ecad_date
    FROM warehouse.int_rt_ecad_events e
    WHERE e.r_number = r.r_number
      AND e.ecad_date >= r.rt_referral_date
    ORDER BY e.ecad_date
    LIMIT 1
) ecad_post ON TRUE

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
    SELECT t.first_treat_date
    FROM warehouse.int_rt_treat_events t
    WHERE t.r_number = r.r_number
      AND t.first_treat_date >= r.rt_referral_date
    ORDER BY t.first_treat_date
    LIMIT 1
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