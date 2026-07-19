DROP VIEW IF EXISTS warehouse.int_oncology_referrals;

CREATE VIEW warehouse.int_oncology_referrals AS

    SELECT
    MAX(source_id) AS source_id,
    r_number,
    MAX(nhs_number) AS nhs_number,
    MAX(patient_name) AS patient_name,
    MAX(speciality_referred) AS speciality_referred,
    MAX(oncologist) AS oncologist,
    MAX(referral_source) AS referral_source,
    MIN(date_referred) AS date_referred,
    MIN(date_received) AS date_received,
    MAX(date_triaged) AS date_triaged,
    MAX(clinic_date) AS clinic_date,
    MAX(clinic_type) AS clinic_type,
    MAX(NULLIF(TRIM(no_opa),'')) AS no_opa,
    STRING_AGG(DISTINCT delay_reason, ';') AS delay_reason

    FROM staging.stg_oncology_intake
    GROUP BY r_number;
