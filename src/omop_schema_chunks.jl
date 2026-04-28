const OMOP_SCHEMA_CHUNKS = [

"""Table: person
Purpose: The central demographic table. Every patient in the database has exactly one row here.
Use this table when: counting patients, filtering by age/gender/race/ethnicity, or as the
starting point for any patient-level cohort analysis.
Key columns:
  - person_id (INTEGER, PK): Unique identifier for the patient. Every clinical table links back here.
  - gender_concept_id (INTEGER, FK→concept): Standard code for biological sex. Male=8507, Female=8532.
  - year_of_birth (INTEGER): Year of birth. Use (CURRENT_YEAR - year_of_birth) to compute approximate age.
  - month_of_birth (INTEGER, nullable): Month of birth if available.
  - day_of_birth (INTEGER, nullable): Day of birth if available.
  - race_concept_id (INTEGER, FK→concept): Standard race vocabulary code.
  - ethnicity_concept_id (INTEGER, FK→concept): Standard ethnicity code. Hispanic=38003563.
  - location_id (INTEGER, FK→location): Geographic location of the patient's residence.
  - care_site_id (INTEGER, FK→care_site): The primary care site for this patient.
Example query goal: "Count female patients born after 1980" → filter gender_concept_id=8532 AND year_of_birth>1980.
""",

"""Table: visit_occurrence
Purpose: Records each patient encounter with the healthcare system (inpatient stays,
outpatient visits, emergency visits). One row per visit.
Use this table when: analyzing visit patterns, counting hospital admissions, finding
first/last visits, or filtering clinical events to a specific encounter type.
Key columns:
  - visit_occurrence_id (INTEGER, PK): Unique ID for this visit.
  - person_id (INTEGER, FK→person): Which patient this visit belongs to.
  - visit_concept_id (INTEGER, FK→concept): Type of visit. Inpatient=9201, Outpatient=9202, ER=9203.
  - visit_start_date (DATE): When the visit began. Use for temporal filtering.
  - visit_end_date (DATE): When the visit ended. Null for single-day visits.
  - care_site_id (INTEGER, FK→care_site): Where the visit occurred.
Example query goal: "Find the most recent visit for each patient" → group by person_id, take max(visit_start_date).
Example query goal: "Count inpatient admissions in 2020" → filter visit_concept_id=9201 AND visit_start_date between '2020-01-01' and '2020-12-31'.
""",

"""Table: condition_occurrence
Purpose: Clinical diagnoses and medical conditions recorded for a patient. This is where
ICD-10 codes, diagnoses, and disease flags live after being mapped to standard OMOP vocabulary.
Use this table when: finding patients with a specific disease, counting diagnoses,
studying comorbidities, or filtering patients by diagnosis.
Key columns:
  - condition_occurrence_id (INTEGER, PK): Unique ID for this diagnosis record.
  - person_id (INTEGER, FK→person): The patient.
  - condition_concept_id (INTEGER, FK→concept): Standard SNOMED concept ID for the condition.
    Diabetes type 2 = 201826. Hypertension = 320128. Heart failure = 316139.
  - condition_start_date (DATE): When the diagnosis was first recorded.
  - condition_end_date (DATE, nullable): When the condition resolved (often null for chronic conditions).
  - visit_occurrence_id (INTEGER, FK→visit_occurrence): Which visit this diagnosis came from.
  - condition_source_value (TEXT): Original source code (e.g., ICD-10 "E11.9").
Example query goal: "Find all patients with diabetes" → filter condition_concept_id=201826 (or descendants).
Example query goal: "Count unique patients diagnosed with hypertension" → 
  distinct count of person_id where condition_concept_id=320128.
""",

"""Table: drug_exposure
Purpose: Records prescriptions, medication administrations, and dispensings for patients.
Use this table when: studying medications, finding patients on a specific drug,
calculating drug exposure duration, or studying drug-disease relationships.
Key columns:
  - drug_exposure_id (INTEGER, PK): Unique ID for this drug record.
  - person_id (INTEGER, FK→person): The patient.
  - drug_concept_id (INTEGER, FK→concept): Standard RxNorm concept ID for the drug.
    Metformin = 1503297. Lisinopril = 1308216. Atorvastatin = 1545958.
  - drug_exposure_start_date (DATE): When the drug was started.
  - drug_exposure_end_date (DATE, nullable): When the drug was stopped.
  - days_supply (INTEGER, nullable): Number of days of medication supplied.
  - quantity (FLOAT, nullable): Quantity dispensed.
  - visit_occurrence_id (INTEGER, FK→visit_occurrence): Encounter where drug was prescribed.
Example query goal: "Find patients currently taking metformin" → filter drug_concept_id=1503297.
Example query goal: "Average duration of statin prescriptions" → mean of days_supply where drug_concept_id in statin concept set.
""",

"""Table: measurement
Purpose: Lab results, vital signs, and clinical measurements. Examples: blood glucose,
HbA1c, blood pressure, BMI, heart rate, cholesterol levels.
Use this table when: analyzing lab trends, finding patients with abnormal values,
studying clinical measurements over time.
Key columns:
  - measurement_id (INTEGER, PK): Unique ID.
  - person_id (INTEGER, FK→person): The patient.
  - measurement_concept_id (INTEGER, FK→concept): What was measured. 
    HbA1c = 3004410. Systolic BP = 3004249. Diastolic BP = 3012888. BMI = 3038553.
    Fasting blood glucose = 3037110. LDL cholesterol = 3028288.
  - measurement_date (DATE): When the measurement was taken.
  - value_as_number (FLOAT): The numeric result (e.g., 7.2 for HbA1c%).
  - value_as_concept_id (INTEGER, FK→concept): For categorical results (positive/negative).
  - unit_concept_id (INTEGER, FK→concept): Unit of measurement (mg/dL, mmHg, etc.)
  - range_low (FLOAT): Lower bound of normal range.
  - range_high (FLOAT): Upper bound of normal range.
Example query goal: "Find patients with HbA1c over 7%" → filter measurement_concept_id=3004410 AND value_as_number > 7.0.
""",

"""Table: observation
Purpose: Clinical facts not captured elsewhere — smoking status, pregnancy,
allergy records, patient-reported outcomes, social history.
Use this table when: studying behavioral risk factors, finding smokers,
looking at social determinants of health.
Key columns:
  - observation_id (INTEGER, PK): Unique ID.
  - person_id (INTEGER, FK→person): The patient.
  - observation_concept_id (INTEGER, FK→concept): What was observed.
    Smoking status = 4005823. Tobacco user = 4218917.
  - observation_date (DATE): When recorded.
  - value_as_string (TEXT): Free-text value for the observation.
  - value_as_concept_id (INTEGER): Coded value for the observation.
""",

"""Table: concept
Purpose: The master vocabulary table. OMOP maps all codes (ICD, SNOMED, RxNorm, LOINC, CPT)
to standard concept IDs. This table translates those IDs into human-readable names.
Use this table when: looking up what a concept_id means, searching for concept IDs by name,
or joining to get readable labels for your results.
Key columns:
  - concept_id (INTEGER, PK): The standard identifier used across all clinical tables.
  - concept_name (TEXT): Human-readable name (e.g., "Type 2 diabetes mellitus").
  - domain_id (TEXT): Which domain this concept belongs to (Condition, Drug, Measurement, etc.)
  - vocabulary_id (TEXT): Source vocabulary (SNOMED, RxNorm, LOINC, ICD10CM, etc.)
  - concept_code (TEXT): Original source code (e.g., "E11" for ICD-10 type 2 diabetes).
  - standard_concept (TEXT): 'S' = standard concept, 'C' = classification, null = non-standard.
Example query goal: "What is the name of concept_id 201826?" → select concept_name from concept where concept_id = 201826.
Example query goal: "Find the concept_id for 'atrial fibrillation'" → filter concept_name LIKE '%atrial fibrillation%' AND standard_concept='S'.
""",

"""Table: concept_relationship
Purpose: Maps relationships between concepts — most importantly, maps non-standard
source codes to standard OMOP concept IDs via the 'Maps to' relationship.
Use this table when: translating ICD-9/ICD-10/NDC codes to standard concept IDs,
finding hierarchical parent/child concept relationships.
Key columns:
  - concept_id_1 (INTEGER, FK→concept): Source concept.
  - concept_id_2 (INTEGER, FK→concept): Target concept.
  - relationship_id (TEXT): Type of relationship. 'Maps to' = standard mapping. 'Is a' = hierarchy.
Example query goal: "Map ICD-10 E11 to standard OMOP concept" → 
  join concept ON concept_code='E11' then join concept_relationship WHERE relationship_id='Maps to'.
""",

"""Table: location
Purpose: Geographic information about patients and care sites.
Key columns:
  - location_id (INTEGER, PK): Unique ID.
  - address_1, address_2 (TEXT): Street address.
  - city (TEXT): City name.
  - state (TEXT): Two-letter US state code (e.g., 'IL', 'NY', 'CA').
  - zip (TEXT): ZIP code.
  - county (TEXT): County name.
Example query goal: "Find patients living in Illinois" → join person ON location_id, filter location.state = 'IL'.
""",

"""Table: procedure_occurrence
Purpose: Medical procedures performed on patients (surgeries, imaging, labs ordered).
Key columns:
  - procedure_occurrence_id (INTEGER, PK): Unique ID.
  - person_id (INTEGER, FK→person): The patient.
  - procedure_concept_id (INTEGER, FK→concept): Standard CPT/SNOMED code for the procedure.
  - procedure_date (DATE): When it was performed.
  - visit_occurrence_id (INTEGER, FK→visit_occurrence): Encounter where it occurred.
""",

]  
const OMOP_SCHEMA_SOURCES = [
    "OMOP:person",
    "OMOP:visit_occurrence",
    "OMOP:condition_occurrence",
    "OMOP:drug_exposure",
    "OMOP:measurement",
    "OMOP:observation",
    "OMOP:concept",
    "OMOP:concept_relationship",
    "OMOP:location",
    "OMOP:procedure_occurrence",
]