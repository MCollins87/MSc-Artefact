
DROP VIEW IF EXISTS warehouse.int_rt_booking_events;

CREATE VIEW warehouse.int_rt_booking_events AS

WITH booking_clean AS (
    SELECT
        b.activity_instance_id,
        b.nhs_number,
        b.r_number,
        b.booking_due_date,
        b.booking_status,
        b.activity_name,
        b.booked_by,

        ROW_NUMBER() OVER (
            PARTITION BY b.activity_instance_id
            ORDER BY b.booking_due_date DESC
        ) AS rn

    FROM staging.aria_booking b
    WHERE b.booking_due_date IS NOT NULL
)

SELECT
    activity_instance_id,
    nhs_number,
    r_number,
    booking_due_date,
    booking_status,
    activity_name,
    booked_by

FROM booking_clean
WHERE rn = 1;