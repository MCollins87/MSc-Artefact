INSERT INTO warehouse.dim_icd10_mapping VALUES

-- ========================
-- 🔴 EXCLUSIONS (HIGHEST PRIORITY)
-- ========================
('EXCLUDE', 'D352', 'D354', 0, 1),
('EXCLUDE', 'C632', 'C632', 0, 1),
('EXCLUDE', 'C578', 'C579', 0, 1),
('EXCLUDE', 'D443', 'D445', 0, 1),

-- ========================
-- 🧠 BRAIN OTHER (override exclusions)
-- ========================
('Brain (other)', 'C751', 'C753', 1, 2),
('Brain (other)', 'D18', 'D18', 1, 2),
('Brain (other)', 'D32', 'D33', 1, 2),
('Brain (other)', 'D352', 'D354', 1, 2),
('Brain (other)', 'D42', 'D43', 1, 2),
('Brain (other)', 'D443', 'D445', 1, 2),

-- ========================
-- 🧠 BRAIN MALIGNANT
-- ========================
('Brain (malignant)', 'C70', 'C72', 1, 3),

-- ========================
-- 🟢 SPECIFIC SITES
-- ========================
('Anus', 'C21', 'C21', 1, 3),
('Bladder', 'C67', 'C67', 1, 3),
('Bone', 'C40', 'C41', 1, 3),
('Breast', 'C50', 'C50', 1, 3),
('Breast (DCIS)', 'D05', 'D05', 1, 3),
('Cervix', 'C53', 'C53', 1, 3),
('Eye', 'C69', 'C69', 1, 3),
('Gallbladder', 'C23', 'C23', 1, 3),
('Kidney', 'C64', 'C64', 1, 3),
('Liver', 'C22', 'C22', 1, 3),
('Melanoma', 'C43', 'C43', 1, 3),
('Mesothelioma', 'C45', 'C45', 1, 3),
('Non-melanoma skin cancer', 'C44', 'C44', 1, 3),
('Oesophagus', 'C15', 'C15', 1, 3),
('Pancreas', 'C25', 'C25', 1, 3),
('Penis', 'C60', 'C60', 1, 3),
('Prostate', 'C61', 'C61', 1, 3),
('Scrotum', 'C632', 'C632', 1, 2),
('Small intestine', 'C17', 'C17', 1, 3),
('Stomach', 'C16', 'C16', 1, 3),
('Testes', 'C62', 'C62', 1, 3),
('Thymus', 'C37', 'C37', 1, 3),
('Vagina', 'C52', 'C52', 1, 3),
('Vulva', 'C51', 'C51', 1, 3),

-- ========================
-- 🟡 GROUPED SYSTEMS
-- ========================
('Colorectal', 'C18', 'C20', 1, 5),
('Lung', 'C33', 'C34', 1, 5),
('Head and neck', 'C00', 'C14', 1, 5),
('Head and neck', 'C30', 'C32', 1, 5),
('Urinary tract', 'C65', 'C66', 1, 5),
('Urinary tract', 'C68', 'C68', 1, 5),
('Uterus', 'C54', 'C55', 1, 5),
('Ovary', 'C56', 'C56', 1, 5),
('Ovary', 'C57', 'C57', 1, 6),

-- ========================
-- 🟠 SPECIAL GROUPS
-- ========================
('Cancer of unknown primary', 'C77', 'C80', 1, 5),
('Kaposi sarcoma', 'C46', 'C46', 1, 5),
('Heart/mediastinum/pleura', 'C38', 'C39', 1, 5),
('Soft tissue', 'C47', 'C49', 1, 5),
('Other malignant', 'C24', 'C26', 1, 6),
('Other malignant', 'C63', 'C63', 1, 6),
('Other malignant', 'C76', 'C76', 1, 6),
('Other malignant', 'C97', 'C97', 1, 6),

-- ========================
-- 🟣 ENDOCRINE
-- ========================
('Endocrine (excl brain)', 'C73', 'C75', 1, 6),

-- ========================
-- 🔵 HAEMATOLOGICAL
-- ========================
('Haematological (lymphoma)', 'C81', 'C86', 1, 5),
('Haematological (non-lymphoma)', 'C88', 'C88', 1, 5),
('Haematological (non-lymphoma)', 'C90', 'C96', 1, 5),
('Haematological (non-lymphoma)', 'D45', 'D47', 1, 5),
('Haematological (non-lymphoma)', 'E85', 'E85', 1, 5),

-- ========================
-- 🟤 IN SITU
-- ========================
('In situ', 'D00', 'D07', 1, 5),
('In situ', 'D09', 'D09', 1, 5),

-- ========================
-- 🟢 BENIGN
-- ========================
('Benign', 'D10', 'D17', 1, 10),
('Benign', 'D19', 'D31', 1, 10),
('Benign', 'D34', 'D36', 1, 10),

-- ========================
-- ⚪ UNCERTAIN / UNKNOWN
-- ========================
('Uncertain/Unknown', 'D37', 'D41', 1, 8),
('Uncertain/Unknown', 'D44', 'D44', 1, 8),
('Uncertain/Unknown', 'D48', 'D48', 1, 8);
