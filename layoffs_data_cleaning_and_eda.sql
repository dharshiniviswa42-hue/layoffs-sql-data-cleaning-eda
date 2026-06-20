-- ============================================
-- LAYOFFS PROJECT — DATA CLEANING
-- ============================================

CREATE DATABASE layoffs_project;
USE layoffs_project;

-- Create a staging copy so the raw data stays untouched
CREATE TABLE layoffs_staging
LIKE layoffs;

INSERT layoffs_staging
SELECT * FROM layoffs;

SELECT * FROM layoffs_staging;


-- --------------------------------------------
-- STEP 1: REMOVE DUPLICATES
-- --------------------------------------------

-- Identify duplicates using ROW_NUMBER()
SELECT *,
ROW_NUMBER() OVER(
    PARTITION BY company, location, industry, total_laid_off,
                 percentage_laid_off, date, stage, country, funds_raised_millions
) AS row_num
FROM layoffs_staging;

-- View only the duplicate rows
WITH duplicate_cte AS (
    SELECT *,
    ROW_NUMBER() OVER(
        PARTITION BY company, location, industry, total_laid_off,
                     percentage_laid_off, date, stage, country, funds_raised_millions
    ) AS row_num
    FROM layoffs_staging
)
SELECT * FROM duplicate_cte
WHERE row_num > 1;

-- CTEs can't be deleted from directly, so create a second staging table with row_num included
CREATE TABLE layoffs_staging2 (
    company text,
    location text,
    industry text,
    total_laid_off int DEFAULT NULL,
    percentage_laid_off text,
    date text,
    stage text,
    country text,
    funds_raised_millions int DEFAULT NULL,
    row_num int
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO layoffs_staging2
SELECT *,
ROW_NUMBER() OVER(
    PARTITION BY company, location, industry, total_laid_off,
                 percentage_laid_off, date, stage, country, funds_raised_millions
) AS row_num
FROM layoffs_staging;

SET SQL_SAFE_UPDATES = 0;

DELETE FROM layoffs_staging2
WHERE row_num > 1;


-- --------------------------------------------
-- STEP 2: STANDARDIZE THE DATA
-- --------------------------------------------

-- Trim extra spaces from company names
UPDATE layoffs_staging2
SET company = TRIM(company);

-- Check industry values for inconsistencies
SELECT DISTINCT industry
FROM layoffs_staging2
ORDER BY 1;

-- Standardize all crypto-related variations into one value
UPDATE layoffs_staging2
SET industry = 'Crypto'
WHERE industry LIKE 'Crypto%';

-- Fix "United States." typo
UPDATE layoffs_staging2
SET country = 'United States'
WHERE country = 'United States.';

-- Convert date column from text to proper DATE type
UPDATE layoffs_staging2
SET date = STR_TO_DATE(date, '%m/%d/%Y');

ALTER TABLE layoffs_staging2
MODIFY COLUMN date DATE;


-- --------------------------------------------
-- STEP 3: HANDLE NULL / BLANK VALUES
-- --------------------------------------------

-- Convert blank industry values to NULL for consistency
UPDATE layoffs_staging2
SET industry = NULL
WHERE industry = '';

-- Fill missing industry using other rows of the same company
UPDATE layoffs_staging2 t1
JOIN layoffs_staging2 t2
    ON t1.company = t2.company
SET t1.industry = t2.industry
WHERE t1.industry IS NULL
AND t2.industry IS NOT NULL;

-- Rows with no total_laid_off AND no percentage_laid_off carry no analytical value
SELECT *
FROM layoffs_staging2
WHERE total_laid_off IS NULL
AND percentage_laid_off IS NULL;

DELETE FROM layoffs_staging2
WHERE total_laid_off IS NULL
AND percentage_laid_off IS NULL;


-- --------------------------------------------
-- STEP 4: REMOVE UNNECESSARY COLUMNS
-- --------------------------------------------

ALTER TABLE layoffs_staging2
DROP COLUMN row_num;

SELECT * FROM layoffs_staging2;


-- ============================================
-- EXPLORATORY DATA ANALYSIS (EDA)
-- ============================================

-- Highest single layoff event
SELECT MAX(total_laid_off)
FROM layoffs_staging2;

-- Highest and lowest percentage of workforce laid off
SELECT MAX(percentage_laid_off), MIN(percentage_laid_off)
FROM layoffs_staging2
WHERE percentage_laid_off IS NOT NULL;

-- Companies that laid off 100% of their workforce (effectively shut down)
SELECT *
FROM layoffs_staging2
WHERE percentage_laid_off = 1;

-- Same as above, ordered by how much funding they had raised
SELECT *
FROM layoffs_staging2
WHERE percentage_laid_off = 1
ORDER BY funds_raised_millions DESC;

-- Total layoffs by company
SELECT company, SUM(total_laid_off) AS total_laid_off
FROM layoffs_staging2
GROUP BY company
ORDER BY 2 DESC;

-- Total layoffs by industry
SELECT industry, SUM(total_laid_off) AS total_laid_off
FROM layoffs_staging2
GROUP BY industry
ORDER BY 2 DESC;

-- Total layoffs by country
SELECT country, SUM(total_laid_off) AS total_laid_off
FROM layoffs_staging2
GROUP BY country
ORDER BY 2 DESC;

-- Total layoffs by year
SELECT YEAR(date) AS year, SUM(total_laid_off) AS total_laid_off
FROM layoffs_staging2
GROUP BY YEAR(date)
ORDER BY 2 DESC;

-- Total layoffs by company funding stage
SELECT stage, SUM(total_laid_off) AS total_laid_off
FROM layoffs_staging2
GROUP BY stage
ORDER BY 2 DESC;

-- Average percentage laid off, by company
SELECT company, AVG(percentage_laid_off) AS avg_laid_off
FROM layoffs_staging2
GROUP BY company
ORDER BY 2 DESC;

-- Rolling total of layoffs per month
WITH Rolling_total AS
(
    SELECT SUBSTRING(date, 1, 7) AS month, SUM(total_laid_off) AS total_laid_off
    FROM layoffs_staging2
    WHERE SUBSTRING(date, 1, 7) IS NOT NULL
    GROUP BY month
    ORDER BY 1 ASC
)
SELECT month, total_laid_off,
SUM(total_laid_off) OVER(ORDER BY month) AS rolling_total
FROM Rolling_total;

-- Top 3 companies with the most layoffs, per year
WITH company_year AS
(
    SELECT company, YEAR(date) AS years,
    SUM(total_laid_off) AS total_laid_off
    FROM layoffs_staging2
    GROUP BY company, YEAR(date)
),
company_year_rank AS (
    SELECT company, years, total_laid_off,
    DENSE_RANK() OVER (PARTITION BY years ORDER BY total_laid_off DESC) AS ranking
    FROM company_year
)
SELECT company, years, total_laid_off, ranking
FROM company_year_rank
WHERE ranking <= 3
AND years IS NOT NULL
ORDER BY years ASC, total_laid_off DESC;
