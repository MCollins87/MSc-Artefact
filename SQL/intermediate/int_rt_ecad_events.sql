DROP VIEW IF EXISTS warehouse.int_rt_ecad_events;

CREATE VIEW warehouse.int_rt_ecad_events AS

WITH ecad_clean AS (
    SELECT
        e.activity_instance_id,
        e.nhs_number,
        e.r_number,
        e.ecad AS ecad_date,
        e.oncologist,

        -- Defensive deduplication
        ROW_NUMBER() OVER (
            PARTITION BY e.activity_instance_id
            ORDER BY e.ecad DESC
        ) AS rn

    FROM staging.aria_ecad e
    WHERE e.ecad IS NOT NULL
)

SELECT
    activity_instance_id,
    nhs_number,
    r_number,
    ecad_date,
    oncologist

FROM ecad_clean
WHERE rn = 1;