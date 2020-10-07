USE clinical_merge_v5_240919;

-- Our data is updated frequently, so we index it by the date of retrieval.
-- Risk factor definitions are versioned on GitHub (https://github.com/zietzm/phenotype_standardization/)
SET @date = '2020-06-15';
SET @version_hash = '66ec50743325ded678ab71acb1794a7f25bf8a85';

CREATE TABLE IF NOT EXISTS user_mnz2108.abo_covid_analysis_wide
(
    pat_mrn_id                           INT      NOT NULL,
    male_sex                             INT      NOT NULL,
    age                                  FLOAT    NOT NULL,
    ethnicity                            CHAR(10) NOT NULL,
    race                                 CHAR(10) NOT NULL,
    abo                                  CHAR(2)  NOT NULL,
    rh                                   CHAR(3)  NOT NULL,
    risk_factor_cardiovascular_disorders BOOLEAN  NOT NULL,
    risk_factor_diabetes_mellitus        BOOLEAN  NOT NULL,
    risk_factor_hypertension             BOOLEAN  NOT NULL,
    risk_factor_obesity                  BOOLEAN  NOT NULL,
    risk_factor_respiratory_disorders    BOOLEAN  NOT NULL,
    cov_pos                              BOOLEAN  NOT NULL,
    intubated                            BOOLEAN  NOT NULL,
    died                                 BOOLEAN  NOT NULL,
    date_retrieved                       DATE     NOT NULL,
    version_hash                         CHAR(40) NOT NULL
);

-- ----------------------------------
-- Temporarily cache blood group measurements (joined to itself to ensure consistent blood types for each person)
-- Caching this takes ~ 5-10 minutes
-- ----------------------------------

CREATE TABLE IF NOT EXISTS user_mnz2108.blood_groups AS (
    SELECT DISTINCT pat_mrn_id,
                    CASE
                        WHEN abo_rh LIKE 'AB%' THEN 'AB'
                        WHEN abo_rh LIKE 'B%' THEN 'B'
                        WHEN abo_rh LIKE 'O%' THEN 'O'
                        WHEN abo_rh LIKE 'A%' THEN 'A'
                        END AS abo,
                    CASE
                        WHEN abo_rh LIKE '%Pos%' OR abo_rh LIKE '%+%' OR
                             abo_rh LIKE '%pos%' THEN 'pos'
                        WHEN abo_rh LIKE '%Neg%' OR abo_rh LIKE '%-%' OR
                             abo_rh LIKE '%neg%' THEN 'neg'
                        END AS rh
    FROM (
             SELECT DISTINCT pat_mrn_id, value_source_value AS abo_rh
             FROM concept_ancestor
                      INNER JOIN measurement ON descendant_concept_id = measurement_concept_id
                      INNER JOIN 1_covid_patient2person ON measurement.person_id = 1_covid_patient2person.person_id
             WHERE ancestor_concept_id = 40776356

             UNION ALL

             -- Joining on LOINC codes (stored in 1_covid_measurements_noname as an integer without the check digit)
             SELECT DISTINCT pat_mrn_id, ord_value AS abo_rh
             FROM concept_ancestor
                      INNER JOIN concept ON descendant_concept_id = concept_id
                      INNER JOIN 1_covid_measurements_noname
                                 ON CAST(SUBSTRING(concept_code FROM 1 FOR CHAR_LENGTH(concept_code) - 2) AS UNSIGNED) =
                                    component_loinc_code
             WHERE ancestor_concept_id = 40776356
               AND concept_code NOT REGEXP '[A-Za-z]'
               AND date_retrieved = @date
         ) AS abo_rh_measurements
    WHERE abo_rh != 'Invalid'
);

-- ----------------------------------
-- Temporarily cache risk factors (long query processed again in building the main table)
-- Caching this takes ~ 7 minutes
-- ----------------------------------

CREATE TABLE IF NOT EXISTS user_mnz2108.blood_group_risk_factors AS (
    SELECT *
    FROM (
             -- cardiovascular_disorders
             SELECT DISTINCT pat_mrn_id, 'cardiovascular_disorders' AS risk_factor
             FROM (
                      -- From COVID table (descendants of OMOP 134057 mapped to ICD-10 CM)
                      SELECT DISTINCT pat_mrn_id
                      FROM concept_ancestor
                               INNER JOIN concept_relationship ON descendant_concept_id = concept_id_1
                               INNER JOIN concept ON concept_id_2 = concept_id
                               INNER JOIN 1_covid_patients_noname ON concept_code = REPLACE(icd10_code, ',', '')
                      WHERE ancestor_concept_id = 134057
                        AND relationship_id IN ('Included in map from', 'Mapped from')
                        AND vocabulary_id = 'ICD10CM'
                        AND date_retrieved = @date

                      UNION ALL

                      -- From OMOP table (descendants of OMOP 134057)
                      SELECT DISTINCT pat_mrn_id
                      FROM concept_ancestor
                               INNER JOIN condition_occurrence ON descendant_concept_id = condition_concept_id
                               INNER JOIN 1_covid_patient2person USING (person_id)
                      WHERE ancestor_concept_id = 134057
                  ) AS cv_disease_patients

             UNION ALL

             -- diabetes_mellitus
             SELECT DISTINCT pat_mrn_id, 'diabetes_mellitus' AS risk_factor
             FROM (
                      -- From OMOP table (SNOMED)
                      SELECT DISTINCT pat_mrn_id
                      FROM concept_ancestor
                               INNER JOIN condition_occurrence ON descendant_concept_id = condition_concept_id
                               INNER JOIN 1_covid_patient2person USING (person_id)
                      WHERE ancestor_concept_id = 201820

                      UNION ALL

                      -- From COVID table (ICD10)
                      SELECT DISTINCT pat_mrn_id
                      FROM 1_covid_patients_noname
                      WHERE date_retrieved = @date
                        AND (
                              icd10_code LIKE 'E08%' OR icd10_code LIKE 'E09%' OR
                              icd10_code LIKE 'E10%' OR icd10_code LIKE 'E11%' OR icd10_code LIKE 'E13%'
                          )

                      UNION ALL

                      -- From OMOP table (HbA1c >= 6.5)
                      SELECT DISTINCT pat_mrn_id
                      FROM measurement
                               INNER JOIN 1_covid_patient2person USING (person_id)
                      WHERE measurement_concept_id IN (3004410, 3005673, 40758583)
                        AND value_source_value REGEXP '^[<>%0-9.]+$'
                        AND CAST(REPLACE(REPLACE(REPLACE(value_source_value, '<', ''), '>', ''), '%',
                                         '') AS DECIMAL(10, 5)) >=
                            6.5

                      UNION ALL

                      -- From COVID table (HbA1c >= 6.5)
                      SELECT DISTINCT pat_mrn_id
                      FROM 1_covid_measurements_noname
                      WHERE date_retrieved = @date
                        AND component_loinc_code IN (4548, 17856)
                        AND ord_value REGEXP '^[<>%0-9.]+$'
                        AND CAST(REPLACE(REPLACE(REPLACE(ord_value, '<', ''), '>', ''), '%', '') AS DECIMAL(10, 5)) >=
                            6.5
                  ) AS dm_patients

             UNION ALL

             -- hypertension
             SELECT DISTINCT pat_mrn_id, 'hypertension' AS risk_factor
             FROM (
                      -- From COVID table (descendants of OMOP 316866 mapped to ICD-10 CM)
                      SELECT DISTINCT pat_mrn_id
                      FROM concept_ancestor
                               INNER JOIN concept_relationship ON descendant_concept_id = concept_id_1
                               INNER JOIN concept ON concept_id_2 = concept_id
                               INNER JOIN 1_covid_patients_noname ON concept_code = REPLACE(icd10_code, ',', '')
                      WHERE ancestor_concept_id = 316866
                        AND relationship_id IN ('Included in map from', 'Mapped from')
                        AND vocabulary_id = 'ICD10CM'
                        AND date_retrieved = @date

                      UNION ALL

                      -- From OMOP table (descendants of OMOP 316866)
                      SELECT DISTINCT pat_mrn_id
                      FROM concept_ancestor
                               INNER JOIN condition_occurrence ON descendant_concept_id = condition_concept_id
                               INNER JOIN 1_covid_patient2person USING (person_id)
                      WHERE ancestor_concept_id = 316866
                  ) AS hypertensive_patients

             UNION ALL

             -- obesity
             SELECT DISTINCT pat_mrn_id, 'obesity' AS risk_factor
             FROM (
                      -- From COVID table (BMI > 30)
                      SELECT DISTINCT pat_mrn_id
                      FROM 1_covid_vitals_noname
                      WHERE date_retrieved = @date
                        AND bmi >= 30

                      UNION ALL

                      -- From OMOP table (BMI > 30)
                      SELECT DISTINCT pat_mrn_id
                      FROM measurement
                               INNER JOIN 1_covid_patient2person USING (person_id)
                      WHERE measurement_concept_id = 3038553
                        AND measurement_date >= '2019-01-01'
                        AND value_as_number >= 30

                      UNION ALL

                      -- From OMOP table (diagnosis code descendant of 4215968)
                      SELECT DISTINCT pat_mrn_id
                      FROM observation
                               INNER JOIN concept_ancestor ON observation_concept_id = descendant_concept_id
                               INNER JOIN 1_covid_patient2person USING (person_id)
                      WHERE ancestor_concept_id = 4215968

                      UNION ALL

                      -- From OMOP table (BMI percentile > 95%)
                      SELECT DISTINCT pat_mrn_id
                      FROM measurement
                               INNER JOIN 1_covid_patient2person USING (person_id)
                      WHERE measurement_concept_id = 40762636
                        AND measurement_date >= '2019-01-01'
                        AND value_as_number >= 95
                  ) AS ob_patients

             UNION ALL

             -- respiratory_disorders
             SELECT DISTINCT pat_mrn_id, 'respiratory_disorders' AS risk_factor
             FROM (
                      -- From COVID table (descendants of OMOP 320136 mapped to ICD-10 CM)
                      SELECT DISTINCT pat_mrn_id
                      FROM concept_ancestor
                               INNER JOIN concept_relationship ON descendant_concept_id = concept_id_1
                               INNER JOIN concept ON concept_id_2 = concept_id
                               INNER JOIN 1_covid_patients_noname ON concept_code = REPLACE(icd10_code, ',', '')
                      WHERE ancestor_concept_id = 320136
                        AND relationship_id IN ('Included in map from', 'Mapped from')
                        AND vocabulary_id = 'ICD10CM'
                        AND date_retrieved = @date

                      UNION ALL

                      -- From OMOP table (descendants of OMOP 320136)
                      SELECT DISTINCT pat_mrn_id
                      FROM concept_ancestor
                               INNER JOIN condition_occurrence ON descendant_concept_id = condition_concept_id
                               INNER JOIN 1_covid_patient2person USING (person_id)
                      WHERE ancestor_concept_id = 320136
                  ) AS respiratory_disease_patients) AS full_risk_factors
);

-- ----------------------------------
-- Permanently cache the analysis table (so the actual analysis is quick)
-- Caching this takes ~ < 1 minute
-- ----------------------------------

INSERT INTO user_mnz2108.abo_covid_analysis_wide
SELECT 1_covid_persons_noname.pat_mrn_id,
       -- Sex (using female as reference)
       IF(sex_desc = 'Male', 1.0, 0.0)                                               AS male_sex,
       -- Age - either current age or age at death
       DATEDIFF(IF(death_date > 0, DATE(death_date), @date), DATE(birth_date)) / 365 AS age,
       -- Ethnicity
       CASE
           WHEN ethnicity = 'HISPANIC OR LATINO OR SPANISH ORIGIN' THEN 'hs'
           WHEN ethnicity = 'NOT HISPANIC OR LATINO OR SPANISH ORIGIN' THEN 'nonhs'

           -- These are all small minority responses
           WHEN ethnicity = 'MULTI-RACIAL' THEN 'other'
           WHEN ethnicity = 'AFRICAN AMERICAN' THEN 'other'
           WHEN ethnicity = 'CAUCASIAN' THEN 'other'
           WHEN ethnicity = 'ASIAN / PACIFIC ISLANDER' THEN 'other'
           WHEN ethnicity = 'AMERICAN INDIAN / ESKIMO' THEN 'other'

           WHEN ethnicity = '(null)' THEN 'missing'
           WHEN ethnicity = 'DECLINED' THEN 'missing'
           WHEN ethnicity = 'UNKNOWN' THEN 'missing'
           END                                                                       AS ethnicity,
       -- Race
       CASE
           WHEN race_1 = 'WHITE' THEN 'white'
           WHEN race_1 = 'BLACK OR AFRICAN AMERICAN' THEN 'black_aa'
           WHEN race_1 = 'ASIAN' THEN 'asian'

           -- These are all small minority responses
           WHEN race_1 = 'OTHER COMBINATIONS NOT DESCRIBED' THEN 'other'
           WHEN race_1 = 'NAT.HAWAIIAN/OTH.PACIFIC ISLAND' THEN 'other'
           WHEN race_1 = 'AMERICAN INDIAN OR ALASKA NATION' THEN 'other'
           WHEN race_1 = 'ASHKENAZI JEWISH' THEN 'other'
           WHEN race_1 = 'SEPHARDIC JEWISH' THEN 'other'

           WHEN race_1 = 'DECLINED' THEN 'missing'
           WHEN race_1 = '(null)' THEN 'missing'
           END                                                                       AS race,
       abo,
       rh,
       COALESCE(risk_factor_cardiovascular_disorders, 0)                             AS risk_factor_cardiovascular_disorders,
       COALESCE(risk_factor_diabetes_mellitus, 0)                                    AS risk_factor_diabetes_mellitus,
       COALESCE(risk_factor_hypertension, 0)                                         AS risk_factor_hypertension,
       COALESCE(risk_factor_obesity, 0)                                              AS risk_factor_obesity,
       COALESCE(risk_factor_respiratory_disorders, 0)                                AS risk_factor_respiratory_disorders,
       cov_pos,
       COALESCE(intubated, FALSE)                                                    AS intubated,
       (death_date > 0)                                                              AS died,
       @date                                                                         AS date_retrieved,
       @version_hash                                                                 AS version_hash
FROM 1_covid_persons_noname

-- SARS-CoV-2 test results (only investigating tested individuals)
         INNER JOIN (
    SELECT pat_mrn_id, MAX(ord_value LIKE 'Detected%') AS cov_pos
    FROM 1_covid_labs_noname
    WHERE date_retrieved = @date
      AND ord_value NOT IN ('Invalid', 'Indeterminate', 'Nasopharyngeal', 'Not Given',
                            'Void', 'See Comment', 'Yes')
    GROUP BY pat_mrn_id
) AS test_results USING (pat_mrn_id)

-- Patient blood groups (only investigating individuals with known type)
         INNER JOIN (
    SELECT DISTINCT blood_groups.pat_mrn_id, abo, rh
    FROM user_mnz2108.blood_groups AS blood_groups
             INNER JOIN (
        SELECT pat_mrn_id
        FROM user_mnz2108.blood_groups
        GROUP BY pat_mrn_id
        HAVING COUNT(DISTINCT abo, rh) = 1
    ) AS consistently_typed ON blood_groups.pat_mrn_id = consistently_typed.pat_mrn_id
) AS blood_groups USING (pat_mrn_id)

-- Intubation orders
         LEFT JOIN (
    SELECT DISTINCT pat_mrn_id, TRUE AS intubated
    FROM 1_covid_intubation_orders_noname
    WHERE order_date >= '2020-03-01'
      AND date_retrieved = @date
) AS intubation_orders USING (pat_mrn_id)

-- Risk factors
         LEFT JOIN (
    SELECT pat_mrn_id,
           COUNT(IF(risk_factor = 'cardiovascular_disorders', 1, NULL)) AS risk_factor_cardiovascular_disorders,
           COUNT(IF(risk_factor = 'diabetes_mellitus', 1, NULL))        AS risk_factor_diabetes_mellitus,
           COUNT(IF(risk_factor = 'hypertension', 1, NULL))             AS risk_factor_hypertension,
           COUNT(IF(risk_factor = 'obesity', 1, NULL))                  AS risk_factor_obesity,
           COUNT(IF(risk_factor = 'respiratory_disorders', 1, NULL))    AS risk_factor_respiratory_disorders
    FROM user_mnz2108.blood_group_risk_factors
    GROUP BY pat_mrn_id
) AS risk_factors ON 1_covid_persons_noname.pat_mrn_id = risk_factors.pat_mrn_id

WHERE sex_desc IN ('Male', 'Female')
  AND 1_covid_persons_noname.pat_mrn_id IS NOT NULL
  AND 1_covid_persons_noname.pat_mrn_id > 0
HAVING age >= 18;

-- Clean up the temporarily-created tables
DROP TABLE user_mnz2108.blood_groups;
DROP TABLE user_mnz2108.blood_group_risk_factors;

-- ----------------------------------
-- Cache general population blood group distribution
-- Caching this takes ~ < 1 minute
-- ----------------------------------

CREATE TABLE IF NOT EXISTS user_mnz2108.blood_groups_general_population AS (
    SELECT abo, rh, COUNT(DISTINCT person_id) AS n, @date AS date_retrieved
    FROM (
             SELECT DISTINCT person_id,
                             CASE
                                 WHEN value_source_value LIKE 'AB%' THEN 'AB'
                                 WHEN value_source_value LIKE 'B%' THEN 'B'
                                 WHEN value_source_value LIKE 'O%' THEN 'O'
                                 WHEN value_source_value LIKE 'A%' THEN 'A'
                                 END AS abo,
                             CASE
                                 WHEN value_source_value LIKE '%Pos%' OR value_source_value LIKE '%+%' OR
                                      value_source_value LIKE '%pos%' THEN 'pos'
                                 WHEN value_source_value LIKE '%Neg%' OR value_source_value LIKE '%-%' OR
                                      value_source_value LIKE '%neg%' THEN 'neg'
                                 END AS rh
             FROM concept_ancestor
                      INNER JOIN measurement ON descendant_concept_id = measurement_concept_id
             WHERE ancestor_concept_id = 40776356
               AND value_source_value != 'Invalid'
         ) AS blood_group_measurements
    WHERE rh IN ('pos', 'neg')
      AND person_id NOT IN (
        -- Remove people tested for SARS-CoV-2 infection
        SELECT DISTINCT person_id
        FROM 1_covid_labs_noname
                 INNER JOIN 1_covid_patient2person USING (pat_mrn_id)
        WHERE date_retrieved = @date
    )
    GROUP BY abo, rh);
