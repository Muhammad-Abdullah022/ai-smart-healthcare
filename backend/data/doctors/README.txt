Doctor directory data (feature 10) — one CSV file per source, any name ending in .csv.

Columns (header row required):
  city, doctor_name, specialty, qualification, clinic_name, address, fee_pkr, phone, email, timings, source_url, checked_date

- Use only real, checked information (e.g. the doctor's own clinic page, hospital website, PMDC record).
- email is needed for "Book appointment" to send the request to the doctor.
- The backend loads these files on start (and again when a file changes).

Files
- punjab_govt_consultants_2025.csv — consultants posted by the Primary & Secondary Healthcare Dept., Punjab (2025).
- punjab_teaching_hospital_specialists_2025.csv — specialists at government teaching hospitals, from:
    * University of Health Sciences Lahore, list of approved postgraduate supervisors (July 2025)
      https://www.uhs.edu.pk/downloads/supervisorlist10072025.pdf
    * Sheikh Zayed Hospital / FPGMI Lahore faculty page  https://szmc.org.pk/szpgmi/faculty
    * SHC&ME Dept. seniority list, Associate Professors of Gastroenterology (Nov 2025)
  Anaesthesia, radiology and lab specialties are left out (patients do not book them).
  Fees and phone numbers are not published there, so they are blank: "confirm at the hospital".
There are no made-up doctors. Doctors who sign up in the app appear after admin approval.
