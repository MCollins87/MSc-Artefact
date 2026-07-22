# ETL script to load oncology clinic workbook into PostgreSQL
# Writtn by: Mark Collins
# Updated 2026-07

import os
import logging
import pandas as pd
import psycopg2
import shutil

from dotenv import load_dotenv
from psycopg2.extras import execute_values

# ----------------------------------------
# LOGGING
# ----------------------------------------

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


# ----------------------------------------
# HELPERS
# ----------------------------------------

def get_latest_file(folder):
    files = [
        f for f in os.listdir(folder)
        if f.endswith(".xlsx")
    ]
    if not files:
        logging.info("No clinic workbook found - Skipping clinic load.")
        return None
    latest = max(files, key=lambda f: os.path.getctime(os.path.join(folder, f)))
    return os.path.join(folder, latest)

def clean_columns(df):
    df.columns = (
        df.columns
        .str.replace('\ufeff', '')
        .str.strip()
        .str.lower()
        .str.replace(" ", "_")
        .str.replace("/", "_")
    )

    df = df.rename(columns={
        "pas_no": 
        "pas_number",
        "ref_consultant_full_name": "ref_consultant",
        "ref_to_national_specialty_code_&_name": "ref_to_national_code",
        "ref_to_local_specialty_code_&_name": "ref_to_local_code",
        "consultant_full_name": "consultant",
        "appointment_attended_indicator": "appointment_attended",
        "appointment_attendance_status_desc":"appointment_attendance_status"
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
    if pd.isna(val):
        return None
    return val


# ----------------------------------------
# LOAD WORKBOOK
# ----------------------------------------

def load_data():
    logging.info("Loading Oncology Clinic workbook...")
    path = get_latest_file(DATA_PATH)
    if path is None:
        return None, None
    logging.info(f"Using workbook {path}")
    bookings = pd.read_excel(path, sheet_name="New Bookings")
    appointments = pd.read_excel(path, sheet_name="Appointments")

    bookings["record_source"] = "Booking"
    appointments["record_source"] = "Appointment"

    df = pd.concat([bookings, appointments], ignore_index=True)
    df = clean_columns(df)
    df = convert_dates(df)

    if "pas_number" in df.columns:
        df["pas_number"] = df["pas_number"].astype(str).str.strip()

    if "nhs_number" in df.columns:
        df["nhs_number"] = df["nhs_number"].astype(str).str.strip()

    logging.info(f"Loaded {len(df)} rows")
    return df, path


# ----------------------------------------
# INSERT
# ----------------------------------------

def insert_data(df):
    logging.info("Connecting to the database...")
    conn = psycopg2.connect(**DB_CONFIG)
    cursor = conn.cursor()

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
            clean_value(row.get("appointment_attendance_status")),
            clean_value(row.get("record_source"))
        ))

    insert_sql = """
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
            appointment_attendance_status,
            record_source
        )
        VALUES %s
    """

    execute_values(cursor, insert_sql, records)
    conn.commit()
    cursor.close()
    conn.close()
    logging.info(f"Inserted {len(records)} rows")

#----------------------------------------
# MAIN EXECUTION
#----------------------------------------

if __name__ == "__main__":
    logging.info("Starting Oncology Clinic ETL")
    try:
        df, file_path = load_data()
        if df is None:
            logging.info("No clinic work book available. Skipping")
        else:
            insert_data(df)
            archive_dir = r"C:\IDR\Archive_Onc_Clinic"
            os.makedirs(archive_dir, exist_ok=True)
            destination = os.path.join(archive_dir, os.path.basename(file_path))
            shutil.move(file_path, destination)
            logging.info(f"Workbook archived to {destination}")
        logging.info("Oncology Clinic ETL completed")
    except Exception as e:
        logging.error(f"Oncology Clinic ETL process failed: {e}")
        raise
