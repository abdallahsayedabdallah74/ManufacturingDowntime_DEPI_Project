CREATE DATABASE PROJECT_DEPI_2


CREATE TABLE Products (
    Product_id VARCHAR(50) PRIMARY KEY, 
    Flavor VARCHAR(50),
    Size VARCHAR(50),
    Min_batch_time INT
)
BULK INSERT Products
FROM 'D:\Data Analysis Track\Final Project\Product.csv'
WITH (
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    FIRSTROW = 2
)


CREATE TABLE Line_Productivity (
    Batch INT PRIMARY KEY,              
    Date DATETIME,
    Product_id VARCHAR(50),
	Operator_name VARCHAR(50),
    Start_time VARCHAR(50),  
    End_time VARCHAR(50),
    productin_Duration VARCHAR(50),
	Shift VARCHAR(50),
	Production_status VARCHAR(50),
    
    CONSTRAINT FK_ProductBatch FOREIGN KEY (Product_id) 
    REFERENCES Products(Product_id)
)

BULK INSERT Line_Productivity
FROM 'D:\Data Analysis Track\Final Project\L_P.csv'
WITH (
    FIELDTERMINATOR = ',', 
    ROWTERMINATOR = '\n',
    FIRSTROW = 2,
    CODEPAGE = '65001'
)



CREATE TABLE Downtime_Factors (
    Factor_ID INT PRIMARY KEY,
    Description VARCHAR(255),
    Operator_Error VARCHAR(10) -- "Yes" or "No"
)
BULK INSERT Downtime_Factors
FROM 'D:\Data Analysis Track\Final Project\D_F.csv'
WITH (
    FIELDTERMINATOR = ',', 
    ROWTERMINATOR = '\n',
    FIRSTROW = 2,
    CODEPAGE = '65001'
)



CREATE TABLE Line_Downtime (
    Downtime_id INT PRIMARY KEY,
    Batch INT,
    Factor_ID INT, 
    Downtime_Min INT 

    CONSTRAINT FK_Batch FOREIGN KEY (Batch) 
    REFERENCES Line_Productivity(Batch),

    CONSTRAINT FK_Factor FOREIGN KEY (Factor_ID) 
    REFERENCES Downtime_Factors(Factor_ID)
)
BULK INSERT Line_Downtime
FROM 'D:\Data Analysis Track\Final Project\L_D.csv'
WITH (
    FIELDTERMINATOR = ',', 
    ROWTERMINATOR = '\n',
    FIRSTROW = 2,
    CODEPAGE = '65001'
)

SELECT * FROM Line_Productivity
SELECT * FROM Products
SELECT * FROM Line_Downtime
SELECT * FROM Downtime_Factors


--======================
--  Incpect the Data
--======================

--(Top Rows)
SELECT TOP 5 * FROM Line_Productivity
SELECT TOP 5 * FROM Products
SELECT TOP 5 * FROM Line_Downtime
SELECT TOP 5 * FROM Downtime_Factors


--(Data Types)
EXEC sp_help 'Line_Productivity'
EXEC sp_help 'Products'
EXEC sp_help 'Line_Downtime'
EXEC sp_help 'Downtime_Factors'

SELECT * FROM Line_Productivity WHERE Batch IS NULL
--(Missing Value Information)
SELECT 
    'Line_Productivity' AS Table_Name,
    COUNT(*) AS Total_Rows,
    SUM(CASE WHEN Batch IS NULL THEN 1 ELSE 0 END) AS Missing_Batch,
    SUM(CASE WHEN Date IS NULL THEN 1 ELSE 0 END) AS Missing_Date,
    SUM(CASE WHEN Product_id IS NULL THEN 1 ELSE 0 END) AS Missing_Product,
    SUM(CASE WHEN Operator_Name IS NULL THEN 1 ELSE 0 END) AS Missing_Operator,
    SUM(CASE WHEN Start_Time IS NULL THEN 1 ELSE 0 END) AS Missing_Start,
    SUM(CASE WHEN End_Time IS NULL THEN 1 ELSE 0 END) AS Missing_End
FROM Line_Productivity

SELECT 
    'Line_DownTime' AS Table_Name,
    COUNT(*) AS Total_Rows,
    SUM(CASE WHEN Batch IS NULL THEN 1 ELSE 0 END) AS Null_Batch,
    SUM(CASE WHEN Downtime_id IS NULL THEN 1 ELSE 0 END) AS Null_ID,
    SUM(CASE WHEN Factor_ID IS NULL THEN 1 ELSE 0 END) AS Null_Factor,
    SUM(CASE WHEN DownTime_MIn IS NULL THEN 1 ELSE 0 END) AS Null_Duration
FROM Line_DownTime

SELECT 
    'Product' AS Table_Name,
    COUNT(*) AS Total_Rows,
    SUM(CASE WHEN Product_id IS NULL THEN 1 ELSE 0 END) AS Null_Product_ID,
    SUM(CASE WHEN Min_batch_time IS NULL THEN 1 ELSE 0 END) AS Null_Target_Time
FROM Products

SELECT 
    'DownTime_Factors' AS Table_Name,
    COUNT(*) AS Total_Rows,
    SUM(CASE WHEN Factor_ID IS NULL THEN 1 ELSE 0 END) AS Null_Factor_ID,
    SUM(CASE WHEN Description IS NULL OR Description = '' THEN 1 ELSE 0 END) AS Null_Description
FROM DownTime_Factors


--(Downtime Statistics)
SELECT 
    COUNT(Downtime_id) AS Total_Breakdowns,          -- عدد المرات اللي المكنة عطلت فيها
    SUM(DownTime_MIn) AS Total_Downtime_Mins,        -- إجمالي دقائق العطل
    AVG(DownTime_MIn) AS Avg_Downtime_Per_Batch,     -- متوسط وقت العطل في المرة الواحدة
    MIN(DownTime_MIn) AS Shortest_Downtime,          -- أقصر عطل (ممكن يكون تعديل بسيط)
    MAX(DownTime_MIn) AS Longest_Downtime,           -- أطول عطل (كارثة محتاجة تحليل)
    STDEV(DownTime_MIn) AS Downtime_Consistency      -- الانحراف المعياري (لو كبير يبقى الأعطال غير متوقعة)
FROM Line_Downtime


--(Grouped Statistics)
SELECT 
    d_f.Description,
    COUNT(d.Downtime_id) AS Frequency,
    SUM(d.DownTime_MIn) AS Total_Lost_Minutes,
    CAST(AVG(CAST(d.DownTime_MIn AS FLOAT)) AS DECIMAL(10,2)) AS Avg_Minutes
FROM Line_Downtime d
JOIN DownTime_Factors d_f ON d.Factor_ID = d_f.Factor_ID
GROUP BY d_f.Description
ORDER BY Total_Lost_Minutes DESC

--Operators (Performance Summary)
SELECT 
    Operator_Name,
    COUNT(Batch) AS Batches_Completed,
    AVG(DATEDIFF(SECOND, '00:00:00', Productin_Duration) / 60.0) AS Avg_Batch_Duration_Min,
    MAX(Productin_Duration) AS Slowest_Batch,
    MIN(Productin_Duration) AS Fastest_Batc
FROM Line_Productivity
GROUP BY Operator_Name
ORDER BY Avg_Batch_Duration_Min ASC


--=================================
--   Handling Missing Value
--=================================
SELECT * FROM Line_Productivity WHERE Batch IS NULL


UPDATE Line_Productivity
SET Operator_Name = ISNULL(Operator_Name, 'Unknown')
WHERE Operator_Name IS NULL OR Operator_Name = ''


UPDATE DownTime_Factors
SET Description = ISNULL(Description, 'Other/Unspecified')
WHERE Description IS NULL

UPDATE Line_DownTime
SET DownTime_MIn = 0
WHERE DownTime_MIn IS NULL

UPDATE Line_DownTime
SET DownTime_MIn = (SELECT AVG(DownTime_MIn) FROM Line_DownTime)
WHERE DownTime_MIn IS NULL


DELETE FROM Line_Productivity
WHERE Batch IS NULL

DELETE FROM Line_DownTime
WHERE Batch IS NULL

SELECT 
    Batch, 
    COALESCE(Operator_Name, 'Staff Member') AS Operator,
    COALESCE(Product_id, 'N/A') AS Product
FROM Line_Productivity



--======================
--   Correct Data Types
--======================

ALTER TABLE Line_Productivity
ALTER COLUMN [Date] DATE

ALTER TABLE Line_Productivity
ALTER COLUMN Start_Time TIME

ALTER TABLE Line_Productivity
ALTER COLUMN End_Time TIME

ALTER TABLE Line_Productivity
ALTER COLUMN Production_Duration TIME

ALTER TABLE Products
ALTER COLUMN Min_batch_time INT

ALTER TABLE Line_DownTime
ALTER COLUMN Downtime_Min INT

ALTER TABLE Line_DownTime
ALTER COLUMN Batch INT

--for Accuracy
SELECT COLUMN_NAME, DATA_TYPE 
FROM INFORMATION_SCHEMA.COLUMNS 
WHERE TABLE_NAME = 'Line_Downtime'

SELECT COLUMN_NAME, DATA_TYPE 
FROM INFORMATION_SCHEMA.COLUMNS 
WHERE TABLE_NAME = 'Products'

SELECT COLUMN_NAME, DATA_TYPE 
FROM INFORMATION_SCHEMA.COLUMNS 
WHERE TABLE_NAME = 'DownTime_Factors'
--=======================================
--   Standardize Categorical Values
--=======================================
--(TRIM)
UPDATE Line_Productivity
SET Operator_Name = TRIM(Operator_Name)

UPDATE Products
SET Flavor = TRIM(Flavor)

--(Upper/Lower Case)
UPDATE Line_Productivity 
SET Product_id = UPPER(Product_id)

UPDATE Products
SET Product_id = UPPER(Product_id)

UPDATE Products 
SET Flavor = UPPER(Flavor)

--(Typos)
UPDATE Line_Productivity
SET Operator_Name = 'Charlie'
WHERE Operator_Name IN ('Charly', 'charli', 'Chalie')

--(Mapping)
UPDATE Products
SET Size = '600ml'
WHERE Size IN ('600', '0.6L', '600 ML')

UPDATE Products
SET Size = '2000ml'
WHERE Size IN ('2000', '2 L', '2000 ML')

--============================
--     Handle Duplicates
--============================
--(Check Duplication Values)
SELECT Batch, Date, Product_id, Start_Time, COUNT(*) AS Occurrence_Count
FROM Line_Productivity
GROUP BY Batch, Date, Product_id, Start_Time
HAVING COUNT(*) > 1

SELECT Batch, Factor_ID, DownTime_MIn, COUNT(*) AS Duplicate_Entries
FROM Line_DownTime
GROUP BY Batch, Factor_ID, DownTime_MIn
HAVING COUNT(*) > 1

SELECT Product_id, COUNT(*) AS ID_Count
FROM Products
GROUP BY Product_id
HAVING COUNT(*) > 1

SELECT Factor_ID, COUNT(*) AS ID_Count
FROM DownTime_Factors
GROUP BY Factor_ID
HAVING COUNT(*) > 1

--(remove duplications)
WITH Deletion_CTE AS (
    SELECT *, 
           ROW_NUMBER() OVER (
               PARTITION BY Batch, Product_id, Start_Time 
           ) AS RowNumber
    FROM Line_Productivity
)

-- استعرضهم الأول للتأكد
-- لو تمام امسحهم
DELETE FROM Deletion_CTE WHERE RowNumber > 1


--============================
--     Feature Engineering
--============================
--(Shift Classification)
SELECT *,
    CASE 
        WHEN Start_Time >= '06:00:00' AND Start_Time < '14:00:00' THEN 'Morning'
        WHEN Start_Time >= '14:00:00' AND Start_Time < '22:00:00' THEN 'Afternoon'
        ELSE 'Night'
    END AS Shift_Name
FROM Line_Productivity

--(Net Run Time)
SELECT 
    p.Batch,
    p.Productin_Duration,
    COALESCE(d.Total_Downtime, 0) AS Total_Downtime_Min,
    -- تحويل الـ Duration لدقائق وطرح العطل منه
    (DATEDIFF(MINUTE, 0, CAST(p.Productin_Duration AS DATETIME)) - COALESCE(d.Total_Downtime, 0)) AS Net_Production_Min
FROM Line_Productivity p
LEFT JOIN (
    SELECT Batch, SUM(DownTime_MIn) AS Total_Downtime 
    FROM Line_DownTime GROUP BY Batch
) d ON p.Batch = d.Batch

--(Efficiency Score)
SELECT 
    p.Batch,
    pr.Flavor,
    pr.Min_batch_time AS Target_Min,
    (DATEDIFF(MINUTE, 0, CAST(p.Productin_Duration AS DATETIME))) AS Actual_Min,
    -- حساب النسبة المئوية للكفاءة
    CAST((pr.Min_batch_time * 100.0) / NULLIF(DATEDIFF(MINUTE, 0, CAST(p.Productin_Duration AS DATETIME)), 0) AS DECIMAL(10,2)) AS Efficiency_Percentage
FROM Line_Productivity p
JOIN Products pr ON p.Product_id = pr.Product_id

--(Status Flag)
SELECT Batch,
    CASE 
        WHEN DATEDIFF(MINUTE, 0, CAST(Productin_Duration AS DATETIME)) <= (SELECT Min_batch_time FROM Products WHERE Product_id = Line_Productivity.Product_id) THEN 'On Time'
        WHEN DATEDIFF(MINUTE, 0, CAST(Productin_Duration AS DATETIME)) <= (SELECT Min_batch_time + 15 FROM Products WHERE Product_id = Line_Productivity.Product_id) THEN 'Slight Delay'
        ELSE 'Critical Delay'
    END AS Production_Status
FROM Line_Productivity


--==================================
--   View of Master Rename column
--==================================
EXEC sp_rename 'Line_Productivity.Production_Date', 'Date', 'COLUMN'
EXEC sp_rename 'Line_Productivity.Productin_Duration', 'Gross_Run_Time', 'COLUMN'
EXEC sp_rename 'Line_DownTime.Duration_Min', 'Lost_Time_Minutes', 'COLUMN'


-----------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------

SELECT * FROM Products
SELECT * FROM Line_Productivity
SELECT * FROM Line_DownTime
SELECT * FROM DownTime_Factors


ALTER TABLE Line_Productivity
ADD productin_Duration AS 
    DATEDIFF(MINUTE, 
        CAST(Date AS DATETIME) + CAST(Start_time AS DATETIME), 
        CASE 
            WHEN End_time < Start_time 
            THEN DATEADD(DAY, 1, CAST(Date AS DATETIME) + CAST(End_time AS DATETIME))
            ELSE CAST(Date AS DATETIME) + CAST(End_time AS DATETIME)
        END
    )


ALTER TABLE Line_productivity
ADD Shift NVARCHAR(50),
    P_Status NVARCHAR(50)


UPDATE Line_productivity
SET Shift = 
CASE 
    WHEN CAST(Start_Time AS TIME) BETWEEN '06:00:00' AND '13:59:59' THEN 'MORNING'
    WHEN CAST(Start_Time AS TIME) BETWEEN '14:00:00' AND '21:59:59' THEN 'AFTERNOON'
    ELSE 'NIGHT'
END


UPDATE p
SET p.P_Status = CASE 
    WHEN (DATEPART(HOUR, p.Productin_Duration) * 60 + DATEPART(MINUTE, p.Productin_Duration)) <= pr.Min_batch_time 
        THEN 'ON TIME'
    ELSE 'DELAY'
END
FROM Line_productivity p
JOIN Products pr ON p.Product_id = pr.Product_id

----------------------------------------------------------------------------------------------------------------------------------------------
--This view allows you to answer these questions with a single click:
--Was the delay in the batch due to justifiable downtime or employee laziness?
--Which shift is most consistent with the target time?
--Which flavor takes longer than allowed?

CREATE OR ALTER VIEW Production_Master_Report
AS
SELECT 
    p.Batch,
    p.Date,
    p.Product_id,
    pr.Flavor, 
    p.Operator_Name,
    p.Shift,
    p.P_Status,
    
    p.productin_Duration AS Actual_Min,
    pr.Min_batch_time AS Target_Min,
   
    ISNULL((SELECT SUM(DownTime_Min) FROM Line_DownTime WHERE Batch = p.Batch), 0) AS Total_Downtime_Min
FROM Line_productivity p
LEFT JOIN Products pr ON p.Product_id = pr.Product_id

SELECT * FROM Production_Master_Report



