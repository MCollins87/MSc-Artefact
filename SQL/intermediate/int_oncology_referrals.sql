DROP VIEW IF EXISTS warehouse.int_oncology_referrals;

CREATE VIEW warehouse.int_oncology_referrals AS

WITH dedupe AS (
    SELECT
    s.*,
    ROW_NUMBER() OVER (
        PARTITION BY UPPER(TRIM(r_number))
        ORDER BY
            CASE
                WHEN COALESCE(TRIM(no_opa), '') = ''
                THEN 1
                ELSE 0
            END DESC,
            clinic_date DESC NULLS LAST,
            date_triaged DESC NULLS LAST,
            source_id DESC
    ) AS rn
    FROM staging.stg_oncology_intake s
)

SELECT *
FROM dedupe
WHERE rn = 1;