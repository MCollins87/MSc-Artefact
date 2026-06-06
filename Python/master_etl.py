import os
import subprocess
import logging
import psycopg2
from dotenv import load_dotenv

os.chdir(r"C:\IDR\MSc-Artefact\Python")

load_dotenv()
DB_CONFIG = {
    "host": os.getenv("PGHOST"),
    "port": os.getenv("PGPORT"),
    "dbname": os.getenv("PGDATABASE"),
    "user": os.getenv("PGUSER"),
    "password": os.getenv("PGPASSWORD"),
}

logging.basicConfig(
    filename=r"C:\IDR\logs\etl.log",
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)

def build_fact_table():
    logging.info("Starting fact table build process.")
    try:
        # load SQL file
        with open(r"C:\IDR\MSc-Artefact\SQL\build_fact_table.sql", "r") as f:
            sql = f.read()

        # Connect to DB
        conn = psycopg2.connect(**DB_CONFIG)
        cursor = conn.cursor()
        # Execute
        cursor.execute(sql)
        conn.commit()
        # get row count for logging
        cursor.execute("SELECT COUNT(*) FROM warehouse.fact_oncology_pathway;")
        row_count = cursor.fetchone()[0]
        logging.info(f"Fact table build completed. Rows inserted: {row_count}")

        cursor.close()
        conn.close()
    except Exception as e:
        logging.error(f"Fact table build failed: {e}")
        raise


logging.info("Starting master ETL process.")
logging.info("Running ARIA RT Referral ETL...")
try:
    subprocess.run(["python", "etl_load_ARIA_RT_Referral.py"], check=True)
    logging.info("ARIA RT Referral ETL completed.")
except subprocess.CalledProcessError as e:
    logging.error(f"ARIA RT Referral ETL failed: {e}")

logging.info("Running ARIA First Treatment ETL...")
try:
    subprocess.run(["python", "etl_load_ARIA_Treat.py"], check=True)
    logging.info("ARIA First Treatment ETL completed.")
except subprocess.CalledProcessError as e:
    logging.error(f"ARIA First Treatment ETL failed: {e}")

logging.info("Running ARIA CT ETL...")
try:
    subprocess.run(["python", "etl_load_ARIA_CT.py"], check=True)
    logging.info("ARIA CT ETL completed.")
except subprocess.CalledProcessError as e:
    logging.error(f"ARIA CT ETL failed: {e}")

logging.info("Running Intake ETL...")
try:
    subprocess.run(["python", "etl_load_intake.py"], check=True)
    logging.info("Intake ETL completed.")
except subprocess.CalledProcessError as e:
    logging.error(f"Intake ETL failed: {e}")

logging.info("Building Fact Table...")

build_fact_table()

    
logging.info("Master ETL process completed successfully.")

