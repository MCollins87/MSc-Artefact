DROP VIEW IF EXISTS warehouse.int_rt_treat_events;

CREATE VIEW warehouse.int_rt_treat_events AS

WITH treat_clean AS (
    SELECT
        t.activity_instance_id,
        t.nhs_number,
        t.r_number,
        t.first_treat_date,
        t.appointment_status,
        t.resource_name,
        t.treat_activity_name,
        t.oncologist,

        -- Defensive deduplication
        ROW_NUMBER() OVER (
            PARTITION BY t.activity_instance_id
            ORDER BY t.first_treat_date DESC
        ) AS rn

    FROM staging.stg_aria_treat t
    WHERE t.first_treat_date IS NOT NULL
)

SELECT
    activity_instance_id,
    nhs_number,
    r_number,
    first_treat_date,
    appointment_status,
    resource_name,
    treat_activity_name,
    oncologist

FROM treat_clean
WHERE rn = 1;