DROP TABLE IF EXISTS warehouse.fact_oncology_pathway;

CREATE TABLE warehouse.fact_oncology_pathway AS
WITH base AS (
    SELECT
        -- Patient details and context
        s.nhs_number,
        s.r_number,
        s.oncologist,
        s.speciality_referred,
        s.no_opa,
        s.referral_source,
        s.clinic_type,
        clinic.ref_to_local_code AS clinic_speciality,

        -- Core Dates
        s.date_referred AS referral_date,
        s.date_received,
        clinic.first_booking_date,
        clinic.first_clinic_date,
        clinic.appointment_attendance_status,

        -- Time dimensions
        DATE_TRUNC('month', s.date_referred)::DATE AS referral_month,
        DATE_TRUNC('week', s.date_referred)::DATE AS referral_week,

        -- Core intervals
        (COALESCE(s.date_received::DATE, s.date_referred) - s.date_referred::DATE) AS days_referral_to_received,
        GREATEST(clinic.first_booking_date::DATE - COALESCE(s.date_received::DATE, s.date_referred::DATE), 0) AS days_received_to_triage,
        (clinic.first_clinic_date::DATE - clinic.first_booking_date::DATE) AS days_triage_to_clinic,

        CASE
            WHEN clinic.first_clinic_date IS NOT NULL
            THEN (clinic.first_clinic_date::DATE - s.date_referred::DATE)
        END AS days_to_clinic,

        CASE
            WHEN clinic.first_clinic_date IS NOT NULL
            THEN (clinic.first_clinic_date::DATE - s.date_referred::DATE)
            ELSE (CURRENT_DATE - s.date_referred::DATE)
        END AS current_wait_days,

        CURRENT_TIMESTAMP AS load_timestamp

        FROM warehouse.int_oncology_referrals s

        LEFT JOIN LATERAL(
            SELECT
                c.booking_date AS first_booking_date,
                c.appointment_date AS first_clinic_date,
                c.appointment_attendance_status,
                c.ref_to_local_code
            FROM staging.oncology_clinic c
            WHERE REPLACE(c.nhs_number, ' ', '') = REPLACE(s.nhs_number, ' ', '')
            AND c.booking_date >= s.date_referred
            ORDER BY c.booking_date
            LIMIT 1
        ) clinic ON TRUE
        WHERE s.date_referred IS NOT NULL
),

enriched AS (
    SELECT
        *,

        -- Inclusion / Exclusion flags

        CASE
            WHEN COALESCE(TRIM(no_opa), '') = ''
            THEN 1
            ELSE 0
        END AS include_in_operational_reporting_flag,

        CASE
            WHEN referral_source IN ('SRH', 'IOW')
            THEN 1
            ELSE 0
        END AS external_provider_flag,

        CASE
            WHEN days_triage_to_clinic > 84
            THEN 1
            ELSE 0
        END AS deferred_followup_flag,

        CASE 
            WHEN days_triage_to_clinic < 84
                AND COALESCE(TRIM(no_opa), '') = ''
            THEN 1
            ELSE 0
        END AS operational_clinic_wait_flag
    
    FROM base
),

classified AS (
    SELECT
        *,

        --Current State

        
        CASE
            WHEN first_clinic_date IS NULL
             AND include_in_operational_reporting_flag = 1
             AND external_provider_flag = 0
            THEN 1
            ELSE 0
        END AS active_referral_flag,

        CASE
            WHEN first_clinic_date IS NOT NULL
             AND first_clinic_date <= CURRENT_DATE
             AND operational_clinic_wait_flag = 1
            THEN 1
            ELSE 0
        END AS completed_operational_clinic_flag,

        CASE
            WHEN first_clinic_date > CURRENT_DATE
             AND operational_clinic_wait_flag = 1
            THEN 1
            ELSE 0
        END AS future_operational_clinic_flag

    FROM enriched

),

reporting AS (
    SELECT
        *,
    -- Current wait for charts

        CASE
            WHEN active_referral_flag = 1
                THEN current_wait_days
            WHEN future_operational_clinic_flag = 1
                THEN days_to_clinic
            WHEN completed_operational_clinic_flag = 1
                THEN days_to_clinic
        END AS operational_wait_days,

    -- Future booked KPI

        CASE 
            WHEN future_operational_clinic_flag = 1
            THEN days_to_clinic
        END AS future_booked_wait_days

    FROM classified

)

SELECT

    *,

    -- Patient classification

    CASE
        WHEN external_provider_flag = 1
            THEN 'External Provider'
        WHEN deferred_followup_flag = 1
            THEN 'Deferred Follow-up'
        WHEN future_operational_clinic_flag = 1
            THEN 'Future Booked'
        WHEN completed_operational_clinic_flag = 1
            THEN 'Historic'
        ELSE 'Waiting'
    END AS patient_group,

    
    CASE
        WHEN active_referral_flag = 1
            THEN 1
        WHEN future_operational_clinic_flag = 1
            THEN 2
        WHEN deferred_followup_flag = 1
            THEN 3
        WHEN completed_operational_clinic_flag = 1
            THEN 4
        WHEN external_provider_flag = 1
            THEN 5
        ELSE 99
    END AS patient_group_sort,

    -- RAG

    CASE 
        WHEN current_wait_days <= 14 THEN 'GREEN'
        WHEN current_wait_days <= 21 THEN 'AMBER'
        ELSE 'RED'
    END AS clinic_rag,

    -- Time windows

    CASE
        WHEN first_booking_date >= CURRENT_DATE - INTERVAL '30 days'
             AND include_in_operational_reporting_flag = 1
        THEN 1
        ELSE 0
    END AS last_30_day_booking_flag,

    CASE
        WHEN first_clinic_date >= CURRENT_DATE - INTERVAL '30 days'
             AND completed_operational_clinic_flag = 1
        THEN 1
        ELSE 0
    END AS last_30_day_clinic_flag,

    -- Trend chart dates
    DATE_TRUNC('week', first_booking_date)::DATE AS booking_week_commencing,

    DATE_TRUNC('week', first_clinic_date)::DATE AS clinic_week_commencing,

    -- Wait Buckets

    CASE
        WHEN operational_wait_days < 7 THEN '0-1 Weeks'
        WHEN operational_wait_days < 14 THEN '1-2 Weeks'
        WHEN operational_wait_days < 21 THEN '2-3 Weeks'
        WHEN operational_wait_days < 28 THEN '3-4 Weeks'
        WHEN operational_wait_days < 35 THEN '4-5 Weeks'
        WHEN operational_wait_days < 42 THEN '5-6 Weeks'
        WHEN operational_wait_days < 49 THEN '6-7 Weeks'
        WHEN operational_wait_days < 56 THEN '7-8 Weeks'
        ELSE '8+ Weeks'
    END AS wait_week_bucket,

    CASE
        WHEN operational_wait_days < 7 THEN 1
        WHEN operational_wait_days < 14 THEN 2
        WHEN operational_wait_days < 21 THEN 3
        WHEN operational_wait_days < 28 THEN 4
        WHEN operational_wait_days < 35 THEN 5
        WHEN operational_wait_days < 42 THEN 6
        WHEN operational_wait_days < 49 THEN 7
        WHEN operational_wait_days < 56 THEN 8
        ELSE 9
    END AS wait_week_bucket_sort

FROM reporting;