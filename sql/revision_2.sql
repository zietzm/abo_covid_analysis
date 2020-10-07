SET SQL_MODE = '';

USE clinical_merge_v5_240919;

SET @start_of_covid_in_nyc = '2020-03-10';
SET @outcome_date = '2020-08-01';



--  Cleaned blood types table

DROP TABLE IF EXISTS user_mnz2108.abo_types;

CREATE TABLE user_mnz2108.abo_types AS
SELECT DISTINCT pat_mrn_id,
                CASE
                    WHEN abo_rh LIKE 'AB %' THEN 'AB'
                    WHEN abo_rh LIKE 'B %' THEN 'B'
                    WHEN abo_rh LIKE 'O %' THEN 'O'
                    WHEN abo_rh LIKE 'A %' THEN 'A'
                    END AS abo,
                CASE
                    WHEN abo_rh LIKE '%Pos%' OR abo_rh LIKE '%+%' THEN 'pos'
                    WHEN abo_rh LIKE '%Neg%' OR abo_rh LIKE '%-%' THEN 'neg'
                    END AS rh
FROM (
         SELECT pat_mrn_id, value_source_value AS abo_rh
         FROM concept_ancestor
                  INNER JOIN measurement ON descendant_concept_id = measurement_concept_id
                  INNER JOIN `2_covid_patient2person` ON measurement.person_id = `2_covid_patient2person`.person_id
         WHERE ancestor_concept_id = 40776356

         UNION

         -- Joining on LOINC codes (stored in 1_covid_measurements_noname as an integer without the check digit)
         SELECT pat_mrn_id, ord_value AS abo_rh
         FROM concept_ancestor
                  INNER JOIN concept ON descendant_concept_id = concept_id
                  INNER JOIN `2_covid_measurements_noname`
                             ON CAST(SUBSTRING(concept_code FROM 1 FOR CHAR_LENGTH(concept_code) - 2) AS UNSIGNED) =
                                component_loinc_code
         WHERE ancestor_concept_id = 40776356
           AND concept_code NOT REGEXP '[A-Za-z]'
           AND date_retrieved <= @outcome_date
     ) AS abo_rh_measurements
WHERE abo_rh != 'Invalid';

-- Remove patients having erroneous measurements, meaning incompatible blood type measurements
DROP TABLE IF EXISTS user_mnz2108.abo_cleaned_types;

CREATE TABLE user_mnz2108.abo_cleaned_types AS
SELECT *
FROM user_mnz2108.abo_types
WHERE pat_mrn_id NOT IN (SELECT pat_mrn_id FROM user_mnz2108.abo_types GROUP BY pat_mrn_id HAVING COUNT(*) > 1);

DROP TABLE user_mnz2108.abo_types;



--  Cleaned test results table

-- Remove inconclusive, erroneous, or cancelled tests, and remove a "patient" who is a stand-in for
-- an automated lab test procedure.
DROP TABLE IF EXISTS user_mnz2108.abo_cleaned_test_results;

CREATE TABLE user_mnz2108.abo_cleaned_test_results AS
SELECT pat_mrn_id,
       result_datetime AS test_result_datetime,
       CASE
           WHEN ord_value LIKE 'Detected%' THEN 'Test: positive'
           WHEN ord_value = 'yes' THEN 'Test: positive'
           WHEN ord_value LIKE 'Not detected%' THEN 'Test: negative'
           WHEN ord_value = 'sars-cov-2 neg' THEN 'Test: negative'
           WHEN ord_value = 'positive' THEN 'Test: positive'
           WHEN ord_value = 'negative' THEN 'Test: negative'
           END         AS event_desc
FROM `2_covid_labs_noname`
WHERE ord_value NOT IN ('Invalid', 'Indeterminate', '(null)', 'error', 'ERROR', 'Nasopharyngeal', 'See Comment',
                        'Not Given', 'Void', 'CANCELED')
  AND pat_mrn_id NOT IN (SELECT pat_mrn_id FROM `2_covid_persons_noname` WHERE pat_name LIKE 'AUTOMATEDLAB%')
  AND date_retrieved <= @outcome_date;

CREATE INDEX id ON user_mnz2108.abo_cleaned_test_results (pat_mrn_id);



--  MRNs for all patients with a SARS-CoV-2 test and consistent blood type

-- Combined cohort (people tested for infection and with a unique blood type)
DROP TABLE IF EXISTS user_mnz2108.abo_cohort_pat_mrns;

CREATE TABLE user_mnz2108.abo_cohort_pat_mrns AS
SELECT DISTINCT pat_mrn_id
FROM user_mnz2108.abo_cleaned_types
         INNER JOIN user_mnz2108.abo_cleaned_test_results USING (pat_mrn_id)
         INNER JOIN `2_covid_persons_noname` USING (pat_mrn_id);



--  Cohort entry and exit times table

-- Each patient's first positive test result. Only includes patients with a positive test.
DROP TABLE IF EXISTS user_mnz2108.abo_first_positive;

CREATE TABLE user_mnz2108.abo_first_positive AS
SELECT pat_mrn_id, MIN(test_result_datetime) AS test_result_datetime
FROM user_mnz2108.abo_cleaned_test_results
WHERE event_desc = 'Test: positive'
  AND pat_mrn_id IN (SELECT pat_mrn_id FROM user_mnz2108.abo_cohort_pat_mrns)
GROUP BY pat_mrn_id;

-- Cohort ENTRY times
-- IF first positive test result is either during or shortly after an encounter THEN encounter start time
-- ELSE first positive test result time
-- Since we are only joining on the earliest positive test result, the minimum of these is the encounter start time,
-- if an encounter qualifies, and the time of the first positive test result, otherwise.
DROP TABLE IF EXISTS user_mnz2108.abo_cohort_entry_times;

CREATE TABLE user_mnz2108.abo_cohort_entry_times AS
SELECT pat_mrn_id,
       MIN(IF((test_result_datetime >= hosp_admsn_time) AND
              (TIMEDIFF(test_result_datetime, hosp_admsn_time) <= TIME('96:00:00')),
              hosp_admsn_time, test_result_datetime)) AS cohort_entry_time
FROM user_mnz2108.abo_first_positive
         LEFT JOIN `2_covid_admission_noname` USING (pat_mrn_id)
GROUP BY pat_mrn_id;


-- Get MAXIMUM censor times based on encounters and days after cohort entry, IRRESPECTIVE of outcome
-- IF patient had an encounter starting before and ending after first positive test + 10 days, THEN the end of that encounter
-- ELSE cohort entry + 10 days
DROP TABLE IF EXISTS user_mnz2108.abo_max_censor_times;

CREATE TABLE user_mnz2108.abo_max_censor_times AS
SELECT pat_mrn_id,
       MAX(IF(hosp_admsn_time <= cohort_entry_plus_ten AND hosp_disch_time > cohort_entry_plus_ten,
              hosp_disch_time, cohort_entry_plus_ten)) AS max_censor_time
FROM (
         SELECT pat_mrn_id,
                DATE_ADD(cohort_entry_time, INTERVAL 10 DAY) AS cohort_entry_plus_ten,
                hosp_admsn_time,
                hosp_disch_time
         FROM user_mnz2108.abo_cohort_entry_times
                  LEFT JOIN `2_covid_admission_noname` USING (pat_mrn_id)
     ) AS possible_max_censor_times
GROUP BY pat_mrn_id;


-- Combine cohort entry with maximum censor time
DROP TABLE IF EXISTS user_mnz2108.abo_censor_min_max;

CREATE TABLE user_mnz2108.abo_censor_min_max AS
SELECT *
FROM user_mnz2108.abo_cohort_entry_times
         INNER JOIN user_mnz2108.abo_max_censor_times USING (pat_mrn_id);

DROP TABLE IF EXISTS user_mnz2108.abo_cohort_entry_times;
DROP TABLE IF EXISTS user_mnz2108.abo_max_censor_times;
DROP TABLE IF EXISTS user_mnz2108.abo_first_positive;


-- Patients are also censored by outcome occurrences.

-- Don't want to include people with a DNR/DNI in the comparison at all
DROP TABLE IF EXISTS user_mnz2108.abo_dni;

CREATE TABLE user_mnz2108.abo_dni AS
SELECT pat_mrn_id, MIN(order_date) AS dnr_date
FROM `2_covid_orders_noname`
WHERE description = 'DNR/DNI-DO NOT RESUSCITATE/DO NOT INTUBATE'
  AND pat_mrn_id IN (SELECT pat_mrn_id FROM user_mnz2108.abo_cohort_pat_mrns)
GROUP BY pat_mrn_id;


-- People censored by intubation
DROP TABLE IF EXISTS user_mnz2108.abo_intubations;

CREATE TABLE user_mnz2108.abo_intubations AS
SELECT pat_mrn_id, MIN(order_date) AS intubation_date, 1.0 AS intubated
FROM user_mnz2108.abo_censor_min_max
         LEFT JOIN `2_covid_intubation_orders_noname` USING (pat_mrn_id)
WHERE (order_status IS NULL OR order_status != 'Canceled')
  AND order_date >= cohort_entry_time
  AND order_date <= max_censor_time
  AND date_retrieved <= @outcome_date
GROUP BY pat_mrn_id;


-- People censored by death
DROP TABLE IF EXISTS user_mnz2108.abo_deaths;

CREATE TABLE user_mnz2108.abo_deaths AS
SELECT pat_mrn_id, death_date, 1.0 AS died
FROM user_mnz2108.abo_censor_min_max
         INNER JOIN patients_birth_death_12082020 USING (pat_mrn_id)
WHERE death_date <= max_censor_time;


-- Combine cohort entry and censoring with outcomes
DROP TABLE IF EXISTS user_mnz2108.abo_intubation_death;

CREATE TABLE user_mnz2108.abo_intubation_death AS
SELECT pat_mrn_id,
       cohort_entry_time,
       death_date,
       COALESCE(intubation_date, max_censor_time) AS intubation_censor_time,
       COALESCE(intubated, 0.0)                   AS intubated,
       COALESCE(death_date, max_censor_time)      AS death_censor_time,
       COALESCE(died, 0.0)                        AS died
FROM user_mnz2108.abo_censor_min_max
         LEFT JOIN user_mnz2108.abo_intubations USING (pat_mrn_id)
         LEFT JOIN user_mnz2108.abo_deaths USING (pat_mrn_id);

DROP TABLE IF EXISTS user_mnz2108.abo_censor_min_max;
DROP TABLE IF EXISTS user_mnz2108.abo_intubations;
DROP TABLE IF EXISTS user_mnz2108.abo_deaths;



--  Cleaned demographic data

DROP TABLE IF EXISTS user_mnz2108.abo_race;

CREATE TABLE user_mnz2108.abo_race AS
SELECT pat_mrn_id,
       CASE
           WHEN COUNT(DISTINCT race) = 1 THEN MAX(race)
           WHEN COUNT(DISTINCT race) = 0 THEN 'missing'
           ELSE 'other'
           END AS race
FROM (
         SELECT pat_mrn_id,
                CASE
                    WHEN race IN ('(null)', 'DECLINED') THEN NULL
                    WHEN race = 'WHITE' THEN 'white'
                    WHEN race = 'BLACK OR AFRICAN AMERICAN' THEN 'black'
                    WHEN race IN ('ASIAN', 'NAT.HAWAIIAN/OTH.PACIFIC ') THEN 'asian'
                    ELSE 'other'
                    END AS race
         FROM (
                  SELECT pat_mrn_id, race_1 AS race
                  FROM `2_covid_persons_noname`
                  UNION
                  SELECT pat_mrn_id, race_2 AS race
                  FROM `2_covid_persons_noname`
                  UNION
                  SELECT pat_mrn_id, race_3 AS race
                  FROM `2_covid_persons_noname`
              ) AS race_long
         WHERE pat_mrn_id IN (SELECT pat_mrn_id FROM user_mnz2108.abo_cohort_pat_mrns)
     ) AS cleaned_race
GROUP BY pat_mrn_id;



--  Combined demographic, blood type, intubation/death data

DROP TABLE IF EXISTS user_mnz2108.abo_basic;

CREATE TABLE user_mnz2108.abo_basic AS
SELECT pat_mrn_id,
       DATEDIFF(COALESCE(abo_intubation_death.death_date, NOW()), birth_date) / 365 AS age,
       IF(sex_desc = 'Male', 1., 0.)                                                AS male,
       race,
       IF(ethnicity = 'HISPANIC OR LATINO OR SPANISH ORIGIN', 1., 0.)               AS hispanic,
       abo,
       rh,
       cohort_entry_time,
       intubation_censor_time,
       intubated,
       dnr_date,
       death_censor_time,
       died
FROM user_mnz2108.abo_cohort_pat_mrns
         INNER JOIN `2_covid_persons_noname` USING (pat_mrn_id)
         INNER JOIN user_mnz2108.abo_race USING (pat_mrn_id)
         INNER JOIN user_mnz2108.abo_cleaned_types USING (pat_mrn_id)
         LEFT JOIN user_mnz2108.abo_intubation_death USING (pat_mrn_id)
         LEFT JOIN user_mnz2108.abo_dni USING (pat_mrn_id)
WHERE (intubation_censor_time IS NULL OR intubation_censor_time >= cohort_entry_time)
  AND (death_censor_time IS NULL OR death_censor_time >= cohort_entry_time);

DROP TABLE IF EXISTS user_mnz2108.abo_cohort_pat_mrns;
DROP TABLE IF EXISTS user_mnz2108.abo_race;
DROP TABLE IF EXISTS user_mnz2108.abo_cleaned_types;
DROP TABLE IF EXISTS user_mnz2108.abo_intubation_death;
DROP TABLE IF EXISTS user_mnz2108.abo_dni;

-- Compare the tested cohort with the general population = not tested for SARS-CoV-2

CREATE TABLE user_mnz2108.abo_general_population AS
SELECT DISTINCT pat_mrn_id,
                CASE
                    WHEN abo_rh LIKE 'AB %' THEN 'AB'
                    WHEN abo_rh LIKE 'B %' THEN 'B'
                    WHEN abo_rh LIKE 'O %' THEN 'O'
                    WHEN abo_rh LIKE 'A %' THEN 'A'
                    END AS abo,
                CASE
                    WHEN abo_rh LIKE '%Pos%' OR abo_rh LIKE '%+%' THEN 'pos'
                    WHEN abo_rh LIKE '%Neg%' OR abo_rh LIKE '%-%' THEN 'neg'
                    END AS rh
FROM (
         SELECT person_id AS pat_mrn_id, value_source_value AS abo_rh
         FROM concept_ancestor
                  INNER JOIN measurement ON descendant_concept_id = measurement_concept_id
         WHERE ancestor_concept_id = 40776356
           AND person_id NOT IN (SELECT person_id
                                 FROM `2_covid_labs_noname`
                                          INNER JOIN `2_covid_patient2person` USING (pat_mrn_id))

         UNION

         -- Joining on LOINC codes (stored in 1_covid_measurements_noname as an integer without the check digit)
         SELECT pat_mrn_id, ord_value AS abo_rh
         FROM concept_ancestor
                  INNER JOIN concept ON descendant_concept_id = concept_id
                  INNER JOIN `2_covid_measurements_noname`
                             ON CAST(SUBSTRING(concept_code FROM 1 FOR CHAR_LENGTH(concept_code) - 2) AS UNSIGNED) =
                                component_loinc_code
         WHERE ancestor_concept_id = 40776356
           AND concept_code NOT REGEXP '[A-Za-z]'
           AND date_retrieved <= @outcome_date
           AND pat_mrn_id NOT IN (SELECT pat_mrn_id FROM `2_covid_labs_noname`)
     ) AS abo_rh_measurements
WHERE abo_rh != 'Invalid';

-- Compute the frequency in the general population
CREATE TABLE user_mnz2108.abo_general_pop_freq AS
SELECT blood_type, COUNT(DISTINCT pat_mrn_id) AS N
FROM (
         SELECT pat_mrn_id, abo AS blood_type
         FROM user_mnz2108.abo_general_population
         UNION ALL
         SELECT pat_mrn_id, rh AS blood_type
         FROM user_mnz2108.abo_general_population
     ) AS general_pop
WHERE blood_type IS NOT NULL
  AND pat_mrn_id NOT IN (SELECT pat_mrn_id
                         FROM user_mnz2108.abo_general_population
                         GROUP BY pat_mrn_id
                         HAVING COUNT(*) > 1)
GROUP BY blood_type;

DROP TABLE user_mnz2108.abo_general_population;
