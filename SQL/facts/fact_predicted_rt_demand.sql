DROP VIEW IF EXISTS warehouse.fact_predicted_rt_demand;

CREATE VIEW warehouse.fact_predicted_rt_demand AS
SELECT
    nhs_number,
    first_clinic_date,
    oncologist,
    speciality_referred
FROM warehouse.fact_oncology_pathway
WHERE clinic_type ILIKE 'clin%'
AND first_clinic_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days';