# ETL script to load ECAD data into PostgreSQL
# This script extracts data from a CSV file, transforms it, and loads it into a PostgreSQL database.
# Written by: Mark Collins | Date: 2024-06-15

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
    "ARIA_BOOKING_FILE_PATH",
    r"C:\IDR\RAW\ARIA_ECAD"
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
        "primaryoncologist": "oncologist",
        "nhsnumber": "nhs_number",
        "pasnumber": "pas_number",
        "ctractivityinstanceser": "activity_instance_id"
    })

    return df

def convert_dates(df):
    df['ecad'] = pd.to_datetime(df['ecad'], errors='coerce')
    return df

def clean_value(val):
    if pd.isna(val):
        return None
    return val

def load_data():
    logging.info("Starting ETL processes for ECAD")
    file_path = get_latest_file(DATA_PATH, "RT_ECAD")
    logging.info(f"Loading data from file: {file_path}")
    df = pd.read_csv(file_path, encoding='utf-8-sig')

    logging.info("Cleaning column names and renaming columns")
    df = clean_columns(df)
    df = convert_dates(df)

    # Clean key column
    df['activity_instance_id'] = df['activity_instance_id'].astype(str).str.strip()

    #Remove bad keys
    df = df[df["activity_instance_id"].notna()]
    df = df[df["activity_instance_id"] != ""]
    df = df[df["activity_instance_id"] != "None"]

    # Sort so most recent ECAD wins
    df = df.sort_values("ecad")

    # Deduplicate
    df = df.drop_duplicates(subset=["activity_instance_id"], keep="last")

     # Safety check
    dupes = df["activity_instance_id"].duplicated().sum()
    if dupes > 0:
        raise ValueError(f"Duplicate activity_instance_id found after deduplication: {dupes}")
    return df

def upsert_data(df):
    logging.info("Connecting to Database")
    conn = psycopg2.connect(**DB_CONFIG)
    cursor = conn.cursor()

    logging.info("preparing data for upsert.")
    records = []
    for _,row in df.iterrows():
        records.append((
            clean_value(row.get('activity_instance_id')),
            clean_value(row.get('r_number')),
            clean_value(row.get('ecad')),
            clean_value(row.get('oncologist')),
            clean_value(row.get('nhs_number')),
            clean_value(row.get('pas_number')),
            clean_value(row.get('diagnosis_icd10'))
        ))

        logging.info(f"Upserting {len(records)} records into the database.")
    query = """
    INSERT INTO staging.aria_ecad (
        activity_instance_id,
        r_number,
        ecad,
        oncologist,
        nhs_number,
        pas_number,
        diagnosis_icd10
    )
    VALUES %s
    ON CONFLICT (activity_instance_id)
    DO UPDATE SET
    ecad = EXCLUDED.ecad,
    oncologist = EXCLUDED.oncologist;
    """

    execute_values(cursor, query, records)
    conn.commit()
    cursor.close()
    conn.close()
    logging.info("Data upsert complete.")

if __name__ == "__main__":
    logging.info("Starting ETL process for ECAD data.")
    try:
        df = load_data()
        upsert_data(df)
    except Exception as e:
        logging.error(f"ETL process failed: {e}")
        raise