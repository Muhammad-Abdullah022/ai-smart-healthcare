/// What each feature screen asks for, in the UI-first phase.
/// Every form saves to MongoDB through POST /entries/{feature}.
/// Dedicated logic (AI, verified data, file upload, QR, PDF) is added feature by feature later.
enum FieldType { text, long, number, date, time, choice, toggle, tags }

class FieldSpec {
  const FieldSpec(this.key, this.label, this.type, {this.hint, this.options = const [], this.required = false});

  final String key;
  final String label;
  final FieldType type;
  final String? hint;
  final List<String> options;
  final bool required;
}

class FormSpec {
  const FormSpec({required this.purpose, required this.fields, this.saveLabel = 'Save', this.notice});

  final String purpose;
  final List<FieldSpec> fields;
  final String saveLabel;
  final String? notice;
}

const _sample = 'Prototype: there is no verified data source for this yet, so results will be clearly '
    'labelled sample data. What you save here is kept in your account.';
const _later = 'This screen saves your details now. The smart part (AI reading, checks) is being added next.';

const _r = true; // required

const Map<int, FormSpec> featureForms = {
  // ---------- Module 1: Diagnosis & medical assistance ----------
  6: FormSpec(
    purpose: 'Find medical laboratories near you for the test you need.',
    notice: _sample,
    saveLabel: 'Save search',
    fields: [
      FieldSpec('test_needed', 'Test you need', FieldType.text, hint: 'e.g. CBC, Lipid profile', required: _r),
      FieldSpec('city', 'City', FieldType.text, hint: 'e.g. Lahore', required: _r),
      FieldSpec('area', 'Area (optional)', FieldType.text, hint: 'e.g. Gulberg'),
    ],
  ),
  7: FormSpec(
    purpose: 'Compare lab test prices before you book.',
    notice: _sample,
    saveLabel: 'Save comparison',
    fields: [
      FieldSpec('test_name', 'Test name', FieldType.text, hint: 'e.g. HbA1c', required: _r),
      FieldSpec('city', 'City', FieldType.text, required: _r),
      FieldSpec('budget', 'Budget in rupees (optional)', FieldType.number),
    ],
  ),
  8: FormSpec(
    purpose: 'Keep your lab reports and the key values in them, so they can be read and explained.',
    notice: 'Photo upload and AI reading of the report are coming next. For now, type the key values.',
    saveLabel: 'Save report',
    fields: [
      FieldSpec('report_type', 'Report type', FieldType.choice,
          options: ['Blood test', 'Urine test', 'X-ray', 'Ultrasound', 'ECG', 'Other'], required: _r),
      FieldSpec('lab_name', 'Lab or hospital', FieldType.text),
      FieldSpec('report_date', 'Report date', FieldType.date, required: _r),
      FieldSpec('key_values', 'Key values', FieldType.long, hint: 'e.g. Hb 12.5 g/dL, WBC 7,200'),
      FieldSpec('notes', 'Notes', FieldType.long),
    ],
  ),
  9: FormSpec(
    purpose: 'Compare a test result from an earlier report with your latest one.',
    saveLabel: 'Save comparison',
    fields: [
      FieldSpec('test_name', 'Test', FieldType.text, hint: 'e.g. Fasting blood sugar', required: _r),
      FieldSpec('unit', 'Unit', FieldType.text, hint: 'e.g. mg/dL'),
      FieldSpec('previous_value', 'Previous value', FieldType.number, required: _r),
      FieldSpec('previous_date', 'Previous date', FieldType.date),
      FieldSpec('current_value', 'Current value', FieldType.number, required: _r),
      FieldSpec('current_date', 'Current date', FieldType.date),
    ],
  ),
  10: FormSpec(
    purpose: 'Get a suggestion for which kind of doctor to see.',
    notice: _later,
    saveLabel: 'Save request',
    fields: [
      FieldSpec('concern', 'What is the problem?', FieldType.long, required: _r),
      FieldSpec('city', 'City', FieldType.text),
      FieldSpec('preference', 'Preference', FieldType.choice, options: ['Any', 'Female doctor', 'Male doctor']),
    ],
  ),
  11: FormSpec(
    purpose: 'Request an appointment and get a confirmation email.',
    notice: 'Prototype: doctors and time slots will come from admin-verified doctors only. '
        'Your request is saved now.',
    saveLabel: 'Request appointment',
    fields: [
      FieldSpec('specialty', 'Doctor type', FieldType.choice,
          options: ['General physician', 'Cardiologist', 'Dermatologist', 'Gynaecologist', 'Paediatrician',
              'Psychiatrist', 'ENT specialist', 'Other'], required: _r),
      FieldSpec('preferred_date', 'Preferred date', FieldType.date, required: _r),
      FieldSpec('preferred_time', 'Preferred time', FieldType.time),
      FieldSpec('mode', 'Visit type', FieldType.choice, options: ['In person', 'Online']),
      FieldSpec('reason', 'Reason for visit', FieldType.long, required: _r),
    ],
  ),
  13: FormSpec(
    purpose: 'Ask a health question in Urdu, English or Roman Urdu.',
    notice: 'Voice input is coming next. You can type your question now.',
    saveLabel: 'Save question',
    fields: [
      FieldSpec('language', 'Language', FieldType.choice, options: ['English', 'Urdu', 'Roman Urdu'], required: _r),
      FieldSpec('question', 'Your question', FieldType.long, required: _r),
    ],
  ),
  14: FormSpec(
    purpose: 'Check in on your recovery each day, so worsening is noticed early.',
    saveLabel: 'Save check-in',
    fields: [
      FieldSpec('condition', 'Recovering from', FieldType.text, hint: 'e.g. Typhoid, surgery', required: _r),
      FieldSpec('feeling', 'Compared with yesterday', FieldType.choice,
          options: ['Better', 'Same', 'Worse'], required: _r),
      FieldSpec('pain_level', 'Pain (0–10)', FieldType.number),
      FieldSpec('notes', 'Notes', FieldType.long),
    ],
  ),
  15: FormSpec(
    purpose: 'Get a second view on advice you received, to discuss with your doctor.',
    notice: _later,
    saveLabel: 'Save request',
    fields: [
      FieldSpec('original_advice', 'Advice you were given', FieldType.long, required: _r),
      FieldSpec('question', 'What would you like checked?', FieldType.long, required: _r),
    ],
  ),

  // ---------- Module 2: Mental health ----------
  17: FormSpec(
    purpose: 'Write down what is on your mind. A supportive assistant will reply here.',
    notice: 'AI replies are coming next. Your notes are private to you. If you are in danger, use "Get help now".',
    saveLabel: 'Save note',
    fields: [FieldSpec('message', 'How are you feeling?', FieldType.long, required: _r)],
  ),
  19: FormSpec(
    purpose: 'Note what stresses you and what helps, to get personal relief ideas.',
    saveLabel: 'Save',
    fields: [
      FieldSpec('source', 'Main source of stress', FieldType.choice,
          options: ['Studies', 'Work', 'Family', 'Money', 'Health', 'Other'], required: _r),
      FieldSpec('level', 'Stress level (1–10)', FieldType.number, required: _r),
      FieldSpec('what_helped', 'What helped before?', FieldType.long),
    ],
  ),
  20: FormSpec(
    purpose: 'Track your exercise sessions. Camera counting will help you keep good form.',
    notice: 'Prototype: camera rep counting runs on your phone and is coming next. Log sessions now.',
    saveLabel: 'Save session',
    fields: [
      FieldSpec('exercise', 'Exercise', FieldType.choice,
          options: ['Squats', 'Push-ups', 'Walking', 'Stretching', 'Yoga', 'Other'], required: _r),
      FieldSpec('reps', 'Repetitions', FieldType.number),
      FieldSpec('minutes', 'Minutes', FieldType.number),
    ],
  ),
  21: FormSpec(
    purpose: 'Keep track of posture problems and get tips to correct them.',
    notice: 'Prototype: live posture detection with the camera is coming next.',
    saveLabel: 'Save',
    fields: [
      FieldSpec('issue', 'Posture issue', FieldType.choice,
          options: ['Neck pain', 'Back pain', 'Rounded shoulders', 'Slouching', 'Other'], required: _r),
      FieldSpec('hours_sitting', 'Hours sitting per day', FieldType.number),
      FieldSpec('notes', 'Notes', FieldType.long),
    ],
  ),
  23: FormSpec(
    purpose: 'Set up a simple daily meditation and wellness plan.',
    saveLabel: 'Save plan',
    fields: [
      FieldSpec('goal', 'Main goal', FieldType.choice, options: ['Better sleep', 'Less stress', 'More focus', 'Calm mood'], required: _r),
      FieldSpec('minutes_per_day', 'Minutes per day', FieldType.number, required: _r),
      FieldSpec('preferred_time', 'Preferred time', FieldType.time),
    ],
  ),

  // ---------- Module 3: Medicine & pharmacy ----------
  26: FormSpec(
    purpose: 'Save a prescription so its medicines can be read and turned into a schedule.',
    notice: 'Photo upload and handwriting reading are coming next. Type what the prescription says.',
    saveLabel: 'Save prescription',
    fields: [
      FieldSpec('doctor_name', 'Doctor', FieldType.text),
      FieldSpec('date', 'Prescription date', FieldType.date, required: _r),
      FieldSpec('medicines_written', 'Medicines written', FieldType.long,
          hint: 'One per line, exactly as written', required: _r),
    ],
  ),
  27: FormSpec(
    purpose: 'Identify a medicine from its pack.',
    notice: 'Photo identification is coming next. Type what is printed on the pack.',
    saveLabel: 'Save',
    fields: [
      FieldSpec('name_on_pack', 'Name on the pack', FieldType.text, required: _r),
      FieldSpec('salt', 'Ingredient (if printed)', FieldType.text),
      FieldSpec('expiry', 'Expiry date', FieldType.date),
    ],
  ),
  28: FormSpec(
    purpose: 'Find pharmacies near you that may have your medicine.',
    notice: _sample,
    saveLabel: 'Save search',
    fields: [
      FieldSpec('medicine', 'Medicine', FieldType.text, required: _r),
      FieldSpec('city', 'City', FieldType.text, required: _r),
      FieldSpec('area', 'Area (optional)', FieldType.text),
    ],
  ),
  29: FormSpec(
    purpose: 'Compare medicine prices between pharmacies.',
    notice: _sample,
    saveLabel: 'Save comparison',
    fields: [
      FieldSpec('medicine', 'Medicine', FieldType.text, required: _r),
      FieldSpec('strength', 'Strength', FieldType.text, hint: 'e.g. 500 mg'),
      FieldSpec('city', 'City', FieldType.text),
    ],
  ),
  30: FormSpec(
    purpose: 'Find medicines with the same ingredient and strength. Ask your doctor before switching.',
    notice: 'Alternatives will only come from a verified medicine database, never from AI guesses.',
    saveLabel: 'Save search',
    fields: [
      FieldSpec('brand', 'Medicine you use', FieldType.text, required: _r),
      FieldSpec('salt', 'Ingredient', FieldType.text),
      FieldSpec('strength', 'Strength', FieldType.text),
    ],
  ),
  31: FormSpec(
    purpose: 'Check whether two medicines are safe to take together.',
    notice: 'Interaction results will come from a verified medicine database. Always confirm with a pharmacist.',
    saveLabel: 'Save check',
    fields: [
      FieldSpec('medicine_a', 'First medicine', FieldType.text, required: _r),
      FieldSpec('medicine_b', 'Second medicine', FieldType.text, required: _r),
    ],
  ),
  34: FormSpec(
    purpose: 'Turn a prescription into a reminder schedule you approve.',
    notice: _later,
    saveLabel: 'Save',
    fields: [FieldSpec('prescription_text', 'Prescription text', FieldType.long, required: _r)],
  ),
  37: FormSpec(
    purpose: 'Ask about a medicine and its side effects in plain language.',
    notice: _later,
    saveLabel: 'Save question',
    fields: [
      FieldSpec('medicine', 'Medicine', FieldType.text, required: _r),
      FieldSpec('question', 'Your question', FieldType.long, required: _r),
    ],
  ),

  // ---------- Module 4: Records & care ----------
  38: FormSpec(
    purpose: 'Keep all your health records together in one private place.',
    notice: 'File and photo upload is coming next.',
    saveLabel: 'Save record',
    fields: [
      FieldSpec('record_type', 'Type', FieldType.choice,
          options: ['Report', 'Prescription', 'Discharge summary', 'Scan', 'Vaccination card', 'Other'], required: _r),
      FieldSpec('title', 'Title', FieldType.text, required: _r),
      FieldSpec('date', 'Date', FieldType.date),
      FieldSpec('provider', 'Hospital / doctor', FieldType.text),
      FieldSpec('notes', 'Notes', FieldType.long),
    ],
  ),
  39: FormSpec(
    purpose: 'Record your conditions, surgeries, vaccinations and family history.',
    saveLabel: 'Add to history',
    fields: [
      FieldSpec('kind', 'Type', FieldType.choice,
          options: ['Condition', 'Surgery', 'Vaccination', 'Family history', 'Hospital stay'], required: _r),
      FieldSpec('name', 'Name', FieldType.text, hint: 'e.g. Asthma, Appendix removal', required: _r),
      FieldSpec('year', 'Year', FieldType.number),
      FieldSpec('notes', 'Notes', FieldType.long),
    ],
  ),
  40: FormSpec(
    purpose: 'Estimate your future health risks from your lifestyle and history.',
    notice: 'Risk estimates are informational only and not clinically validated. The calculation is coming next.',
    saveLabel: 'Save details',
    fields: [
      FieldSpec('height_cm', 'Height (cm)', FieldType.number, required: _r),
      FieldSpec('weight_kg', 'Weight (kg)', FieldType.number, required: _r),
      FieldSpec('smoker', 'I smoke', FieldType.toggle),
      FieldSpec('activity', 'Exercise', FieldType.choice, options: ['Rarely', '1–2 days a week', '3+ days a week']),
      FieldSpec('family_history', 'Family history', FieldType.tags, hint: 'e.g. diabetes, heart disease'),
    ],
  ),
  41: FormSpec(
    purpose: 'Log readings like blood pressure and sugar to see your trends.',
    saveLabel: 'Save reading',
    fields: [
      FieldSpec('measure', 'Measurement', FieldType.choice,
          options: ['Blood pressure', 'Blood sugar', 'Weight', 'Heart rate', 'Temperature', 'Oxygen'], required: _r),
      FieldSpec('value', 'Value', FieldType.text, hint: 'e.g. 120/80, 110', required: _r),
      FieldSpec('unit', 'Unit', FieldType.text, hint: 'e.g. mmHg, mg/dL'),
      FieldSpec('date', 'Date', FieldType.date, required: _r),
      FieldSpec('time', 'Time', FieldType.time),
    ],
  ),
  42: FormSpec(
    purpose: 'Bring in steps, heart rate and sleep from your smartwatch.',
    notice: 'Prototype: automatic sync needs Health Connect and a supported watch. Log readings manually for now.',
    saveLabel: 'Save',
    fields: [
      FieldSpec('date', 'Date', FieldType.date, required: _r),
      FieldSpec('steps', 'Steps', FieldType.number),
      FieldSpec('heart_rate', 'Resting heart rate', FieldType.number),
      FieldSpec('sleep_hours', 'Sleep (hours)', FieldType.number),
    ],
  ),
  43: FormSpec(
    purpose: 'Add family members and choose who may help manage your care.',
    saveLabel: 'Add family member',
    fields: [
      FieldSpec('name', 'Name', FieldType.text, required: _r),
      FieldSpec('relation', 'Relation', FieldType.choice,
          options: ['Parent', 'Spouse', 'Child', 'Sibling', 'Other'], required: _r),
      FieldSpec('age', 'Age', FieldType.number),
      FieldSpec('conditions', 'Their conditions', FieldType.tags),
      FieldSpec('caregiver', 'Can help manage my care', FieldType.toggle),
    ],
  ),
  44: FormSpec(
    purpose: 'Choose what your emergency QR card shows to doctors and rescuers.',
    notice: 'QR code generation is coming next. Your choices are saved now.',
    saveLabel: 'Save card settings',
    fields: [
      FieldSpec('show_blood_group', 'Show blood group', FieldType.toggle),
      FieldSpec('show_allergies', 'Show allergies', FieldType.toggle),
      FieldSpec('show_conditions', 'Show conditions', FieldType.toggle),
      FieldSpec('show_contacts', 'Show emergency contacts', FieldType.toggle),
      FieldSpec('extra_note', 'Extra note', FieldType.long, hint: 'e.g. I have a pacemaker'),
    ],
  ),
  45: FormSpec(
    purpose: 'Get health suggestions tailored to your goals.',
    notice: _later,
    saveLabel: 'Save goal',
    fields: [
      FieldSpec('goal', 'Goal', FieldType.choice,
          options: ['Lose weight', 'Sleep better', 'Lower blood pressure', 'Eat healthier', 'Be more active'], required: _r),
      FieldSpec('notes', 'Anything we should know?', FieldType.long),
    ],
  ),
  47: FormSpec(
    purpose: 'Doctors: apply for verification so you can review and approve AI suggestions.',
    notice: 'An admin checks every application by hand before approval.',
    saveLabel: 'Submit application',
    fields: [
      FieldSpec('full_name', 'Full name', FieldType.text, required: _r),
      FieldSpec('pmdc_number', 'PMDC registration number', FieldType.text, required: _r),
      FieldSpec('specialty', 'Specialty', FieldType.text, required: _r),
      FieldSpec('hospital', 'Hospital / clinic', FieldType.text),
    ],
  ),
  50: FormSpec(
    purpose: 'Create a health summary to share with your doctor.',
    notice: 'PDF creation is coming next. Your request is saved now.',
    saveLabel: 'Request summary',
    fields: [
      FieldSpec('period', 'Period', FieldType.choice, options: ['Last 30 days', 'Last 3 months', 'Last year'], required: _r),
      FieldSpec('include', 'Include', FieldType.tags, hint: 'e.g. medicines, reports, symptom checks'),
    ],
  ),
};
