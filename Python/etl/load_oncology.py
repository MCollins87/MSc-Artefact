# ETL Script to load Oncology Referral Intake data into PostgreSQL
# This script reads a CSV file containing referral intake data, 
# performs necessary cleaning and transformation, and then loads the data into a staging table in PostgreSQL.
# Written by: Mark Collins | Date: 2024-06-01
import os
import pandas as pd
import psycopg2
from psycopg2.extras import execute_values
from dotenv import load_dotenv

import logging

logging.basicConfig(
    filename=r"C:\IDR\logs\etl.log",
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)


# ----------------------------------------
# LOAD ENVIRONMENT VARIABLES
# ----------------------------------------
load_dotenv()

DB_CONFIG = {
    "host": os.getenv("PGHOST"),
    "port": os.getenv("PGPORT"),
    "dbname": os.getenv("PGDATABASE"),
    "user": os.getenv("PGUSER"),
    "password": os.getenv("PGPASSWORD"),
}

DATA_PATH = os.getenv(
    "INTAKE_FILE_PATH",
    r"C:\IDR\RAW\Onc_ref"
)


# ----------------------------------------
# HELPER FUNCTIONS
# ----------------------------------------

def get_latest_file(folder, prefix):
    files = [
        f for f in os.listdir(folder)
        if f.startswith(prefix) and f.endswith(".csv")
    ]
    if not files:
        raise FileNotFoundError(f"No files found with prefix '{prefix}' in folder '{folder}'")
    latest_file = max(files, key=lambda x: os.path.getctime(os.path.join(folder, x)))
    return os.path.join(folder, latest_file)


def clean_columns(df):
    df.columns = (
        df.columns
        .str.replace('\ufeff', '')   # REMOVE BOM
        .str.strip()
        .str.lower()
        .str.replace(" ", "_")
        .str.replace("-", "_")
    )

    df = df.rename(columns={
        "clin_/_med": "clin_med",
        "new_clinic_date": "clinic_date",
        "date_recieved": "date_received"  # fix spelling
    })

    return df



def ensure_columns(df):
    required_cols = [
        "date_received",
        "date_triaged",
        "clinic_date",
        "created",
        "modified"
    ]

    for col in required_cols:
        if col not in df.columns:
            df[col] = None

    return df


def convert_dates(df):
    date_cols = [
        "date_referred",
        "date_received",
        "date_triaged",
        "clinic_date",
        "created",
        "modified"
    ]

    for col in date_cols:
        if col in df.columns:
            df[col] = pd.to_datetime(df[col], format="%Y-%m-%d", errors="coerce")

    return df


def clean_value(val):
    """Convert pandas NaT/NaN → None for PostgreSQL"""
    if pd.isna(val):
        return None
    return val


# ----------------------------------------
# LOAD AND PREP DATA
# ----------------------------------------

def load_data():
    logging.info("Loading  Oncology referral CSV...")
    file_path = get_latest_file(DATA_PATH, "oncology_intake")
    logging.info(f"using file: {file_path}")

    df = pd.read_csv(file_path, encoding="utf-8-sig")
    df = clean_columns(df)
    df = ensure_columns(df)
    df = convert_dates(df)

    # Create surrogate key
    if "id" in df.columns:
        df["source_id"] = df["id"]
    else:
        df["source_id"] = df.index

    logging.info(f"✅ Loaded {len(df)} rows")

    return df


# ----------------------------------------
# LOAD INTO DATABASE
# ----------------------------------------

def upsert_data(df):
    logging.info("🔄 Connecting to database...")

    conn = psycopg2.connect(**DB_CONFIG)
    cursor = conn.cursor()

    logging.info("🔄 Preparing records...")

    records = []

    for _, row in df.iterrows():
        records.append((
            clean_value(row["source_id"]),
            clean_value(row.get("nhs_number")),
            clean_value(row.get("r_number")),
            clean_value(row.get("name")),
            clean_value(row.get("tumour_site")),
            clean_value(row.get("oncologist")),
            clean_value(row.get("referral_source")),
            clean_value(row.get("date_referred")),
            clean_value(row.get("date_received")),
            clean_value(row.get("date_triaged")),
            clean_value(row.get("clinic_date")),
            clean_value(row.get("delay_reason")),
            clean_value(row.get("created")),
            clean_value(row.get("modified")),
            clean_value(row.get("clinic_type")),
            clean_value(row.get("no_opa"))
        ))

    logging.info("🔄 Inserting data...")

    query = """
        INSERT INTO staging.stg_oncology_intake (
            source_id,
            nhs_number,
            r_number,
            patient_name,
            tumour_site,
            oncologist,
            referral_source,
            date_referred,
            date_received,
            date_triaged,
            clinic_date,
            delay_reason,
            created,
            modified,
            clinic_type,
            no_opa
        )
        VALUES %s
        ON CONFLICT (source_id)
        DO UPDATE SET
            nhs_number = EXCLUDED.nhs_number,
            clinic_date = EXCLUDED.clinic_date,
            modified = EXCLUDED.modified;
    """

    execute_values(cursor, query, records)

    conn.commit()
    cursor.close()
    conn.close()

    logging.info("✅ Data loaded successfully")


# ----------------------------------------
# MAIN ENTRY POINT
# ----------------------------------------

if __name__ == "__main__":
    logging.info("Starting ETL process for Intake data.")
    try:
        df = load_data()
        upsert_data(df)
    except Exception as e:
        logging.error(f"ETL process failed: {e}")
        raise