DROP VIEW IF EXISTS warehouse.fact_full_pathway;

CREATE VIEW warehouse.fact_full_pathway AS
SELECT
    -- Keys
    rt_pathway_id AS pathway_id,
    nhs_number,
    r_number,

    -- Modality (plan for SACT to be added)
    'RT' AS treatment_modality,

    -- Oncology dates
    oncology_referral_date,
    oncology_clinic_date,

    -- RT dates
    rt_referral_date,
    booking_completed_date,
    ct_date,
    first_completed_treat_date AS treatment_date,

    -- Flags
    has_active_booking,
    has_completed,
    has_ct_flag,
    
    -- Intervals
    days_oncology_to_rt,
    days_rt_to_booking,
    days_booking_to_ct,
    days_ct_to_treat,

    days_oncology_to_treatment,
    days_rt_to_treatment,

    -- Targets
    cwt_31_day_flag,
    cwt_62_day_flag,

    performance_group,

    --Live risk
    days_to_31_breach,
    days_to_62_breach,
    predicted_breach_flag,
    overdue_62_day,

    CURRENT_TIMESTAMP AS load_timestamp

FROM warehouse.fact_rt_pathway
WHERE include_in_analysis_flag = 1;