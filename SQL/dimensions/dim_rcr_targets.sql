CREATE TABLE IF NOT EXISTS warehouse.dim_rcr_targets (
    rcr_category TEXT PRIMARY KEY,
    target_days INT NOT NULL,
    target_hours INT NULL
);

INSERT INTO warehouse.dim_rcr_targets (rcr_category, target_days, target_hours)
VALUES
('CAT1', 31, NULL),
('CAT2', 31, NULL),
('CAT3', 21, NULL),
('CAT3+', 5, NULL),
('CAT4', 2, 48)
ON CONFLICT (rcr_category) DO UPDATE
SET
    target_days = EXCLUDED.target_days,
    target_hours = EXCLUDED.target_hours;