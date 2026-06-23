import os
import subprocess
import psycopg2
from dotenv import load_dotenv

import logging

logging.basicConfig(
    filename=r"C:\IDR\logs\etl.log",
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)

load_dotenv()
DB_CONFIG = {
    "host": os.getenv("PGHOST"),
    "port": os.getenv("PGPORT"),
    "dbname": os.getenv("PGDATABASE"),
    "user": os.getenv("PGUSER"),
    "password": os.getenv("PGPASSWORD"),
}

def run_python(script):
    logging.info(f"Running {script}")
    subprocess.run(["python", script], check=True)

def run_sql(file):
    logging.info(f"Executing {file}")
    conn = psycopg2.connect(**DB_CONFIG)
    cursor = conn.cursor()
    with open(file, 'r') as f:
        cursor.execute(f.read())
    conn.commit()
    cursor.close()
    conn.close()

def run_sql_inline(sql):
    conn = psycopg2.connect(**DB_CONFIG)
    cursor = conn.cursor()
    cursor.execute(sql)
    conn.commit()
    cursor.close()
    conn.close()


# STEP1: Load Staging
try:
    run_python("etl/load_rt_referral.py")
    run_python("etl/load_booking.py")
    run_python("etl/load_ecad.py")
    run_python("etl/load_ct.py")
    run_python("etl/load_treat.py")
    run_python("etl/load_machine_appointments.py")
    run_python("etl/load_oncology.py")
except Exception as e:
    logging.info(f"Pipeline failes {e}")
    raise

# STEP2: DROP dependant objects first
run_sql_inline("""
               DROP VIEW IF EXISTS warehouse.int_rt_treat_summary;
               DROP VIEW IF EXISTS warehouse.int_oncology_events;
               DROP TABLE IF EXISTS warehouse.fact_rt_pathway;
               DROP VIEW IF EXISTS warehouse.int_rt_machine_capacity_window;
               DROP VIEW IF EXISTS warehouse.int_rt_machine_appointments;
               """)

# STEP 3: build Oncology fact first
run_sql("../SQL/facts/fact_oncology_pathway.sql")

# STEP 4: Intermediate

run_sql("../SQL/intermediate/int_rt_referral.sql")
run_sql("../SQL/intermediate/int_rt_booking_events.sql")
run_sql("../SQL/intermediate/int_rt_ecad_events.sql")
run_sql("../SQL/intermediate/int_rt_ct_events.sql")
run_sql("../SQL/intermediate/int_rt_treat_events.sql")
run_sql("../SQL/intermediate/int_rt_trt_summary.sql")
run_sql("../SQL/intermediate/int_oncology_events.sql")
run_sql("../SQL/intermediate/int_rt_machine_appointments.sql")
run_sql("../SQL/intermediate/int_rt_machine_capacity.sql")

# STEP 5: Dimensions
run_sql("../SQL/dimensions/dim_rcr_category.sql")
run_sql("../SQL/dimensions/dim_rcr_targets.sql")

# STEP 6: Final Treatment FACT Tables

run_sql("../SQL/facts/fact_rt_pathway.sql")
run_sql("../SQL/facts/fact_rt_machine_capacity.sql")

logging.info("Pipeline complete")