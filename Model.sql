USE CrimeProject
GO

CREATE SCHEMA Dim
GO

--SELECT * FROM Drug.DeathbyRegion -- deaths by YEAR and REGION 
--SELECT * FROM Drug.AdmissionsNHSRegion -- admissions by YEAR and REGION and GENDER
--SELECT * FROM Drug.SeizuresForceArea -- seizures by YEAR and FORCE AREA
SELECT * FROM Drug.SeizuresSnapshot17 -- seizures by FORCE AREA and DRUG (2017)
--SELECT * FROM Drug.SurveyData -- drug use by YEAR and REGION and DRUG
--SELECT * FROM Geo.AreaCompare -- LSOA by FORCE AREA by REGION
--SELECT * FROM Geo.DeprivationRanksLSOA -- deprivation rank by LSOA (England)
--SELECT * FROM Geo.ForceArea -- area size and poly by FORCE AREA
--SELECT * FROM Geo.LSOA -- area size and poly by LSOA
SELECT * FROM Geo.PopulationLSOA -- population by YEAR and LSOA
--SELECT * FROM Geo.WalesDeprivationRanksLSOA -- deprivation rank by LSOA (Wales)
SELECT * FROM Police.CrimeDataStopSearch -- data by DATETIME(minute) and LSOA and CRIME TYPE (object) and GENDER
SELECT * FROM Police.MatchedStreet -- data by YEAR and MONTH and LSOA and CRIME TYPE
--SELECT * FROM Police.TaserUse -- taser incidents by YEAR and FORCE AREA
--SELECT * FROM Weapons.BladedOffenceByAge -- minor/adult offences by YEAR and QUARTER
--SELECT * FROM Weapons.BladedOffenceByArea -- offences by YEAR and FORCE AREA
--SELECT * FROM Weapons.BladedOffenceByOffence -- various offences by YEAR 
--SELECT * FROM Weapons.BladedOffenceByOutcome -- offence outcomes by YEAR and QUARTER
--SELECT * FROM Weapons.FirearmCertificatesForceArea -- certificate applications/totals and firearms by YEAR and FORCE AREA
--SELECT * FROM Weapons.FirearmDealersForceArea -- dealer license applications/totals by YEAR and FORCE AREA
--SELECT * FROM Weapons.FirearmOffenceByArea -- offences by YEAR and FORCE AREA
--SELECT * FROM Weapons.FirearmOffenceByInjury -- nationwide injury types by YEAR
--SELECT * FROM Weapons.FirearmOffenceByLocationType -- nationwide offence locations by YEAR
--SELECT * FROM Weapons.FirearmOffenceByOffence -- nationwide offence types by YEAR
SELECT * FROM Weapons.GunsAgeForceArea -- firearm/shotgun certificates by YEAR and FORCE AREA and AGE (age needs unpivoting)
SELECT * FROM Weapons.GunsGenderForceArea -- firearm/shotgun certificates by YEAR and FORCE AREA and GENDER (gender needs unpivoting)
--SELECT * FROM Weapons.ShotgunCertificatesForceArea -- certificate applications/totals and firearms by YEAR and FORCE AREA


/*---------------------------------------------
    Creating Dim.GeoEngland and Dim.GeoWales
----------------------------------------------*/
-- For Region to ForceArea to LSOA
	-- including deprivation indice ranks
		-- 1 being the most deprived
-- ENGLAND
SELECT
	 a.[Region name]
	,a.[Region code]
	,a.[Force area]
	,a.[Force area code] AS [Force code]
	,f.[Area (sqkm)] AS [Force size (sqkm)]
	,a.[LSOA name]
	,a.[LSOA code]
	,l.[Area (sqkm)] AS [LSOA size (sqkm)]
	,d.[Multiple deprivation]
    ,d.[Income deprivation]
    ,d.[Income deprivation (children)]
    ,d.[Income deprivation (elderly)]
    ,d.[Employment deprivation]
    ,d.[Education/skills/training dep] AS [Education deprivation]
    ,d.[Health deprivation]
    ,d.[Crime]
    ,d.[Barriers to housing/services]
    ,d.[Living environment dep]
    ,d.[Youth deprivation]
    ,d.[Adult skills deprivation]
    ,d.[Geographical barriers]
    ,d.[Wider barriers]
    ,d.[Indoors deprivation]
    ,d.[Outdoors deprivation]
INTO Dim.GeoEngland
FROM Geo.AreaCompare a
JOIN Geo.LSOA l
	on a.[LSOA code]=l.[lsoa code]
JOIN Geo.ForceArea f
	on a.[Force area code] = f.[Area code]
JOIN Geo.DeprivationRanksLSOA d
	on d.[LSOA code] = a.[LSOA code]
-- Adding primary id key
ALTER TABLE Dim.GeoEngland
	Add id int identity primary key

-- WALES
SELECT
	 a.[Region name]
	,a.[Region code]
	,a.[Force area]
	,a.[Force area code] AS [Force code]
	,f.[Area (sqkm)] AS [Force size (sqkm)]
	,a.[LSOA name]
	,a.[LSOA code]
	,l.[Area (sqkm)] AS [LSOA size (sqkm)]
	,w.[Multiple deprivation]
    ,w.[Income deprivation]
    ,w.[Employment deprivation]
    ,w.[Education deprivation]
    ,w.[Health deprivation]
    ,w.[Crime]
    ,w.[Barriers to housing]
	,w.[Barriers to services]
    ,w.[Living environment dep]
INTO Dim.GeoWales
FROM Geo.AreaCompare a
JOIN Geo.LSOA l
	on a.[LSOA code]=l.[lsoa code]
JOIN Geo.ForceArea f
	on a.[Force area code] = f.[Area code]
JOIN Geo.WalesDeprivationRanksLSOA w
	on w.[LSOA code] = a.[LSOA code]
-- Adding primary id key
ALTER TABLE Dim.GeoWales
	Add id int identity primary key


/*--------------------------
    Creating Dim.DateTime
---------------------------*/
-- CTE to union starting anchor date with dateadds
;WITH DatesUnion
AS
(
--anchor
SELECT
     CAST('2005-01-01' AS DATETIME) AS [DateTime] -- Main anchor point
    ,YEAR(CAST('2005-01-01' AS DATETIME)) [Year] -- Derived year
	,CASE
        WHEN MONTH(CAST('2005-01-01' AS DATETIME)) BETWEEN 3 AND 5
        THEN 'Spring'
        WHEN MONTH(CAST('2005-01-01' AS DATETIME)) BETWEEN 6 AND 8
        THEN 'Summer'
        WHEN MONTH(CAST('2005-01-01' AS DATETIME)) BETWEEN 9 AND 11
        THEN 'Autumn'
        ELSE 'Winter'
     END AS [Season] -- Derived season
	,DATEPART(QUARTER,CAST('2005-01-01' AS DATETIME)) [Quarter] -- Derived quarter
    ,MONTH(CAST('2005-01-01' AS DATETIME)) [Month] -- Derived month
    ,DATEPART(dd, CAST('2005-01-01' AS DATETIME)) [Day] -- Derived day (of month)
    ,DATENAME(dw, (CAST('2005-01-01' AS DATETIME))) [DayName] -- Derived day (name)
    ,CASE
        WHEN DATENAME(dw, (CAST('2005-01-01' AS DATETIME))) LIKE 'S%'
        THEN 0
        ELSE 1
     END as [WeekdayFlag] -- Is it a weekday? 1=y 0=n
	 ,DATEPART(hh, CAST('2005-01-01' AS DATETIME)) [Hour] -- Derived hour
	 ,DATEPART(mi, CAST('2005-01-01' AS DATETIME)) [Minute] -- Derived minute
UNION ALL
SELECT -- Creating a new row for every 5 minute interval
     DATEADD(mi, 5, [DateTime])
    ,YEAR(DATEADD(mi, 5, [DateTime]))
	,CASE
        WHEN MONTH(DATEADD(mi, 5, [DateTime])) BETWEEN 3 AND 5
        THEN 'Spring'
        WHEN MONTH(DATEADD(mi, 5, [DateTime])) BETWEEN 6 AND 8
        THEN 'Summer'
        WHEN MONTH(DATEADD(mi, 5, [DateTime])) BETWEEN 9 AND 11
        THEN 'Autumn'
        ELSE 'Winter'
     END AS season
	,DATEPART(QUARTER,DATEADD(mi, 5, [DateTime]))
    ,MONTH(DATEADD(mi, 5, [DateTime]))
    ,DATEPART(dd, DATEADD(mi, 5, [DateTime]))
    ,DATENAME(dw, DATEADD(mi, 5, [DateTime]))
    ,CASE
        WHEN DATENAME(dw, DATEADD(mi, 5, [DateTime])) LIKE 'S%'
        THEN 0
        ELSE 1
     END as isweekday
	 ,DATEPART(hh, DATEADD(mi, 5, [DateTime])) 
	 ,DATEPART(mi, DATEADD(mi, 5, [DateTime])) 
FROM DatesUnion
WHERE DATEADD(dd, 1, [DateTime]) < GETDATE()
)
SELECT *
INTO Dim.[DateTime]
FROM DatesUnion
OPTION (maxrecursion 0)
-- Adding primary id key
ALTER TABLE Dim.[DateTime]
	Add id int identity primary key


/*---------------------------------
    Creating Dim.YearlyForceArea
----------------------------------*/
;with Years as (
SELECT DISTINCT
	[Year]
FROM dim.[DateTime]
WHERE [Year] > 2008
)
, ForceAreas as (
SELECT DISTINCT
	 [Force area]
	,[Force code]
FROM Dim.GeoEngland
UNION
SELECT DISTINCT
	 [Force area]
	,[Force code]
FROM Dim.GeoWales
)
, DimStart as (
SELECT
	*
FROM Years
cross join ForceAreas
)
-- Actual dim table builder
SELECT
	 dim.*
	,ds.[Drug seizures] AS [Police drug seizures]
	,pt.[Taser incidents] AS [Police taser incidents]
	,bo.Offences AS [Bladed offences]
	,fo.Offences AS [Firearm offences]
	,fc.[New applications granted] + sc.[New applications granted]
	+fc.[Renewal applications granted] + sc.[Renewal applications granted] 
	 AS [Firearm licenses granted]
	,fc.[New applications refused] + sc.[New applications refused]
	+fc.[Renewal applications refused] + sc.[Renewal applications refused]
	+fc.Revocations + sc.Revocations AS [Firearm licenses refused/revoked]
	,fc.[Total on issue (31/03)] + sc.[Total on issue (31/03)]
	 AS [Firearm certificates on issue]
	,fc.[Total firearms (31/03)] + sc.[Total shotguns (31/03)]
	 AS [Licensed firearms]
	,fd.[Total dealers (31/03)] AS [Firearm dealers]
INTO dim.YearlyForceArea
FROM DimStart dim
LEFT JOIN Drug.SeizuresForceArea ds
	on dim.[Year] = ds.[Year]
	AND dim.[Force code] = ds.[Area code]
LEFT JOIN police.TaserUse pt
	-- [Year] in taser table is ntext so need to two-step convert
	on dim.[Year] = Convert(int,Convert(varchar(100),pt.[Year]))
	AND dim.[Force code] = pt.[Area code]
LEFT JOIN Weapons.BladedOffenceByArea bo
	on dim.[Year] = bo.[Date]
	AND CASE -- Fixing disparity in force area name (Northumberland v.s. Northumbria)
		WHEN dim.[Force area] = 'Northumbria' AND bo.[Area] = 'Northumberland' THEN 1
		WHEN dim.[Force area] = bo.[Area] THEN 1
		ELSE 0
	END = 1
LEFT JOIN Weapons.FirearmOffenceByArea fo
	on dim.[Year] = fo.[Date (March)]
	AND CASE -- Fixing mistake in fo value for City of London
		WHEN dim.[Force area] = 'City of London' AND fo.[Area] = 'City  of London' THEN 1
		WHEN dim.[Force area] = fo.[Area] THEN 1
		ELSE 0
	END = 1
LEFT JOIN Weapons.FirearmCertificatesForceArea fc
	on dim.[Year] = fc.[Year]
	AND CASE -- Fixing mistake in fc value for City of London
		WHEN dim.[Force area] = 'City of London' AND fc.[Police force area] = 'London, City of' THEN 1
		WHEN dim.[Force area] = fc.[Police force area] THEN 1
		ELSE 0
	END = 1
LEFT JOIN Weapons.ShotgunCertificatesForceArea sc
	on dim.[Year] = sc.[Year]
	AND CASE -- Fixing mistake in fc value for City of London
		WHEN dim.[Force area] = 'City of London' AND sc.[Police force area] = 'London, City of' THEN 1
		WHEN dim.[Force area] = sc.[Police force area] THEN 1
		ELSE 0
	END = 1
LEFT JOIN Weapons.FirearmDealersForceArea fd
	on dim.[Year] = fd.[Year]
	AND CASE -- Fixing mistake in fc value for City of London
		WHEN dim.[Force area] = 'City of London' AND fd.[Police force area] = 'London, City of' THEN 1
		WHEN dim.[Force area] = fd.[Police force area] THEN 1
		ELSE 0
	END = 1
ORDER BY [Year], [Force area]
-- Adding primary id key
ALTER TABLE Dim.YearlyForceArea
	Add id int identity primary key


/*------------------------------
    Creating Dim.YearlyRegion
-------------------------------*/
-- Pivoting a couple of tables to fit in this dim
	-- Drug.AdmissionsNHSRegion, pivot gender
	-- Drug.SurveyData, pivot drug
ALTER SCHEMA temp TRANSFER Drug.AdmissionsNHSRegion
ALTER SCHEMA temp TRANSFER Drug.SurveyData
-- Pivoted in Alteryx, ready to created dim
;with Years as (
SELECT DISTINCT
	[Year]
FROM dim.[DateTime]
)
, Regions as (
SELECT DISTINCT
	 [Region name]
	,[Region code]
FROM Dim.GeoEngland
UNION
SELECT DISTINCT
	 [Region name]
	,[Region code]
FROM Dim.GeoWales
)
, DimStart as (
SELECT
	*
FROM Years
cross join Regions
)
-- Actual dim table builder
SELECT 
	 dim.*
	,sd.[Drug users (% of pop)]
	,sd.[Cannabis users (% of pop)]
	,sd.[Class A users (% of pop)]
	,sd.[Cocaine users (% of pop)]
	,sd.[Ecstasy users (% of pop)]
	,sd.[Amphetamine users (% of pop)]
	,sd.[Hallucinogen users (% of pop)]
	,dr.[Deaths (misuse)] AS [Drug misuse deaths]
	,dr.[Deaths (poison)] AS [Drug poison deaths]
	,nhs.[NHS admissions (drug mental health male)]
	,nhs.[NHS admissions (drug mental health female)]
	,nhs.[NHS admissions (drug poisoning male)]
	,nhs.[NHS admissions (drug poisoning female)]
INTO dim.YearlyRegion
FROM DimStart dim
LEFT JOIN drug.DeathByRegion dr
	on dim.[Year] = dr.[Year]
	AND dim.[Region code] = dr.[Region code]
LEFT JOIN drug.AdmissionsNHSRegion nhs
	on dim.[Year] = nhs.[Year]
	AND dim.[Region code] = nhs.[Region code]
LEFT JOIN drug.SurveyData sd
	on dim.[Year] = sd.[Year]
	AND dim.[Region code] = sd.[Region code]
-- Adding primary id key
ALTER TABLE Dim.YearlyRegion
	Add id int identity primary key


/*----------------------------------
    Creating Dim.YearlyNationwide
-----------------------------------*/
;with Years as (
SELECT DISTINCT
	[Year]
FROM dim.[DateTime]
WHERE [Year] < 2018
)
,KnifeAge as (
SELECT
	[Year], SUM(Minor) as Minor, SUM(Adult) as Adult
FROM Weapons.BladedOffenceByAge
WHERE [Year] between 2008 and 2016
GROUP BY [Year]
)
,KnifeOutcome as (
SELECT
	[Year], SUM(Caution) as Caution, SUM(Discharged) as Discharged,
	SUM(Fine) as Fine, SUM([Community sentence]) as [Community sentence],
	SUM([Suspended sentence]) as [Suspended sentence],
	SUM([Immediate custody]) as [Immediate custody], SUM(Other) as Other
FROM Weapons.BladedOffenceByOutcome
WHERE [Year] between 2008 and 2016
GROUP BY [Year]
)
-- Actual dim table builder
SELECT 
	 dim.*
	,fo.[Homicide] as [Firearm (homicide)]
	,fo.[Attempted murder] as [Firearm (attempted murder)]
	,fo.[Other violence] as [Firearm (violence)]
	,fo.[Robbery] as [Firearm (robbery)]
	,fo.[Burglary] as [Firearm (burglary)]
	,fo.[Criminal damage] as [Firearm (criminal damage)]
	,fo.[Public fear] as [Firearm (public fear)]
	,fo.[Possession] as [Firearm (possession)]
	,fo.[Other] as [Firearm (other)]
	,fi.[Fatal] as [Firearm injuries (fatal)]
	,fi.[Serious] as [Firearm injuries (serious)]
	,fi.[Lesser] as [Firearm injuries (lesser)]
	,fi.[No Injury] as [Firearm injuries (none)]
	,fl.[Shop] as [Firearm location (shop)]
	,fl.[Garage] as [Firearm location (garage)]
	,fl.[Post office] as [Firearm location (post office)]
	,fl.[Bank] as [Firearm location (bank)]
	,fl.[Residential] as [Firearm location (residential)]
	,fl.[Road] as [Firearm location (road)]
	,fl.[Other] as [Firearm location (other)]
	,ka.Adult [Adult knife offences]
	,ka.Minor [Juvenile knife offences]
	,bo.[Homicide] as [Knife (homicide)]
	,bo.[Attempted murder] as [Knife (attempted murder)]
	,bo.[Threats to kill] as [Knife (threats to kill)]
	,bo.[Assault] as [Knife (assault)]
	,bo.[Rape] as [Knife (rape)]
	,bo.[Sexual assault] as [Knife (sexual assault)]
	,bo.[Robbery] as [Knife (robbery)]
	,ko.[Immediate custody] as [Knife outcomes (immediate custody)]
	,ko.[Fine] as [Knife outcomes (fined)]
	,ko.[Community sentence] as [Knife outcomes (community sentence)]
	,ko.[Suspended sentence] as [Knife outcomes (suspended sentence)]
	,ko.[Caution] as [Knife outcomes (caution)]
	,ko.[Discharged] as [Knife outcomes (discharged)]
	,ko.[Other] as [Knife outcomes (other)]
INTO dim.YearlyNationwide
FROM Years dim
LEFT JOIN KnifeAge ka
	ON dim.[Year] = ka.[Year]
LEFT JOIN KnifeOutcome ko
	ON dim.[Year] = ko.[Year]
LEFT JOIN Weapons.BladedOffenceByOffence bo
	ON dim.[Year] = bo.[Year]
LEFT JOIN Weapons.FirearmOffenceByInjury fi
	ON dim.[Year] = fi.[Date (March)]
LEFT JOIN Weapons.FirearmOffenceByLocationType fl
	ON dim.[Year] = fl.[Date (March)]
LEFT JOIN Weapons.FirearmOffenceByOffence fo
	ON dim.[Year] = fo.[Date (March)]
ORDER BY [Year]
-- Adding primary id key
ALTER TABLE Dim.YearlyNationwide
	Add id int identity primary key


/*-----------------------------------
    Creating Dim.StopSearchExtras
------------------------------------*/
-- Holding extra data from the StopSearch table that isn't included within street crime data
SELECT DISTINCT
	[Search type]
	,Gender
	,[Age range]
	,legislation
INTO dim.StopSearchExtras
FROM police.CrimeDataStopSearch
-- adding row of NULLs for Street data that doesn't have this granularity
INSERT INTO dim.StopSearchExtras
VALUES (NULL,NULL,NULL,NULL)
-- Adding primary id key
ALTER TABLE Dim.StopSearchExtras
	Add id int identity primary key


/*-------------------------------------
    Creating Dim.CrimeTypesOutcomes
--------------------------------------*/
-- Holding merged extra data (Crime and Outcome) from the crime data tables
CREATE TABLE Temp.CrimeTypesOutcomes1 (
	[Outcome flag] bit not null default(0)
	)
CREATE TABLE Temp.CrimeTypesOutcomes2 (
	[Crime type] varchar(30) default(NULL)
	)
INSERT INTO Temp.CrimeTypesOutcomes1
VALUES (0),(1)
INSERT INTO Temp.CrimeTypesOutcomes2
VALUES (NULL),('Drugs'),('Weapons'),('Violence & sexual crime'),('Theft & robbery'),('Criminal damage or disorder')
-- Cross join to get all combinations
SELECT
	*
INTO Dim.CrimeTypesOutcomes
FROM Temp.CrimeTypesOutcomes2
CROSS JOIN Temp.CrimeTypesOutcomes1
-- Adding primary id key
ALTER TABLE Dim.CrimeTypesOutcomes
	Add id int identity primary key

/*-----------------------------
    Creating Dim.
------------------------------*/

