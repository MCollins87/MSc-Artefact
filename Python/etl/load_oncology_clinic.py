# ETL Script to load Oncology Clinic data into PostgreSQL
# This script reads a CSV file containing Clinic  data, 
# performs necessary cleaning and transformation, and then loads the data into a staging table in PostgreSQL.
# Written by: Mark Collins | Date: 2024-07-10

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
    "CLINIC_FILE_PATH",
    r"C:\IDR\RAW\Onc_Clinic"
)

#----------------------------------------
# HELPER FUNCTIONS 
#----------------------------------------

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
    )
    df = df.rename(columns={
        "patient_identifier_(dist_no)": "pas_number",
        "ref_consultant_full_name": "ref_consultant",
        "ref_to_national_specialty_code_&_name": "ref_to_national_code",
        "ref_to_local_specialty_code_&_name": "ref_to_local_code",
        "consultant_full_name": "consultant",
        "appointment_attended_indicator": "appointment_attended",
        "appointment_attendance_status_desc": "appointment_attendance_status"
    })
    return df

def convert_dates(df):
    date_columns = [
        "booking_date",
        "appointment_date"
    ]
    for col in date_columns:
        if col in df.columns:
            df[col] = pd.to_datetime(df[col], dayfirst=True, errors='coerce')
    return df

def clean_value(val):
    """Convert pandas NaN to None for database insertion."""
    if pd.isna(val):
        return None
    return val

#----------------------------------------
# LOAD DATA FUNCTION
#----------------------------------------

def load_data():
    logging.info("Loading Oncology Clinic CSV...")
    file_path = get_latest_file(DATA_PATH, "Onc_Clinic")
    logging.info(f"Using file: {file_path}")

    # Read the CSV file into a DataFrame
    df = pd.read_csv(file_path, encoding="utf-8-sig")

    # Clean and transform the DataFrame
    df = clean_columns(df)

    df = convert_dates(df)

    df["pas_number"] = df["pas_number"].astype(str).str.strip()
    df["nhs_number"] = df["nhs_number"].astype(str).str.strip()

    logging.info(f"Loaded {len(df)} rows from the CSV file.")
    return df

#----------------------------------------
# UPLOAD DATA TO DATABASE
#----------------------------------------

def insert_data(df):
    logging.info("Connecting to the database...")
    conn = psycopg2.connect(**DB_CONFIG)
    cursor = conn.cursor()

    
    logging.info("Preparing data for upsert...")
    records = []
    for _, row in df.iterrows():
        records.append((
            clean_value(row.get("pas_number")),
            clean_value(row.get("nhs_number")),
            clean_value(row.get("surname")),
            clean_value(row.get("booking_date")),
            clean_value(row.get("appointment_date")),
            clean_value(row.get("ref_consultant")),
            clean_value(row.get("ref_to_national_code")),
            clean_value(row.get("ref_to_local_code")),
            clean_value(row.get("consultant")),
            clean_value(row.get("clinic_code")),
            clean_value(row.get("appointment_attended")),
            clean_value(row.get("appointment_attendance_status"))
        ))


    # Define the SQL query for upsert
    insert_query = """
        INSERT INTO staging.oncology_clinic (
            pas_number,
            nhs_number,
            surname,
            booking_date,
            appointment_date,
            ref_consultant,
            ref_to_national_code,
            ref_to_local_code,
            consultant,
            clinic_code,
            appointment_attended,
            appointment_attendance_status
        )
        VALUES %s
    """

    logging.info(f"Inserting {len(records)} clinic records into the database...")
    execute_values(cursor, insert_query, records)
    conn.commit()
    cursor.close()
    conn.close()
    logging.info("Data insertion completed successfully.")

#----------------------------------------
# MAIN EXECUTION
#----------------------------------------

if __name__ == "__main__":
    logging.info("Starting Oncology Clinic ETL process...")
    try:
        df = load_data()
        insert_data(df)
        logging.info("Oncology Clinic ETL process completed successfully.")
    except Exception as e:
        logging.error(f"Oncology Clinic ETL process failed: {e}")
        raise
