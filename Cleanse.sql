USE CrimeProject
GO

/* Cleansing to-dos

	Spatial Data Tables
		LSOAs and Police Force Areas
		QGIS to convert .shp files on British system to .csv in World co-ordinates
			Import to SQL
		SQL Cleansing
			Convert Well-Known-Text into SQL geog polygons
			Remove unwanted columns (e.g. Welsh variants of area names)
				Also rename columns to fit conventions applied in other tables
		We can then use these to insert a correct Force Area and LSOA column into police. tables

	AreaCompare table
		Just keep LSOA and Region columns as this is what it's needed for
	
	PoliceCrimeData Tables
		StopSearch
			Unnecessary columns:	Policing operation, 
									Ethnicities (purposely avoiding this for my project),
									Outcome linked to object of search,
									Removal of more than just outer clothing
			Cleansing:	Create Geom points from Long/Lat
						Make [Date] into proper datetime
						Alter [Age Range] values to mimic style from elsewhere
						Group up some of the [Object of search] for easier comparison
		Street
			Unnecessary columns:	[Reported by] and [Falls within] are always equal so just use either AS 'Area'
									Location (just describes which road, we already have precise co-ords)
									Context
			Cleansing:	Fix shifted columns (thanks to erroneous commas in [Location])
							In a CTE, shift these columns back in the right cases (WHERE [LSOA code] like '%"')
							And then build the clean table from that fixed CTE
						Remove unwanted [Crime Type] that don't relate to weapons/drugs/serious gangs:
							Anti-social behaviour, Bicycle theft, Burglary, Criminal damage and arson,
							Other crime, Other theft, Public order, Shoplifting, Vehicle crime
							(THIS MAKES THE TABLE SMALL ENOUGH TO MANAGE)
						Create Geom points from Long/Lat

	Spatialisation of PoliceCrimeData Tables
		Using the GeoPoints created for every instance of crime
			intersect on LSOA and Force polys to create new columns within the Police. tables
				Street already has Area but with different strings (e.g. 'Cumbria Constabulary' rather than 'Cumbria')
					Going to recreate this by intersecting on the GeoPoint
				Street also already has LSOA with correct data values
					Could run some small intersect queries (TOP) to check that my polys line up to this data
				StopSearch only has long/lat and thus GeoPoints
					Need to run intersects to create two new columns
						One for LSOA and one for ForceArea
		(((Might need to batch these as STIntersects is rather CPU intensive)))
			(((Once this is done, however, there is no more need for Geog operations and we will have lovely data to analyse)))
		TURNS OUT... spatial index was the answer, uses B-Trees to index Geog points and Intersect more efficiently


	Firearm/Shotgun Tables [!= FIREARM OFFENCE TABLES]
		These all have summed rows for areas (e.g. England/England and Wales)
			These should be removed
		Firearm/Shotgun Certificates and FirearmDealers has 2 or 3 Granted/Refused rows. 
			In firearm, these correlate to New Applications/Renewal Applications/Variation of Certificate 
			In shotgun, these correlate to New Applications/Renewal Applications
			In Dealers, these correlate to Previously unregistered/Previously registered
			Columns should be renamed to reflect this
		FirearmsGenderForceArea has 2 sets of triple duplicated rows
			Total/Females/Males/Gender not known = Firearm Certs/Shotgun Certs/Firearm and-or shotgun certs
			Total/[Age Brackets] = Firearm Certs/Shotgun Certs/Firearm and-or shotgun certs
			Columns should be renamed to reflect this

	Firearm Offence Tables
		These tables are absolutely cancerous, deep chemo required!!!
			Should be relatively obvious by looking at table / Excel docs

	Bladed Offence Tables
		Not quite as bad as Firearm but still need some cleaning, should be obvious by looking at tables
		Years on force area table:
			08/09, 09/10, 10/11, 11/12, 12/13, 13/14, 14/15, 15/16, 16/17

	Taser Tables
		Imported as 09-13, then individual table for each year, need to collate into one big table with date column
			In 14 only final 3 columns are necessary (others are breaking down by how taser was used, unneccesary)
			In 15 and 16, data is broken up by discharge and non-discharge, use both TOTAL columns
			Also, as with most force area groupings there are "total rows" for wider areas so watch out!
		NOTE: these numbers are incidents involving a taser (not necessarily discharge)
		NOTE: the year in the table name is ending year of data (may be more than 1 years worth)

	DrugDeathByArea Table
		Alteryx, not much to do here

	DrugSeizures Tables
		Snapshot table is based on just year 2016/17
			includes a total column for each drug class
			also includes final unnamed column which is 'Unknown' (i.e. unknown drug)

	DrugAdmissionsNHS Tables
		In column groups of 6 for each year
			Order: 16/17, 15/16, 14/15, 13/14
			Repeated 3 columns, first is the actual admissions for All persons/Male/Female
				Then the same per 100,000 population

	DrugSurveyData Table
		Values are "Proportion of 16 to 59 year olds reporting use of drugs in the specified year"
			These are therefore percentages of total participants surveyed
		Broken down by different drugs
			These are currently listed as their own row above the area data so need to fix this

	DeprivationIndices Table
		Ignore 'Score' columns unless there is a specific index we really want to explore
			then look up the meaning of the score online/in spreadsheet
		Ranking goes in order of 1 = Most deprived/Worst, i.e. higher is 'better'

	PopulationByLSOA Tables
		Imported by seperate years (data is from mid-specified year)
			 Need to insert column for date and collate into single table
		In the earliest data (11), actual population numbers need to be derived
			Data given is 'Area(sq km)' and 'pop per sq km' so this is very easy

	CHECK EVERY ORIGINAL DOCUMENT IN CASE VALUES ARE NOT EXACT
	e.g. Column title = 'Deaths', but it's actually deaths per 100,000 or something

	Check everything for (unwanted) duplicates
	ALSO check everything for area total rows, such as the different Yorkshires grouped as Yorkshire and the Humber
		These totals should be removed

	Sort into Schemas

	THERE ARE 43 FORCE AREAS SO ANYTHING WITH THESE SHOULD HAVE THIS MANY ROWS (at least by year or whatever)

	INSERT primary key column in all tables (unless already present)

	Add functionality to repeatedly run this sql file by using if statements to drop tables before re-making them

*/

/* Creating some extra schema to store uncleansed tables, temp tables and also any trash */
Create schema [Dirty]
GO
Create schema [Temp]
GO
Create schema [Trash]
GO

/*---------------------------
   Spatial tables cleanse
----------------------------*/
CREATE schema [Geo]
GO
-- Force Area polys (43 Force Areas)
;with makevalids -- cte to build the polys from text and MakeValid()
as (
	SELECT
		CASE
			WHEN WKT like '"MULTI%' THEN
					(geography::STMPolyFromText(REPLACE(WKT,'"',''), 4326).MakeValid())
			ELSE	(geography::STPolyFromText(REPLACE(WKT,'"',''), 4326).MakeValid())
		END as poly,
		*
	FROM ForceAreaFinal
	)
select
	-- Selecting only desired columns and renaming to be consistent with other tables
	pfa16cd AS [Area code]
	,pfa16nm AS [Area name]
	,CASE -- This is checking to see if we need to ReorientObject(), for some reason some of the polys are broken and some aren't
		WHEN poly.EnvelopeAngle() < 180 THEN poly
		ELSE poly.ReorientObject()
	 END AS [Geo poly]
INTO Geo.ForceArea -- Put into a table for comparison down the line
FROM makevalids
-- LSOA polys (34,753 LSOAs)
;with makevalids2 -- cte to build the polys from text and MakeValid()
as (
	SELECT
		(geography::STMPolyFromText(REPLACE(WKT,'"',''), 4326).MakeValid()) as poly,
		*
	FROM LSOAFinal
	)
,deletedupes -- have to run a cte with ROW_NUMBER since DISTINCT isn't allowed on Geog
as (
	select
		-- Selecting only desired columns and renaming to be consistent with other tables
		 lsoa11cd AS [LSOA code]
		,lsoa11nm AS [LSOA name]
		,CASE -- This is checking to see if we need to ReorientObject()
			-- for some reason some of the polys are broken and some aren't
			WHEN poly.EnvelopeAngle() < 180 THEN poly
			ELSE poly.ReorientObject()
		 END AS [Geo poly]
		,ROW_NUMBER() over (partition by lsoa11cd order by (SELECT 1)) As rowN
	FROM makevalids2
)
SELECT
	[LSOA code]
	,[LSOA name]
	,[Geo poly]
INTO Geo.LSOA -- Putting into table for comparisons down the line
FROM deletedupes
WHERE rown=1
ALTER SCHEMA Dirty TRANSFER dbo.ForceAreaFinal
ALTER SCHEMA Dirty TRANSFER dbo.LSOAFinal


/*----------------------------------
    PoliceCrimeData tables cleanse
-----------------------------------*/
CREATE SCHEMA [Police]
GO
-- Stop and Search
SELECT
	 CAST([Longitude] as float) AS [Longitude]
	,CAST([Latitude] as float) AS [Latitude]
	,geography::STPointFromText('POINT(' + cast([Longitude] as varchar)
		+ ' ' + cast([Latitude] as varchar) + ')', 4326) AS [Geo point] -- Creating Geo-points from Long/Lat
	,[Type] as [Search type]
	,Cast(Cast([Date]as datetime2) as smalldatetime) AS [DateTimestamp]
	,CAST([Part of a policing operation] as bit) AS [Police operation]
	,Gender
	,CASE
		WHEN [Age range] = 'under 10' THEN '0-10'
		WHEN [Age range] = 'over 34' THEN '34+'
		ELSE [Age range]
	END AS [Age range]
	,legislation
	,CASE
        WHEN [Object of search] IN ('Article for use in theft','Stolen goods')
            THEN 'Theft'
        WHEN [Object of search] IN ('Controlled drugs','Psychoactive substances')
            THEN 'Drugs'
        WHEN [Object of search] IN ('Crossbows','Offensive weapons','Anything to threaten or harm anyone','Firearms')
            THEN 'Weapons'
        WHEN [Object of search] IN ('Articles for use in criminal damage')
            THEN 'Criminal damage'
        ELSE [Object of search]
     END AS [Object of search]
	,Outcome
INTO Police.CrimeDataStopSearch
FROM dbo.PoliceCrimeDataStopSearch

-- Street
;with FixShift AS ( -- creating a cte to fix shifted columns and only return desired columns
SELECT
	[Crime ID] 
	,CAST(left([Month],4) as int) as [Year]
	,CAST(right([Month],2) as int) as [Month]
	,[Falls within] as [Area]
	,CAST([Longitude] as float) AS [Longitude]
	,CAST([Latitude] as float) AS [Latitude]
	,CASE
		WHEN [LSOA code] like '%"'
			THEN [LSOA name]
		ELSE [LSOA code]
	 END as [LSOA code]
	,CASE
		WHEN [LSOA code] like '%"'
			THEN [Crime type]
		ELSE [LSOA name]
	 END as [LSOA name]
	,CASE
		WHEN [LSOA code] like '%"'
			THEN [Last outcome category]
		ELSE [Crime type]
	 END as [Crime type]
	,CASE
		WHEN [LSOA code] like '%"'
			THEN [Context]
		ELSE [Last outcome category]
	 END as [Last outcome category]
FROM PoliceCrimeDataStreet
)
SELECT -- Selecting from our fixed cte only rows with desired [Crime type]
	*
-- Inserting this into a holding table so I don't have to keep running this 4 minute query
INTO temp.PoliceCrimeStreet
FROM FixShift
WHERE 1=1
AND [Crime type] != 'Anti-social behaviour' AND [Crime type] != 'Bicycle theft'
AND [Crime type] != 'Burglary' AND [Crime type] != 'Criminal damage and arson'
AND [Crime type] != 'Other crime' AND [Crime type] != 'Other theft'
AND [Crime type] != 'Public order' AND [Crime type] != 'Shoplifting'
AND [Crime type] != 'Vehicle crime' AND [Crime type] IS NOT NULL
-- Final cleansing of Street data (creating geom points and removing crimes with NULL locations)
SELECT 
	*
	,geography::STPointFromText('POINT(' + cast([Longitude] as varchar)
		+ ' ' + cast([Latitude] as varchar) + ')', 4326) AS [Geo point]
INTO Police.CrimeDataStreet
FROM temp.PoliceCrimeDataStreet
WHERE Longitude IS NOT NULL

/* THIS IS ALMOST 100% ALREADY CONTAINED WITHIN 'Street' TABLE SO UNNECESSARY
-- Outcomes
;with FixShift2 AS ( -- creating a cte to fix shifted columns and only return desired columns
SELECT
	[Crime ID] 
	,CAST(left([Month],4) as int) as [Year]
	,CAST(right([Month],2) as int) as [Month]
	,[Falls within] as [Area]
	,CAST([Longitude] as float) AS [Longitude]
	,CAST([Latitude] as float) AS [Latitude]
	,CASE
		WHEN [LSOA code] like '%"'
			THEN [LSOA name]
		ELSE [LSOA code]
	 END as [LSOA code]
	,CASE
		WHEN [LSOA code] like '%"'
			THEN SUBSTRING([Outcome type],1,charindex(',',[Outcome type])-1)
		ELSE [LSOA name]
	 END as [LSOA name]
	,CASE
		WHEN [LSOA code] like '%"'
			THEN SUBSTRING([Outcome type],charindex(',',[Outcome type])+1,LEN([Outcome type]))
		ELSE [Outcome type]
	 END as [Outcome type]
FROM PoliceCrimeDataOutcomes
)
SELECT -- Selecting from our fixed cte only rows that line up to our Street crime table on ID
	f.*
-- Inserting this into a holding table so I don't have to keep running this query
INTO temp.PoliceCrimeOutcomes
FROM FixShift2 f
JOIN Police.CrimeDataStreet pc
	on f.[Crime ID] = pc.[Crime ID]
*/
-- Tidying up tables appropriately
ALTER SCHEMA Dirty TRANSFER dbo.PoliceCrimeDataOutcomes
ALTER SCHEMA Dirty TRANSFER dbo.PoliceCrimeDataStopSearch
ALTER SCHEMA Dirty TRANSFER dbo.PoliceCrimeDataStreet
ALTER SCHEMA Trash TRANSFER temp.PoliceCrimeOutcomes
ALTER SCHEMA Trash TRANSFER temp.PoliceCrimeStreet


/*--------------------------------------------
   Spatialisation of PoliceCrimeData Tables
---------------------------------------------*/
ALTER SCHEMA Temp TRANSFER police.CrimeDataStopSearch
ALTER SCHEMA Temp TRANSFER police.CrimeDataStreet
-- Needs Primary Key in order to create spatial index
ALTER TABLE geo.ForceArea
	Add id int identity primary key
ALTER TABLE geo.LSOA
	Add id int identity primary key
ALTER TABLE Temp.CrimeDataStopSearch
	Add id int identity primary key
ALTER TABLE Temp.CrimeDataStreet
	Add id int identity primary key
-- Creating spatial index(s) to speed up STIntersects (B-Trees baby!)
CREATE SPATIAL INDEX SIndx_CrimeDataStopSearch_GeoPoint
   ON Temp.CrimeDataStopSearch([Geo point])
CREATE SPATIAL INDEX SIndx_CrimeDataStreet_GeoPoint
   ON Temp.CrimeDataStreet([Geo point])
--CREATE SPATIAL INDEX SIndx_GeoForceArea_GeoPoly
--   ON Geo.ForceArea([Geo poly])			-- SMALL NUMBER OF ROWS: unnecessary to have spatial index
CREATE SPATIAL INDEX SIndx_GeoLSOA_GeoPoly
   ON Geo.LSOA([Geo poly])
-- STOP and SEARCH
	-- Intersecting with Force Areas
	SELECT
		 f.[Area name]
		,f.[Area code]
		,c.[Search type]
		,c.DateTimestamp 
		,c.[Police operation]
		,c.Gender
		,c.[Age range]
		,c.legislation
		,c.[Object of search]
		,c.Outcome
		,c.[Geo point] -- Need this for the next select where we intersect with LSOA
	INTO Temp.MatchedStopSearch -- Putting into temp so we can add in LSOA value as well
	FROM Temp.CrimeDataStopSearch c
	WITH (INDEX(SIndx_CrimeDataStopSearch_GeoPoint))
	join geo.ForceArea f
		--WITH (INDEX(SIndx_GeoForceArea_GeoPoly))
		on c.[Geo point].STIntersects(f.[Geo poly]) = 1
	-- Intersecting with LSOA
		-- Creating new spatial index on our StopSearch table with matched force areas
	ALTER TABLE temp.matchedstopsearch	-- Needs new primary key to create spatial index
		Add id int identity primary key
	CREATE SPATIAL INDEX SIndx_MatchedStopSearch_GeoPoint
		ON Temp.MatchedStopSearch([Geo point])
	SELECT
		 c.[Area name]
		,c.[Area code]
		,l.[LSOA name]
		,l.[LSOA code]
		,c.DateTimestamp 
		,c.[Search type]
		,c.[Object of search]
		,c.[Police operation]
		,c.Gender
		,c.[Age range]
		,c.legislation
		,c.Outcome
	INTO Police.CrimeDataStopSearch
	FROM Temp.MatchedStopSearch c
	WITH (INDEX(SIndx_MatchedStopSearch_GeoPoint))
	join geo.LSOA l
		--WITH (INDEX(SIndx_GeoLSOA_GeoPoly))
		on c.[Geo point].STIntersects(l.[Geo poly]) = 1
-- STREET data
	-- Intersecting with Force Areas
	SELECT
		f.[Area name]
		,f.[Area code]
		,c.[LSOA name]
		,c.[LSOA code]
		,c.[Year]
		,c.[Month]
		,c.[Crime type]
		,c.[Last outcome category]
		,c.[Geo point] -- Need this for the next select where we intersect with LSOA
	INTO Temp.MatchedStreet -- Putting into temp so we can add in LSOA value as well
	FROM Temp.CrimeDataStreet c
	WITH (INDEX(SIndx_CrimeDataStreet_GeoPoint))
	join geo.ForceArea f
		--WITH (INDEX(SIndx_GeoForceArea_GeoPoly))
		on c.[Geo point].STIntersects(f.[Geo poly]) = 1
	-- Intersecting with LSOA
		-- Creating new spatial index on our StopSearch table with matched force areas
	/*
	ALTER TABLE temp.matchedstreet	-- Needs new primary key to create spatial index
		Add id int identity primary key
	CREATE SPATIAL INDEX SIndx_MatchedStreet_GeoPoint
		ON Temp.MatchedStreet([Geo point])
	SELECT
		 c.[Area name]
		,c.[Area code]
		,l.[LSOA name]
		,l.[LSOA code]
		,c.DateTimestamp 
		,c.[Search type]
		,c.[Object of search]
		,c.[Police operation]
		,c.Gender
		,c.[Age range]
		,c.legislation
		,c.Outcome
	INTO Police.CrimeDataStopSearch
	FROM Temp.MatchedStopSearch c
	WITH (INDEX(SIndx_MatchedStopSearch_GeoPoint))
	join geo.LSOA l
		--WITH (INDEX(SIndx_GeoLSOA_GeoPoly))
		on c.[Geo point].STIntersects(l.[Geo poly]) = 1
	*/
	-- Putting into correct schema
	ALTER SCHEMA Police TRANSFER temp.matchedstreet


/*-----------------------------
   AreaCompare table cleanse
------------------------------*/
-- just quick cleanse to convert this into a comparison for LSOA to Region
SELECT DISTINCT
	 LSOA11CD as [LSOA code]
	,LSOA11NM as [LSOA name]
	,RGN11CD as [Region code]
	,RGN11NM as [Region name]
INTO geo.RegionToLSOA
FROM AreaCompare
WHERE RGN11NM != 'Scotland'

ALTER SCHEMA dirty TRANSFER dbo.AreaCompare


/*----------------------------------------------------------------
   Firearm/Shotgun tables cleanse [NOT 'FirearmOffence' tables]
-----------------------------------------------------------------*/
Create schema [Weapons]
Go
Select
	-- Selecting only desired columns
	 year('20' + right([Year],2)) AS [Year] -- Fixing '08/09' format to singular year
	,[Region]
	,[Police force area]
	-- Renaming these columns to correctly differentiate
	,Cast([Granted] as int) AS [New applications granted]
	,Cast([Refused] as int) AS [New applications refused]
	,Cast([Granted1] as int) AS [Renewal applications granted]
	,Cast([Refused1] as int) AS [Renewal applications refused]
	,Cast([Granted2] as int) AS [Variation certificate granted]
	,Cast([Refused2] as int) AS [Variation certificate refused]
	,Cast([Revocations] as int) AS [Revocations]
	,Cast([Firearm certificates on issue as at 31 March] as int) AS [Total on issue (31/03)]
	,Cast([Firearms covered by certificates on issue as at 31 March] as int) AS [Total firearms (31/03)]
	,Cast([Firearms per 100,000 people as at 31 March] as float) AS [Firearms per 100K pop (31/03)]
INTO [Guns].FirearmCertificatesForceArea
FROM dbo.FirearmCertificatesForceArea
WHERE [Police force area] not like '*%' -- Removing rows that are area totals, fortunately prefaced with an asterisk '*'
Select
	-- Selecting only desired columns
	 year('20' + right([Year],2)) AS [Year] -- Fixing '08/09' format to singular year
	,[Region]
	,[Police force area]
	-- Renaming these columns to correctly differentiate
	,Cast([Granted] as int) AS [New applications granted]
	,Cast([Refused] as int) AS [New applications refused]
	,Cast([Granted1] as int) AS [Renewal applications granted]
	,Cast([Refused1] as int) AS [Renewal applications refused]
	,Cast([Revocations] as int) AS [Revocations]
	,Cast([Shotgun certificates on issue as at 31 March] as int) AS [Total on issue (31/03)]
	,Cast([Shotguns covered by certificates in force as at 31 March] as int) AS [Total shotguns (31/03)]
	,Cast([Shotguns per 100,000 people as at 31 March] as float) AS [Shotguns per 100K pop (31/03)]
INTO [Guns].ShotgunCertificatesForceArea
FROM dbo.ShotgunCertificatesForceArea
WHERE [Police force area] not like '*%' -- Removing rows that are area totals, fortunately prefaced with an '*' asterisk
Select
	-- Selecting only desired columns
	 year('20' + right([Year],2)) AS [Year] -- Fixing '08/09' format to singular year
	,[Region]
	,[Police force area]
	-- Renaming these columns to correctly differentiate
	,Cast([Granted] as int) AS [New license granted]
	,Cast([Refused] as int) AS [New license refused]
	,Cast([Granted1] as int) AS [Renewal license granted]
	,Cast([Refused1] as int) AS [Renewal license refused]
	,Cast([Dealers removed from register] as int) AS [Dealers removed]
	,Cast([Dealers registered as at 31 March] as int) AS [Total dealers (31/03)]
INTO [Guns].FirearmDealersForceArea
FROM dbo.FirearmDealersForceArea
WHERE [Police force area] not like '*%' -- Removing rows that are area totals, fortunately prefaced with an asterisk '*'
Select
	-- Selecting only desired columns (splitting table into 2, this one for gender)
	 year('20' + right([Year],2)) AS [Year] -- Fixing '08/09' format to singular year
	,[Region]
	,[Police force area]
	-- Renaming these columns to correctly differentiate
	,Cast([Females] as int) AS [Female firearm certs]
	,Cast([Males] as int) AS [Male firearm certs]
	,Cast([Gender not _known] as int) AS [GenderNA firearm certs]
	,Cast([Females1] as int) AS [Female shotgun certs]
	,Cast([Males1] as int) AS [Male shotgun certs]
	,Cast([Gender not known] as int) AS [GenderNA shotgun certs]
INTO [Guns].GunsGenderForceArea
FROM dbo.FirearmsGenderForceArea
WHERE [Police force area] not like '*%' -- Removing rows that are area totals, fortunately prefaced with an asterisk '*'
Select
	-- Selecting only desired columns (splitting table into 2, this one for age brackets)
	 year('20' + right([Year],2)) AS [Year] -- Fixing '08/09' format to singular year
	,[Region]
	,[Police force area]
	-- Renaming these columns to correctly differentiate
	,Cast([14 to 17] as int) AS [Firearm certs 14-17]
	,Cast([18 to 34] as int) AS [Firearm certs 18-34]
	,Cast([35 to 49] as int) AS [Firearm certs 35-49]
	,Cast([50 to 64] as int) AS [Firearm certs 50-64]
	,Cast([65 and _over] as int) AS [Firearm certs 65+]
	,Cast([13 and _under1] as int) AS [Shotgun certs 0-13]
	,Cast([14 to 171] as int) AS [Shotgun certs 14-17]
	,Cast([18 to 341] as int) AS [Shotgun certs 18-34]
	,Cast([35 to 491] as int) AS [Shotgun certs 35-49]
	,Cast([50 to 641] as int) AS [Shotgun certs 50-64]
	,Cast([65 and _over1] as int) AS [Shotgun certs 65+]
INTO [Guns].GunsAgeForceArea
FROM dbo.FirearmsGenderForceArea
WHERE [Police force area] not like '*%' -- Removing rows that are area totals, fortunately prefaced with an asterisk '*'
-- Moving original tables into dirty schema
ALTER SCHEMA dirty TRANSFER dbo.FirearmCertificatesForceArea
ALTER SCHEMA dirty TRANSFER dbo.ShotgunCertificatesForceArea
ALTER SCHEMA dirty TRANSFER dbo.FirearmDealersForceArea
ALTER SCHEMA dirty TRANSFER dbo.FirearmsGenderForceArea


/*--------------------------------
   FirearmOffence tables cleanse 
---------------------------------*/
-- OFFENCE BY SEVERITY OF INJURY
	-- Need to clean lots of unwanted data and also transpose table, so going to pivot/unpivot
;with GunOffenceByInjury
AS (
SELECT TOP 10 -- TOP 10 so that we only look at firearm offences, not airgun
	-- Renaming date columns to something more sensible
	Injuries, [Apr '02 to Mar '03] AS '2003', [Apr '03 to Mar '04] AS '2004', [Apr '04 to Mar '05] AS '2005',
	[Apr '05 to Mar '06] AS '2006', [Apr '06 to Mar '07] AS '2007', [Apr '07 to Mar '08] AS '2008',
	[Apr '08 to Mar '09] AS '2009', [Apr '09 to Mar '10] AS '2010', [Apr '10 to Mar '113] AS '2011',
	[Apr '11 to Mar '12] AS '2012', [Apr '12 to Mar '13] AS '2013', [Apr '13 to Mar '14] AS '2014',
	[Apr '14 to Mar '15] AS '2015', [Apr '15 to Mar '16] AS '2016', [Apr '16 to Mar '17] AS '2017'
FROM dbo.FirearmOffenceByInjury
)
SELECT
	-- Better names and casting to suitable types
	 year(Cast([Date (March)] AS date)) AS [Date (March)]
	,Cast([Fatal injury4] as int) AS [Fatal]
	,Cast([Serious injury5] as int) AS [Serious]
	,Cast([Slight injury] as int) AS [Lesser]
	,Cast([No injury] as int) AS [No Injury]
INTO Weapons.FirearmOffenceByInjury
FROM
(SELECT
	[Injuries],value,[Date (March)]
	FROM GunOffenceByInjury
	unpivot (
		value for [Date (March)] in 
		([2003],[2004],[2005],[2006],[2007],[2008],[2009],[2010],[2011],[2012],[2013],
		[2014],[2015],[2016],[2017])
	) unpiv 
	) AS src
PIVOT (
	sum(value)
	FOR Injuries IN ([Fatal injury4], [Serious injury5], [Slight injury], [No injury])
	) AS PivotTable;
GO
-- OFFENCE BY LOCATION TYPE (ROBBERIES)
	-- e.g. Post Office/Public highway
	-- Need to clean some unwanted data and also transpose table, so going to pivot/unpivot
;with GunOffenceByLoc
AS (
SELECT
	-- Renaming date columns to something more sensible
	[Location of offence]
	,[Apr '02 to Mar '03] AS '2003', [Apr '03 to Mar '04] AS '2004', [Apr '04 to Mar '05] AS '2005',
	[Apr '05 to Mar '06] AS '2006', [Apr '06 to Mar '07] AS '2007', [Apr '07 to Mar '08] AS '2008',
	[Apr '08 to Mar '09] AS '2009', [Apr '09 to Mar '10] AS '2010', [Apr '10 to Mar '11] AS '2011',
	[Apr '11 to Mar '12] AS '2012', [Apr '12 to Mar '13] AS '2013', [Apr '13 to Mar '14] AS '2014',
	[Apr '14 to Mar '15] AS '2015', [Apr '15 to Mar '16] AS '2016', [Apr '16 to Mar '17] AS '2017'
FROM dbo.FirearmOffenceByLocationType
)
SELECT
	-- Better names and casting to suitable types
	 year(Cast([Date (March)] AS date)) AS [Date (March)]
	,Cast([Shop, stall etc.] as int) AS [Shop]
	,Cast([Garage, service station ] as int) AS [Garage]
	,Cast([Post Office] as int) AS [Post office]
	,Cast([Bank] as int) + Cast([Building society] as int) AS [Bank]
	,Cast([Residential2] as int) AS [Residential]
	,Cast([Public highway] as int) AS [Road]
	,Cast([Other premises or open space] as int) AS [Other]
INTO Weapons.FirearmOffenceByLocationType
FROM
(SELECT
	[Location of offence],value,[Date (March)]
	FROM GunOffenceByLoc
	unpivot (
		value for [Date (March)] in 
		([2003],[2004],[2005],[2006],[2007],[2008],[2009],[2010],[2011],[2012],[2013],
		[2014],[2015],[2016],[2017])
	) unpiv 
	) AS src
PIVOT (
	sum(value)
	FOR [Location of offence] IN ([Shop, stall etc.], [Garage, service station ], [Post Office], [Bank]
					,[Building society], [Residential2], [Public highway], [Other premises or open space])
	) AS PivotTable;
GO
-- OFFENCE BY OFFENCE
	-- e.g. Homicide/Robbery/Possession
	-- Need to clean some unwanted data and also transpose table, so going to pivot/unpivot
;with GunOffenceByOffence
AS (
SELECT TOP 17 -- So we only get firearm offences and not also air-weapons
	-- Renaming date columns to something more sensible
	[Offence type]
	,[Apr '03 to Mar '04] AS '2004', [Apr '04 to Mar '05] AS '2005',
	[Apr '05 to Mar '062] AS '2006', [Apr '06 to Mar '07] AS '2007', [Apr '07 to Mar '08] AS '2008',
	[Apr '08 to Mar '09] AS '2009', [Apr '09 to Mar '10] AS '2010', [Apr '10 to Mar '11] AS '2011',
	[Apr '11 to Mar '12] AS '2012', [Apr '12 to Mar '13] AS '2013', [Apr '13 to Mar '14] AS '2014',
	[Apr '14 to Mar '15] AS '2015', [Apr '15 to Mar '16] AS '2016', [Apr '16 to Mar '17] AS '2017'
FROM dbo.FirearmOffenceByOffence
)
SELECT
	-- Better names and casting to suitable types
	 year(Cast([Date (March)] AS date)) AS [Date (March)]
	,Cast([Homicide3] as int) AS [Homicide]
	,COALESCE(Cast([Attempted murder and other most serious violence] as int),
				Cast([Attempted murder and GBH with intent offences4] as int),
				Cast([Attempted murder, assault with intent to cause serious harm and endangering life4] as int)
	) AS [Attempted murder]
	,Cast([Other] as int) AS [Other violence]
	,Cast([Robbery] as int) AS [Robbery]
	,Cast([Burglary] as int) AS [Burglary]
	,Cast([Criminal damage] as int) AS [Criminal damage]
	,Cast([Public fear, alarm or distress] as int) AS [Public fear]
	,Cast([Possession of weapons] as int) AS [Possession]
	,Cast([Other firearm offences] as int) AS [Other]
INTO Weapons.FirearmOffenceByOffence
FROM
(SELECT
	[Offence type],value,[Date (March)]
	FROM GunOffenceByOffence
	unpivot (
		value for [Date (March)] in 
		([2004],[2005],[2006],[2007],[2008],[2009],[2010],[2011],[2012],[2013],
		[2014],[2015],[2016],[2017])
	) unpiv 
	) AS src
PIVOT (
	sum(value)
	FOR [Offence type] IN ([Homicide3], [Attempted murder and other most serious violence], [Attempted murder and GBH with intent offences4], 
	[Attempted murder, assault with intent to cause serious harm and endangering life4],[Other], [Robbery], 
	[Burglary], [Criminal damage],[Public fear, alarm or distress],[Possession of weapons],[Other firearm offences])
	) AS PivotTable;
GO
-- FirearmOffenceByWeapon will remain unused, moving to Trash schema
ALTER SCHEMA Trash TRANSFER FirearmOffenceByWeapon
-- OFFENCE BY FORCE AREA
	-- Removed final pivot in order to match area convention with other tables
	-- e.g. Cumbria/West Mercia/Dorset
	-- Need to clean some unwanted data, remove totals and also transpose table, so going to pivot/unpivot
;with GunOffenceByArea
AS (
SELECT
	[Police force area],
	-- Renaming date columns to something more sensible
	[Apr '07 to Mar '08] AS '2008',
	[Apr '08 to Mar '09] AS '2009', [Apr '09 to Mar '10] AS '2010', [Apr '10 to Mar '11] AS '2011',
	[Apr '11 to Mar '12] AS '2012', [Apr '12 to Mar '13] AS '2013', [Apr '13 to Mar '14] AS '2014',
	[Apr '14 to Mar '15] AS '2015', [Apr '15 to Mar '16] AS '2016', [Apr '16 to Mar '17] AS '2017'
FROM dirty.FirearmOffenceForceArea
WHERE 1=1
	AND [Police force area] not like 'East ' 
	AND [Police force area] not like 'South West ' 
	AND [Police force area] not like 'South East '
	AND [Police force area] not like 'North West ' 
	AND [Police force area] not like 'North East '
	AND [Police force area] not like 'Wales'
	AND [Police force area] not like 'Yorkshire and The Humber '
	AND [Police force area] not like 'London '
	AND [Police force area] not like 'East Midlands '
)
SELECT
	-- Better names and casting to suitable types
	year(Cast([Date (March)] AS date)) AS [Date (March)]
	,[Police force area] AS [Area]
	,MIN([value]) over (partition by [Date (March)], [Police force area]) AS [Offences]
INTO Weapons.FirearmOffenceByArea
FROM
(SELECT
	[Police force area],value,[Date (March)]
	FROM GunOffenceByArea
	unpivot (
		value for [Date (March)] in 
		([2008],[2009],[2010],[2011],[2012],[2013],
		[2014],[2015],[2016],[2017])
	) unpiv 
	) AS src
--PIVOT (
--	sum(value)
--	FOR [Police force area] IN ([Cleveland], [Durham], [Northumbria], [Cheshire],[Cumbria],[Greater Manchester]
--	,[Lancashire],[Merseyside], [Humberside],[North Yorkshire], [South Yorkshire],[West Yorkshire],[Derbyshire]
--	,[Leicestershire],[Lincolnshire],[Northamptonshire],[Nottinghamshire],[Staffordshire],[Warwickshire],[West Mercia]
--	,[West Midlands],[Bedfordshire],[Cambridgeshire],[Essex] ,[Hertfordshire], [Norfolk], [Suffolk], [City  of London]
--	,[Metropolitan Police] ,[Hampshire] ,[Kent],[Surrey],[Sussex],[Thames Valley],[Avon and Somerset],[Devon and Cornwall]
--	,[Dorset],[Gloucestershire],[Wiltshire],[Dyfed-Powys],[Gwent],[North Wales],[South Wales])
--	) AS PivotTable;
GO
-- Removing duplicate West Midland Rows
WITH Temp ([Date (March)],Area,Offences,duplicateRecCount)
AS
(
SELECT [Date (March)],Area,Offences,ROW_NUMBER() OVER(PARTITION by [Date (March)],Area,Offences ORDER BY Area) 
AS duplicateRecCount
FROM Weapons.FirearmOffenceByArea
)
DELETE FROM Temp --Now Delete Duplicate Records
WHERE duplicateRecCount > 1 
-- Moving original tables into dirty schema
ALTER SCHEMA dirty TRANSFER dbo.FirearmOffenceByInjury
ALTER SCHEMA dirty TRANSFER dbo.FirearmOffenceByLocationType
ALTER SCHEMA dirty TRANSFER dbo.FirearmOffenceByOffence
ALTER SCHEMA dirty TRANSFER dbo.FirearmOffenceForceArea


/*----------------------------------
    BladedOffence tables cleanse
-----------------------------------*/
-- Minor v.s. Adult
SELECT
	-- Case statement to transform quarterly date strings into two columns
		-- One for year and one for quarter
	CASE
		WHEN [F1] like 'Q1%' THEN DATEPART(YY,Convert(date,'15-02-'+RIGHT(F1,4),105)) -- Use Feb 15th for Q1
		WHEN [F1] like 'Q2%' THEN DATEPART(YY,Convert(date,'15-05-'+RIGHT(F1,4),105)) -- Use May 15th for Q2
		WHEN [F1] like 'Q3%' THEN DATEPART(YY,Convert(date,'15-08-'+RIGHT(F1,4),105)) -- Use Aug 15th for Q3
		ELSE DATEPART(YY,Convert(date,'15-11-'+RIGHT(F1,4),105)) -- Use Nov 15th for Q4
	END AS [Year]
	,CASE
		WHEN [F1] like 'Q1%' THEN DATEPART(QQ,Convert(date,'15-02-'+RIGHT(F1,4),105)) -- Use Feb 15th for Q1
		WHEN [F1] like 'Q2%' THEN DATEPART(QQ,Convert(date,'15-05-'+RIGHT(F1,4),105)) -- Use May 15th for Q2
		WHEN [F1] like 'Q3%' THEN DATEPART(QQ,Convert(date,'15-08-'+RIGHT(F1,4),105)) -- Use Aug 15th for Q3
		ELSE DATEPART(QQ,Convert(date,'15-11-'+RIGHT(F1,4),105)) -- Use Nov 15th for Q4
	END AS [Quarter]
	,CAST([Aged 10 to 17] as int) AS [Minor]
	,CAST([Aged 18 and over] as int) AS [Adult]
INTO Weapons.BladedOffenceByAge
FROM [dbo].[BladedOffenceByAgeOutcomeQuarter]
-- Outcomes
SELECT
	-- Case statement to transform quarterly date strings into two columns
		-- One for year and one for quarter
	CASE
		WHEN [F1] like 'Q1%' THEN DATEPART(YY,Convert(date,'15-02-'+RIGHT(F1,4),105)) -- Use Feb 15th for Q1
		WHEN [F1] like 'Q2%' THEN DATEPART(YY,Convert(date,'15-05-'+RIGHT(F1,4),105)) -- Use May 15th for Q2
		WHEN [F1] like 'Q3%' THEN DATEPART(YY,Convert(date,'15-08-'+RIGHT(F1,4),105)) -- Use Aug 15th for Q3
		ELSE DATEPART(YY,Convert(date,'15-11-'+RIGHT(F1,4),105)) -- Use Nov 15th for Q4
	END AS [Year]
	,CASE
		WHEN [F1] like 'Q1%' THEN DATEPART(QQ,Convert(date,'15-02-'+RIGHT(F1,4),105)) -- Use Feb 15th for Q1
		WHEN [F1] like 'Q2%' THEN DATEPART(QQ,Convert(date,'15-05-'+RIGHT(F1,4),105)) -- Use May 15th for Q2
		WHEN [F1] like 'Q3%' THEN DATEPART(QQ,Convert(date,'15-08-'+RIGHT(F1,4),105)) -- Use Aug 15th for Q3
		ELSE DATEPART(QQ,Convert(date,'15-11-'+RIGHT(F1,4),105)) -- Use Nov 15th for Q4
	END AS [Quarter]
	,CAST([Caution] as int) AS [Caution]
	,CAST([Absolute / Conditional discharge] as int) AS [Discharged]
	,CAST([Fine] as int) AS [Fine]
	,CAST([Community sentence] as int) AS [Community sentence]
	,CAST([Suspended sentence] as int) AS [Suspended sentence]
	,CAST([Immediate custody] as int) AS [Immediate custody]
	,CAST([Other disposal 4] as int) AS [Other]
INTO Weapons.BladedOffenceByOutcome
FROM [dbo].[BladedOffenceByAgeOutcomeQuarter]
-- Offence by Offence
BEGIN TRAN -- removing singular erroneous row
	DELETE FROM [BladedOffenceByOffence]
	WHERE [Time period  ] like '%Year ending%'
COMMIT TRAN
SELECT 
	 year('20' + right([Time period  ],2)) AS [Year] -- Fixing '2008/09' format to singular year
	,CAST([Attempted murder] as int) AS [Attempted murder]
	,CAST([Threats to kill] as int) AS [Threats to kill]
	,CAST([Assault with injury and intent to cause serious harm] as int) AS [Assault]
	,CAST([Robbery] as int) AS [Robbery]
	,CAST([Rape] as int) AS [Rape]
	,CAST([Sexual assault] as int) AS [Sexual assault]
	,CAST([Homicide] as int) AS [Homicide]
INTO Weapons.BladedOffenceByOffence
FROM [dbo].[BladedOffenceByOffence]
-- Offence by Force Area
	-- Need to unpivot this to match convention for Areas and Years so using cte
;with HalfCleanBladeArea
AS (
SELECT 
	 [F1] AS [Area]
	,CAST([Number] as int) AS [2009]
	,CAST([Number1] as int) AS [2010]
	,CAST([Number2] as int) AS [2011]
	,CAST([Number3] as int) AS [2012]
	,CAST([Number4] as int) AS [2013]
	,CAST([Number5] as int) AS [2014]
	,CAST([Number6] as int) AS [2015]
	,CAST([Number7] as int) AS [2016]
	,CAST([Number8] as int) AS [2017]
FROM [dbo].[BladedOffenceForceArea]
-- Only return relevant rows
WHERE [F1] IS NOT NULL 
	AND [F1] NOT LIKE '%Region%'
	AND [F1] NOT LIKE 'WALES'
	AND [F1] NOT LIKE '%England%'
)
SELECT
	-- Better names and casting to suitable types
	year([Date]) AS [Date]
	,[Area] AS [Area]
	,MIN([value]) over (partition by [Date], [Area]) AS [Offences]
INTO Weapons.BladedOffenceByArea
FROM
(SELECT
	[Date],[Area],value
	FROM HalfCleanBladeArea
	unpivot (
		value for [Date] in 
		([2009],[2010],[2011],[2012],[2013],
		[2014],[2015],[2016],[2017])
	) unpiv 
	) AS src
-- Moving original tables into dirty schema
ALTER SCHEMA dirty TRANSFER dbo.BladedOffenceByAgeOutcomeQuarter
ALTER SCHEMA dirty TRANSFER dbo.BladedOffenceByOffence
ALTER SCHEMA dirty TRANSFER dbo.BladedOffenceForceArea


/*----------------------------------
    PoliceTaserUse tables cleanse 
-----------------------------------*/
-- Completed in Alteryx, moving original data to dirty schema
ALTER SCHEMA Dirty TRANSFER dbo.PoliceTaserUse13
ALTER SCHEMA Dirty TRANSFER dbo.PoliceTaserUse14
ALTER SCHEMA Dirty TRANSFER dbo.PoliceTaserUse15
ALTER SCHEMA Dirty TRANSFER dbo.PoliceTaserUse16


/*------------------------------------
    DrugDeathByArea table cleanse
-------------------------------------*/
-- Creating new 'Drug' schema
CREATE SCHEMA [Drug]
GO
-- This tabled cleansed in Alteryx and exported here, moving OG data to dirty
ALTER SCHEMA Dirty TRANSFER dbo.drugdeathbyarea
-- Just remove some of the oldest rows
ALTER SCHEMA temp transfer drug.deathbyarea
SELECT
	*
into Drug.DeathByRegion
FROM temp.deathbyarea
WHERE [Year] > 1999