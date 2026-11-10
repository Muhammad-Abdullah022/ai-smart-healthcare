Doctor directory data (feature 10) — one CSV file per source, any name ending in .csv.

Columns (header row required):
  city, doctor_name, specialty, qualification, clinic_name, address, fee_pkr, phone, email, timings, source_url, checked_date

- Use only real, checked information (e.g. the doctor's own clinic page, hospital website, PMDC record).
- email is needed for "Book appointment" to send the request to the doctor.
- The backend loads these files on start (and again when a file changes).
