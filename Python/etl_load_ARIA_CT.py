# ETL Script to load Radiotherapy CT data into PostgreSQL
# This script reads a CSV file containing CT Appointment data, 
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
    "ARIA_CT_FILE_PATH",
    r"C:\IDR\RAW\ARIA_CT"
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
        "r_number": "r_number",
        "ct_date": "ct_date",
        "appointmentstatus": "appointment_status",
        "primaryoncologist": "oncologist",
        "activityname": "activity_name",
        "resourcename": "resource_name",
        "nhsnumber": "nhs_number",
        "pasnumber": "pas_number",
        "ctractivityinstanceser": "activity_instance_id"
    })
    return df

def convert_dates(df):
    df["ct_date"] = pd.to_datetime(df["ct_date"], errors="coerce")
    return df

def clean_value(val):
    if pd.isna(val):
        return None
    return val

def load_data():
    logging.info("loading RT CT data from CSV...")
    file_path = get_latest_file(DATA_PATH, "RT_CT")
    logging.info(f"using file: {file_path}")
    df = pd.read_csv(file_path, encoding="utf-8-sig")
    logging.info("cleaning and transforming data...")
    df = clean_columns(df)
    df = convert_dates(df)
    logging.info(f"loaded {len(df)} rows.")
    return df

def upsert_data(df):
    logging.info("upserting data into PostgreSQL...")
    conn = psycopg2.connect(**DB_CONFIG)
    cursor = conn.cursor()

    logging.info("preparing data for upsert...")
    records = []
    for _, row in df.iterrows():
        records.append((
            clean_value(row["activity_instance_id"]),
            clean_value(row["r_number"]),
            clean_value(row["ct_date"]),
            clean_value(row["appointment_status"]),
            clean_value(row["oncologist"]),
            clean_value(row["activity_name"]),
            clean_value(row["resource_name"]),
            clean_value(row["nhs_number"]),
            clean_value(row["pas_number"])
        ))

    logging.info(f"Inserting {len(records)} rows")
    query = """
        INSERT INTO staging.stg_aria_ct (
            activity_instance_id,
            r_number,
            ct_date,
            appointment_status,
            oncologist,
            activity_name,
            resource_name,
            nhs_number,
            pas_number
        )
        VALUES %s
        ON CONFLICT (activity_instance_id)
        DO UPDATE SET
        ct_date = EXCLUDED.ct_date,
        appointment_status = EXCLUDED.appointment_status,  
        resource_name = EXCLUDED.resource_name,
        oncologist = EXCLUDED.oncologist;
    """

    execute_values(cursor, query, records)
    conn.commit()
    cursor.close()
    conn.close()
    logging.info("data upsert complete.")

if __name__ == "__main__":
    logging.info("Starting ETL process for ARIA CT data.")
    try:
        df = load_data()
        upsert_data(df)
    except Exception as e:
        logging.error(f"ETL process failed: {e}")
        raise