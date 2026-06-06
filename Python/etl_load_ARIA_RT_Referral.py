# ETL Script to load Radiotherapy referral data into PostgreSQL
# This script reads a CSV file containing RT referral intake data, 
# performs necessary cleaning and transformation, and then loads the data into a staging table in PostgreSQL.
# Written by: Mark Collins | Date: 2024-06-02

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
    "ARIA_RT_REFERRAL_FILE_PATH",
    r"C:\IDR\RAW\ARIA_RT_Referral"
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
        .str.replace('\ufeff', '')
        .str.strip()
        .str.lower()
        .str.replace(" ", "_")
        .str.replace("-", "_")
    )


    df = df.rename(columns={
        "patientid": "r_number",
        "dateregistered": "rt_referral_date",
        "primaryoncologist": "oncologist",
        "nhsnumber": "nhs_number",
        "pasnumber": "pas_number",
        "activityname": "activity_name",
        "diagnosisicd10": "diagnosis_icd10"
    })

    return df

def convert_dates(df):
    df["rt_referral_date"] = pd.to_datetime(df["rt_referral_date"], errors="coerce")
    return df

def clean_value(val):
    if pd.isna(val):
        return None
    return val

def load_data():
    logging.info("loading RT csv...")
    file_path = get_latest_file(DATA_PATH, "RT_Referral")
    logging.info(f"using file: {file_path}")
    df = pd.read_csv(file_path, encoding="utf-8-sig")

    logging.info("cleaning columns...")
    df = clean_columns(df)
    logging.info("converting dates...")
    df = convert_dates(df)
    logging.info(f"Loaded {len(df)} rows.")
    return df

def upsert_data(df):
    logging.info("connecting to database...")
    conn = psycopg2.connect(**DB_CONFIG)
    cursor = conn.cursor()

    logging.info("preparing data for upsert...")
    records = []
    for _, row in df.iterrows():
        records.append((
            clean_value(row.get("r_number")),
            clean_value(row.get("nhs_number")),
            clean_value(row.get("rt_referral_date")),
            clean_value(row.get("oncologist")),
            clean_value(row.get("activity_name")),
            clean_value(row.get("diagnosis_icd10"))
        ))

    logging.info(f"Upserting {len(records)} records into database...")
    query = """
        INSERT INTO staging.stg_aria_rt_referral (
            r_number,
            nhs_number,
            rt_referral_date,
            oncologist,
            activity_name,
            diagnosis_icd10
        )
        VALUES %s
        ON CONFLICT (nhs_number, rt_referral_date)
        DO NOTHING;
    """
    execute_values(cursor, query, records)
    conn.commit()
    cursor.close()
    conn.close()
    logging.info("Data upsert complete.")

if __name__ == "__main__":
    logging.info("Starting ETL process for ARIA RT Referral data.")
    try:
        df = load_data()
        upsert_data(df)
    except Exception as e:
        logging.error(f"ETL process failed: {e}")
        raise