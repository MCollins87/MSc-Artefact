DROP VIEW IF EXISTS warehouse.int_rt_referral;

CREATE VIEW warehouse.int_rt_referral AS

WITH referral_clean AS (
    SELECT
        r.r_number,
        r.nhs_number,
        r.rt_referral_date,
        r.oncologist,
        r.diagnosis_icd10,

        -- Deduplicate using referral date
        ROW_NUMBER() OVER (
            PARTITION BY r.r_number, r.rt_referral_date
            ORDER BY r.rt_referral_date
        ) AS rn

    FROM staging.stg_aria_rt_referral r
    WHERE r.rt_referral_date IS NOT NULL
)

SELECT
    r_number,
    nhs_number,
    rt_referral_date,
    oncologist,
    diagnosis_icd10

FROM referral_clean
WHERE rn = 1;
