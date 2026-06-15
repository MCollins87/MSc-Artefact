DROP VIEW IF EXISTS warehouse.int_rt_ct_events;

CREATE VIEW warehouse.int_rt_ct_events AS

WITH ct_clean AS (
    SELECT
        c.activity_instance_id,
        c.nhs_number,
        c.r_number,
        c.ct_date,
        c.appointment_status,
        c.resource_name,
        c.oncologist,

        -- Defensive deduplication
        ROW_NUMBER() OVER (
            PARTITION BY c.activity_instance_id
            ORDER BY c.ct_date DESC
        ) AS rn

    FROM staging.stg_aria_ct c
    WHERE c.ct_date IS NOT NULL
)

SELECT
    activity_instance_id,
    nhs_number,
    r_number,
    ct_date,
    appointment_status,
    resource_name,
    oncologist

FROM ct_clean
WHERE rn = 1;