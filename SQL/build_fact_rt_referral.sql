DROP TABLE IF EXISTS warehouse.fact_rt_referral;

CREATE TABLE warehouse.fact_rt_referral AS

SELECT
    r.nhs_number,
    r.rt_referral_date,
    r.oncologist,
    r.activity_name,
    r.diagnosis_icd10,

    -- Time Dimensions
    DATE_TRUNC('month', r.rt_referral_date)::DATE AS rt_referral_month,
    DATE_TRUNC('week', r.rt_referral_date)::DATE AS rt_referral_week,

    -- Flags
    1 AS is_rt_referral,

    -- Metadata
    CURRENT_TIMESTAMP AS load_timestamp

FROM staging.stg_aria_rt_referral r

WHERE r.rt_referral_date is NOT NULL;