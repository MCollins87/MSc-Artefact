CREATE TABLE IF NOT EXISTS warehouse.dim_rcr_category (
    raw_activity_name TEXT PRIMARY KEY,
    rcr_category TEXT NOT NULL
);

-- Insert only if not already present
INSERT INTO warehouse.dim_rcr_category (raw_activity_name, rcr_category)
VALUES
('Bookings CAT1', 'CAT1'),
('Bookings CAT2', 'CAT2'),
('Bookings CAT3', 'CAT3'),
('Bookings CAT3+', 'CAT3+'),
('Bookings CAT4', 'CAT4')
ON CONFLICT (raw_activity_name) DO NOTHING;
