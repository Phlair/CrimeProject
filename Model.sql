

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
FROM Geo.AreaCompare a
JOIN Geo.LSOA l
	on a.[LSOA code]=l.[lsoa code]
JOIN Geo.ForceArea f
	on a.[Force area code] = f.[Area code]
JOIN Geo.DeprivationRanksLSOA d
	on d.[LSOA code] = a.[LSOA code]