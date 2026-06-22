DROP VIEW IF EXISTS warehouse.int_rt_booking_events;

CREATE VIEW warehouse.int_rt_booking_events AS

SELECT
    b.r_number,
    b.nhs_number,

    -- Bookings completion
    MIN(booking_due_date) FILTER (
        WHERE booking_status = 'Completed'
    ) AS booking_completed_date,

    CASE 
        WHEN COUNT(*) FILTER (
            WHERE booking_status = 'Completed'
        ) > 0 THEN 1
        ELSE 0
    END AS booking_completed_flag,

    -- RCR Category
    MIN(d.rcr_category) AS rcr_category

FROM staging.aria_booking b

LEFT JOIN warehouse.dim_rcr_category d
    ON b.activity_name = d.raw_activity_name

GROUP BY r_number, nhs_number;