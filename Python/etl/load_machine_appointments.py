# ETL Script to load Radiotherapy Machine Appointment data into PostgreSQL
# Uses ARIA activity_instance_id for de-duplication

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
    "ARIA_MACHINE_FILE_PATH",
    r"C:\IDR\RAW\ARIA_All_Treat"
)

# ----------------------------------------
# HELPERS
# ----------------------------------------

def get_latest_file(folder):
    files = [f for f in os.listdir(folder) if f.endswith(".csv")]
    if not files:
        raise FileNotFoundError("No CSV files found")
    latest_file = max(files, key=lambda x: os.path.getctime(os.path.join(folder, x)))
    return os.path.join(folder, latest_file)


def clean_columns(df):
    df.columns = (
        df.columns
        .str.replace('\ufeff', '')
        .str.strip()
        .str.lower()
        .str.replace(" ", "_")
    )


    df = df.rename(columns={
        "ctractivityinstanceser": "activity_instance_id",
        "appointmentdatetime": "appt_start",
        "scheduledendtime": "appt_end",
        "activityname": "activity_name",
        "resourcename": "machine",
        "patientid": "r_number",   # or keep separate if needed
        "activityplannedlength": "planned_minutes",
        "activityreallength": "actual_minutes",
        "appointmentstatus": "appointment_status"
    })


    return df


def convert_dates(df):
    df["appt_start"] = pd.to_datetime(df["appt_start"], errors="coerce")
    df["appt_end"] = pd.to_datetime(df["appt_end"], errors="coerce")
    return df


def load_data():
    logging.info("Loading machine appointment data...")

    file_path = get_latest_file(DATA_PATH)
    logging.info(f"Using file: {file_path}")

    df = pd.read_csv(file_path, encoding="utf-8-sig", dtype=str)

    df = clean_columns(df)
    df = convert_dates(df)

    # ----------------------------------------
    # CLEAN KEYS
    # ----------------------------------------

    df["activity_instance_id"] = df["activity_instance_id"].astype(str).str.strip()

    df = df[df["activity_instance_id"].notna()]
    df = df[df["activity_instance_id"] != ""]
    df = df[df["activity_instance_id"] != "None"]

    # ----------------------------------------
    # DEDUPLICATION (KEY STEP ✅)
    # ----------------------------------------

    logging.info("De-duplicating on activity_instance_id...")

    df = df.sort_values("appt_start")
    df = df.drop_duplicates(subset=["activity_instance_id"], keep="last")

    # sanity check
    dupes = df["activity_instance_id"].duplicated().sum()
    if dupes > 0:
        raise ValueError("Duplicates remain after deduplication")

    logging.info(f"Rows after deduplication: {len(df)}")

    return df


# ----------------------------------------
# UPSERT
# ----------------------------------------

def upsert_data(df):
    conn = psycopg2.connect(**DB_CONFIG)
    cursor = conn.cursor()

    records = []

    for _, row in df.iterrows():
        records.append((
            row["activity_instance_id"],
            row["machine"],
            row["appt_start"],
            row["appt_end"],
            row.get("activity_name"),
            row.get("r_number"),
            row.get("appointment_status")
        ))

    query = """
        INSERT INTO staging.aria_machine_appointments (
            activity_instance_id,
            machine,
            appt_start,
            appt_end,
            activity_name,
            r_number,
            appointment_status
        )
        VALUES %s
        ON CONFLICT (activity_instance_id)
        DO UPDATE SET
            appt_start = EXCLUDED.appt_start,
            appt_end   = EXCLUDED.appt_end,
            activity_name = EXCLUDED.activity_name,
            machine = EXCLUDED.machine,
            appointment_status = EXCLUDED.appointment_status;
    """

    execute_values(cursor, query, records)
    conn.commit()
    cursor.close()
    conn.close()

    logging.info("Upsert complete.")


# ----------------------------------------

if __name__ == "__main__":
    try:
        df = load_data()
        upsert_data(df)
    except Exception as e:
        logging.error(f"ETL failed: {e}")
        raise