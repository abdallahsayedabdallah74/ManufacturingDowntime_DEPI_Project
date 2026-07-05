SELECT * FROM Products
SELECT * FROM Line_Productivity
SELECT * FROM Line_DownTime
SELECT * FROM DownTime_Factors

--------------------------------------- Productivity & Efficiency ------------------------------------
SELECT SUM(l.productin_Duration) as Total_production_Duration
FROM Line_Productivity l

SELECT Avg(productin_duration) as avg_duration
FROM Line_Productivity l

SELECT SUM(l_d.Downtime_Min)
FROM Line_DownTime l_d

SELECT 
    P_Status,
    COUNT(*) AS Total_Batches
FROM Line_Productivity
WHERE P_Status IN ('ON TIME', 'DELAY')
GROUP BY P_Status;

WITH Batch_Downtime AS
(
    SELECT
        Batch,
        SUM(Downtime_Min) AS Total_Downtime
    FROM Line_DownTime
    GROUP BY Batch
)

SELECT
    ROUND(
        (
            1 - (
                SUM(ISNULL(bd.Total_Downtime,0)) * 1.0
                / SUM(lp.Productin_Duration)
            )
        ) * 100
    ,2) AS Productivity_Score
FROM Line_Productivity lp
LEFT JOIN Batch_Downtime bd
    ON lp.Batch = bd.Batch;

--1: Production Trend by Date
SELECT 
    Date, 
    COUNT(Batch) AS Total_Batches,
    -- لحساب التغير عن اليوم السابق (اختياري)
    COUNT(Batch) - LAG(COUNT(Batch)) OVER (ORDER BY Date) AS Growth_Difference
FROM Line_Productivity
GROUP BY Date
ORDER BY Date

--2: Batch Density per Shift
SELECT 
    Shift, 
    COUNT(Batch) AS Total_Batches,
    -- بنقسم على عدد الأيام عشان نجيب المتوسط لكل وردية في اليوم الواحد
    CAST(COUNT(Batch) AS FLOAT) / COUNT(DISTINCT Date) AS Avg_Batches_Per_Day
FROM Line_Productivity
GROUP BY Shift
ORDER BY Avg_Batches_Per_Day DESC

--3: Product Mix Ratio
SELECT 
    Product_id, 
    COUNT(Batch) AS Batch_Count,
    -- حساب النسبة المئوية
    CAST(COUNT(Batch) * 100.0 / SUM(COUNT(Batch)) OVER() AS DECIMAL(10,2)) AS Production_Percentage
FROM Line_Productivity
GROUP BY Product_id
ORDER BY Production_Percentage DESC


--## Time Loss Analysis:
--4: Gap Analysis (Total Actual vs. Ideal Time)
SELECT 
    P.Product_id,
    COUNT(P.Batch) AS Total_Batches,
    SUM(Pr.Min_batch_time) AS Target_Duration_Min,
    SUM(P.productin_Duration) AS Actual_Duration_Min, -- هنا التغيير: جمع مباشر
    
    -- حساب الفرق (الوقت الضائع)
    SUM(P.productin_Duration) - SUM(Pr.Min_batch_time) AS Total_Variance_Min
    
FROM Line_Productivity P
JOIN Products Pr ON P.Product_id = Pr.Product_id
GROUP BY P.Product_id
ORDER BY Total_Variance_Min DESC

--5: Utilization Rate (Daily)
-------  How many hours per day does the line operate out of 24 hours? 
SELECT 
    Date,
    SUM(productin_Duration) AS Total_Work_Minutes,
    -- بنقسم على 1440 اللي هو عدد دقائق اليوم الكامل
    CAST(SUM(productin_Duration) / 1440.0 * 100 AS DECIMAL(10,2)) AS Utilization_Percentage
FROM Line_Productivity
GROUP BY Date
ORDER BY Date

--6: Longest vs. Shortest Batch
---- Which batch took the longest time (Outlier), and why? 
SELECT TOP 5
    P.Batch, 
    P.Product_id,
    P.productin_Duration AS Duration_Min,
    (SELECT STRING_AGG(F.Description, ', ') 
     FROM Line_DownTime D 
     JOIN DownTime_Factors F ON D.Factor_ID = F.Factor_ID 
     WHERE D.Batch = P.Batch) AS Reasons
FROM Line_Productivity P
ORDER BY P.productin_Duration DESC 

---- Which was the fastest batch completed? 
SELECT TOP 5 
    Batch, 
    Product_id,
    productin_Duration AS Duration_Min 
FROM Line_Productivity
ORDER BY productin_Duration ASC


--## Sequence Analysis (Changeover & Idle):
--7: Changeover Frequency
WITH ProductChanges AS (
    SELECT Date, Product_id,
           LAG(Product_id) OVER (PARTITION BY Date ORDER BY Start_time) AS Prev_Product
    FROM Line_Productivity
)
SELECT Date, COUNT(*) AS Changeover_Count
FROM ProductChanges
WHERE Prev_Product IS NOT NULL AND Product_id <> Prev_Product
GROUP BY Date;

--8: (Idle Time Gap daily)
WITH Gaps AS (
    SELECT Date, End_time,
           LEAD(Start_time) OVER (PARTITION BY Date ORDER BY Start_time) AS Next_Start
    FROM Line_Productivity
)
SELECT Date, SUM(DATEDIFF(MINUTE, End_time, Next_Start)) AS Total_Idle_Gap_Min
FROM Gaps
WHERE Next_Start IS NOT NULL
GROUP BY Date

--9: General Production Analysis
-- What is the total number of batches (Total Batches) for each product? 
-- What is the average actual production duration for each product? 
-- How many times was the status marked as ON TIME versus DELAY? (Percentage ratio) 
SELECT 
    Product_id, 
    COUNT(Batch) AS Total_Batches,
    AVG(productin_Duration) AS Avg_Actual_Duration,
    -- نسبة الالتزام بالمواعيد
    CAST(SUM(CASE WHEN P_Status = 'ON TIME' THEN 1 ELSE 0 END) * 100.0 / COUNT(Batch) AS DECIMAL(10,2)) AS On_Time_Percentage
FROM Line_Productivity
GROUP BY Product_id

-- Which day recorded the highest production volume? 
SELECT TOP 1 Date, COUNT(Batch) AS Max_Production_Volume
FROM Line_Productivity
GROUP BY Date
ORDER BY Max_Production_Volume DESC

--## Efficiency Analysis:
--10: Efficiency Gap
SELECT 
    P.Batch,
    P.Product_id,
    PR.Min_batch_time AS Target_Min,
    CASE 
        WHEN P.End_time < P.Start_time 
        THEN DATEDIFF(MINUTE, P.Start_time, P.End_time) + 1440 
        ELSE DATEDIFF(MINUTE, P.Start_time, P.End_time) 
    END AS Actual_Min,
    
    (CASE 
        WHEN P.End_time < P.Start_time 
        THEN DATEDIFF(MINUTE, P.Start_time, P.End_time) + 1440 
        ELSE DATEDIFF(MINUTE, P.Start_time, P.End_time) 
    END) - PR.Min_batch_time AS Gap_Min
FROM Line_Productivity P
JOIN Products PR ON P.Product_id = PR.Product_id
ORDER BY Gap_Min DESC

--11: Shift Analysis
SELECT 
    P.Shift,
    SUM(P.PRODUCTIN_DURATION) AS total_D_per_Shift,
    AVG(P.batch_delay) AS Avg_Delay_Per_Batch
FROM (
    SELECT 
        P.Shift,
        P.Batch,
        P.PRODUCTIN_DURATION,
        (P.PRODUCTIN_DURATION - PR.Min_batch_time) AS batch_delay
    FROM Line_Productivity P
    JOIN Products PR 
        ON P.Product_id = PR.Product_id
) P
GROUP BY P.Shift
ORDER BY  total_D_per_Shift DESC;

--12: Product Size Impact
SELECT 
    PR.Size,
    COUNT(P.Batch) AS Total_Batches,
    AVG(P.productin_Duration) AS Avg_Actual_Time, -- استخدام العمود المصلح
    AVG(PR.Min_batch_time) AS Avg_Target_Time,
    AVG(P.productin_Duration - PR.Min_batch_time) AS Avg_Efficiency_Loss
FROM Line_Productivity P
JOIN Products PR ON P.Product_id = PR.Product_id
GROUP BY PR.Size;

--13: Performance Consistency
--عشان نعرف هل المشغل بيبدأ نشيط وبيكسل في الآخر؟ هنقسم الوردية لنصفين (أول 4 ساعات وتاني 4 ساعات) ونقارن.
WITH ShiftOrder AS (
    SELECT 
        Batch, 
        Shift, 
        Operator_name,
        -- استبدال DATEDIFF بالعمود الجاهز المصلح
        (P.productin_Duration - PR.Min_batch_time) AS Delay,
        ROW_NUMBER() OVER(PARTITION BY Date, Shift, Operator_name ORDER BY Start_time) AS Batch_Order
    FROM Line_Productivity P
    JOIN Products PR ON P.Product_id = PR.Product_id
)
SELECT 
    CASE WHEN Batch_Order <= 3 THEN 'Beginning of Shift' ELSE 'End of Shift' END AS Shift_Phase,
    AVG(Delay) AS Avg_Delay_Minutes
FROM ShiftOrder
GROUP BY CASE WHEN Batch_Order <= 3 THEN 'Beginning of Shift' ELSE 'End of Shift' END

-- KPIs:
-- Productivity Score & Average Delay & OTDR
SELECT 
    P.Product_id,
    -- 1. Productivity Score (%)
    CAST(AVG((PR.Min_batch_time * 100.0) / 
	     NULLIF(P.productin_Duration, 0)) AS DECIMAL(10,2)) AS Productivity_Score_Pct,

    -- 2. Average Delay per Batch
    AVG(P.productin_Duration - PR.Min_batch_time) AS Avg_Delay_Min,

    -- 3. On-Time Delivery Rate (OTDR)
    CAST(SUM(CASE WHEN P.P_Status = 'ON TIME' THEN 1 ELSE 0 END) * 100.0 / 
	     COUNT(P.Batch) AS DECIMAL(10,2)) AS OTDR_Pct

FROM Line_Productivity P
JOIN Products PR ON P.Product_id = PR.Product_id
GROUP BY P.Product_id


-- Throughput (Units/Liters per Hour)
SELECT 
    P.Product_id,
    PR.Size,
    -- إجمالي الوحدات (باتشات * حجم المنتج) مقسوم على إجمالي الساعات
    CAST(
        SUM(CASE WHEN PR.Size = '2 L' THEN 2.0 ELSE 0.6 END) 
        / 
        NULLIF(SUM(P.productin_Duration) / 60.0, 0) 
    AS DECIMAL(10,2)) AS Liters_Per_Hour
FROM Line_Productivity P
JOIN Products PR ON P.Product_id = PR.Product_id
GROUP BY P.Product_id, PR.Size

-- Volume Share
SELECT 
    Product_id,
    COUNT(Batch) AS Batch_Count,
    CAST(COUNT(Batch) * 100.0 / SUM(COUNT(Batch)) OVER() AS DECIMAL(10,2)) AS Volume_Share_Pct
FROM Line_Productivity
GROUP BY Product_id
ORDER BY Volume_Share_Pct DESC

-- Delay-Only Analysis
SELECT 
    P.Product_id,
    COUNT(P.Batch) AS Delayed_Batches_Count,
    -- نستخدم العمود المصلح مباشرة
    AVG(P.productin_Duration - PR.Min_batch_time) AS Avg_Delay_Time_Minutes
FROM Line_Productivity P
JOIN Products PR ON P.Product_id = PR.Product_id
WHERE P.P_Status = 'DELAY'
GROUP BY P.Product_id



--
SELECT 
    P.Product_id,
    COUNT(P.Batch) AS Total_Batches,
    
    -- عدد الباتشات التي اكتملت في موعدها
    SUM(CASE WHEN P.P_Status = 'ON TIME' THEN 1 ELSE 0 END) AS On_Time_Batches_Count,
    
    -- النسبة المئوية للالتزام بالمواعيد
    CAST(SUM(CASE WHEN P.P_Status = 'ON TIME' THEN 1 ELSE 0 END) * 100.0 / 
         COUNT(P.Batch) AS DECIMAL(10,2)) AS OTDR_Pct
FROM Line_Productivity P
GROUP BY P.Product_id;

































SELECT 
    Shift,
    SUM(productin_Duration) AS Total_Production_Duration
FROM Line_Productivity
GROUP BY Shift
ORDER BY Total_Production_Duration DESC;

SELECT 
    P.Shift,
    AVG(P.productin_Duration - PR.Min_batch_time) AS Avg_Delay_Per_Batch
FROM Line_Productivity P
JOIN Products PR 
    ON P.Product_id = PR.Product_id
GROUP BY P.Shift
ORDER BY Avg_Delay_Per_Batch DESC;


SELECT 
    Shift,
    CAST(
        SUM(CASE WHEN P_Status = 'ON TIME' THEN 1 ELSE 0 END) * 100.0 
        / COUNT(*) 
    AS DECIMAL(10,2)) AS On_Time_Percentage
FROM Line_Productivity
GROUP BY Shift
ORDER BY On_Time_Percentage DESC;

SELECT 
    Shift,
    COUNT(Batch) AS Total_Batches
FROM Line_Productivity
GROUP BY Shift
ORDER BY Total_Batches DESC;

SELECT 
    Shift,
    SUM(productin_Duration) AS Total_Operating_Time
FROM Line_Productivity
GROUP BY Shift
ORDER BY Total_Operating_Time DESC;

SELECT 
    P.Shift,
    SUM(P.productin_Duration - PR.Min_batch_time) AS Total_Efficiency_Loss_Min
FROM Line_Productivity P
JOIN Products PR 
    ON P.Product_id = PR.Product_id
GROUP BY P.Shift
ORDER BY Total_Efficiency_Loss_Min DESC;

SELECT 
    Shift,
    Date,
    COUNT(Batch) AS Daily_Batches
FROM Line_Productivity
GROUP BY Shift, Date
ORDER BY Date;













SELECT 
    Operator_name,
    COUNT(Batch) AS Total_Batches
FROM Line_Productivity
GROUP BY Operator_name
ORDER BY Total_Batches DESC;





SELECT 
    P.Operator_name,
    AVG(P.productin_Duration - PR.Min_batch_time) AS Avg_Delay_Per_Batch
FROM Line_Productivity P
JOIN Products PR 
    ON P.Product_id = PR.Product_id
GROUP BY P.Operator_name
ORDER BY Avg_Delay_Per_Batch DESC;




SELECT 
    Operator_name,
    COUNT(Batch) AS Delayed_Batches_Count
FROM Line_Productivity
WHERE P_Status = 'DELAY'
GROUP BY Operator_name
ORDER BY Delayed_Batches_Count DESC;



WITH Operator_Shift_Phase AS (
    SELECT 
        Operator_name,
        Shift,
        Batch,
        (productin_Duration - PR.Min_batch_time) AS Delay,
        ROW_NUMBER() OVER (
            PARTITION BY Operator_name, Shift 
            ORDER BY Start_time
        ) AS Batch_Order
    FROM Line_Productivity P
    JOIN Products PR 
        ON P.Product_id = PR.Product_id
)
SELECT 
    Operator_name,
    CASE 
        WHEN Batch_Order <= 3 THEN 'Early Shift'
        ELSE 'Late Shift'
    END AS Shift_Phase,
    AVG(Delay) AS Avg_Delay
FROM Operator_Shift_Phase
GROUP BY 
    Operator_name,
    CASE 
        WHEN Batch_Order <= 3 THEN 'Early Shift'
        ELSE 'Late Shift'
    END
ORDER BY Operator_name, Shift_Phase;


WITH Operator_Performance AS (
    SELECT 
        Operator_name,
        (productin_Duration - PR.Min_batch_time) AS Delay
    FROM Line_Productivity P
    JOIN Products PR 
        ON P.Product_id = PR.Product_id
)
SELECT 
    Operator_name,
    AVG(Delay) AS Avg_Delay,
    STDEV(Delay) AS Delay_Variation
FROM Operator_Performance
GROUP BY Operator_name
ORDER BY Delay_Variation ASC;























SELECT 
    Product_id,
    COUNT(Batch) AS Batch_Count
FROM Line_Productivity
GROUP BY Product_id
ORDER BY Batch_Count DESC;


SELECT 
    Product_id,
    COUNT(Batch) AS Batch_Count,
    CAST(
        COUNT(Batch) * 100.0 / SUM(COUNT(Batch)) OVER()
    AS DECIMAL(10,2)) AS Volume_Share_Pct
FROM Line_Productivity
GROUP BY Product_id
ORDER BY Volume_Share_Pct DESC;


SELECT 
    COUNT(DISTINCT Product_id) AS Total_Products
FROM Products;

SELECT 
    COUNT(DISTINCT Flavor) AS Total_Flavors
FROM Products;


SELECT 
    COUNT(DISTINCT Operator_name) AS Total_Operators
FROM Line_Productivity;

SELECT 
    P.Product_id,
    AVG(P.productin_Duration) AS Avg_Production_Time
FROM Line_Productivity P
GROUP BY P.Product_id
ORDER BY Avg_Production_Time DESC;

SELECT 
    P.Product_id,
    AVG(P.productin_Duration - PR.Min_batch_time) AS Avg_Efficiency_Gap
FROM Line_Productivity P
JOIN Products PR 
    ON P.Product_id = PR.Product_id
GROUP BY P.Product_id
ORDER BY Avg_Efficiency_Gap DESC;


SELECT 
    PR.Size,
    AVG(P.productin_Duration) AS Avg_Actual_Time,
    AVG(PR.Min_batch_time) AS Avg_Target_Time,
    AVG(P.productin_Duration - PR.Min_batch_time) AS Avg_Loss
FROM Line_Productivity P
JOIN Products PR 
    ON P.Product_id = PR.Product_id
GROUP BY PR.Size
ORDER BY Avg_Loss DESC;



SELECT 
    Product_id,
    COUNT(Batch) AS Delayed_Batches_Count
FROM Line_Productivity
WHERE P_Status = 'DELAY'
GROUP BY Product_id
ORDER BY Delayed_Batches_Count DESC;


SELECT 
    Product_id,
    COUNT(Batch) AS Batch_Count,
    CAST(
        COUNT(Batch) * 100.0 / SUM(COUNT(Batch)) OVER()
    AS DECIMAL(10,2)) AS Production_Mix_Pct
FROM Line_Productivity
GROUP BY Product_id
ORDER BY Production_Mix_Pct DESC;


SELECT 
    P.Product_id,
    CAST(
        AVG((PR.Min_batch_time * 100.0) / NULLIF(P.productin_Duration, 0))
    AS DECIMAL(10,2)) AS Productivity_Score
FROM Line_Productivity P
JOIN Products PR 
    ON P.Product_id = PR.Product_id
GROUP BY P.Product_id
ORDER BY Productivity_Score DESC;






--------------------------------------- Downtime Analysis ------------------------------------

SELECT 
    SUM(Downtime_Min) AS Total_Downtime_Minutes
FROM Line_DownTime;


SELECT 
    AVG(Downtime_Min) AS MTTR_Minutes
FROM Line_DownTime;


SELECT 
    CAST(
        SUM(D.Downtime_Min) * 100.0 /
        NULLIF((SELECT SUM(productin_Duration)
                FROM Line_Productivity),0)
    AS DECIMAL(10,2)) AS Downtime_Ratio_Pct
FROM Line_DownTime D;

SELECT 
    CAST(
        (
            (
                SUM(P.productin_Duration) -
                SUM(ISNULL(D.Downtime_Min,0))
            ) * 100.0
        ) / NULLIF(SUM(P.productin_Duration),0)
    AS DECIMAL(10,2)) AS Availability_Score_Pct
FROM Line_Productivity P
LEFT JOIN Line_DownTime D
    ON P.Batch = D.Batch;






















--1: What is the most frequent downtime factor? 
SELECT 
    F.Description,
    COUNT(D.Downtime_id) AS Occurrence_Count
FROM Line_DownTime D
JOIN DownTime_Factors F ON D.Factor_ID = F.Factor_ID
GROUP BY F.Description
ORDER BY Occurrence_Count DESC

--2: Which factor consumes the highest downtime duration? 
SELECT TOP 5
    F.Description,
    SUM(D.Downtime_Min) AS Total_Downtime_Minutes
FROM Line_DownTime D
JOIN DownTime_Factors F ON D.Factor_ID = F.Factor_ID
GROUP BY F.Description
ORDER BY Total_Downtime_Minutes DESC

--3: What is the total downtime for each shift? 
SELECT 
    P.Shift,
    SUM(D.Downtime_Min) AS Total_Downtime_Min
FROM Line_DownTime D
JOIN Line_Productivity P ON D.Batch = P.Batch
GROUP BY P.Shift
ORDER BY Total_Downtime_Min DESC

--4: What is the total downtime for each day? 
SELECT 
    P.Date,
    SUM(D.Downtime_Min) AS Total_Downtime_Min
FROM Line_DownTime D
JOIN Line_Productivity P ON D.Batch = P.Batch
GROUP BY P.Date
ORDER BY P.Date

--5: What percentage of failures falls under Operator Error versus machine failures? 
SELECT 
    CASE 
        WHEN F.Operator_Error = 'Yes' THEN 'Operator'
        WHEN F.Operator_Error = 'No' THEN 'Non Operator'
        ELSE 'Other' 
    END AS Error_Category,
    CAST(SUM(D.Downtime_Min) * 100.0 / SUM(SUM(D.Downtime_Min)) OVER() AS DECIMAL(10,2)) AS Loss_Percentage
FROM Line_DownTime D
JOIN DownTime_Factors F ON D.Factor_ID = F.Factor_ID
GROUP BY F.Operator_Error;

--6: Pareto Analysis (80/20)
WITH CauseStats AS (
    SELECT 
        F.Description,
        SUM(D.Downtime_Min) AS Total_Min,
        SUM(SUM(D.Downtime_Min)) OVER(ORDER BY SUM(D.Downtime_Min) DESC) AS Cumulative_Min,
        SUM(SUM(D.Downtime_Min)) OVER() AS Grand_Total
    FROM Line_DownTime D
    JOIN DownTime_Factors F ON D.Factor_ID = F.Factor_ID
    GROUP BY F.Description
)
SELECT 
    Description, 
    Total_Min,
    CAST((Cumulative_Min * 100.0 / Grand_Total) AS DECIMAL(10,2)) AS Cumulative_Percentage
FROM CauseStats
WHERE (Cumulative_Min - Total_Min) * 100.0 / Grand_Total < 80; 
-- الأسباب اللي بتطلع هنا هي المسؤولة عن أول 80% من المشاكل




SELECT
    F.Description,
    SUM(D.Downtime_Min) AS Total_Downtime_Min,
    CAST(
        SUM(D.Downtime_Min) * 100.0 /
        SUM(SUM(D.Downtime_Min)) OVER()
    AS DECIMAL(10,2)) AS Downtime_Percentage
FROM Line_DownTime D
JOIN DownTime_Factors F
    ON D.Factor_ID = F.Factor_ID
GROUP BY F.Description
SELECT
    P.Operator_name,
    SUM(D.Downtime_Min) AS Total_Downtime_Min,
    CAST(
        SUM(D.Downtime_Min) * 100.0 /
        SUM(SUM(D.Downtime_Min)) OVER()
    AS DECIMAL(10,2)
    ) AS Downtime_Pct
FROM Line_DownTime D
JOIN Line_Productivity P
    ON D.Batch = P.Batch
GROUP BY P.Operator_name
ORDER BY Total_Downtime_Min DESC;

















--7: Product Impact on Failures
--هل فيه منتج معين "نحس" على الخط؟ مثلاً بيسبب مشاكل في الملصقات (Label Switch) أكتر من غيره؟
SELECT 
    P.Product_id,
    F.Description AS Failure_Type,
    COUNT(D.Downtime_id) AS Occurrence_Count,
    SUM(D.Downtime_Min) AS Total_Lost_Time
FROM Line_DownTime D
JOIN Line_Productivity P ON D.Batch = P.Batch
JOIN DownTime_Factors F ON D.Factor_ID = F.Factor_ID
WHERE F.Description IN ('Batch change', 'Label switch', 'Labeling error')
GROUP BY P.Product_id, F.Description
ORDER BY P.Product_id, Total_Lost_Time DESC

--8: Operator-Failure Correlation
SELECT 
    P.Operator_name,
    F.Description AS Failure_Reason,
    COUNT(D.Downtime_id) AS Frequency
FROM Line_DownTime D
JOIN Line_Productivity P ON D.Batch = P.Batch
JOIN DownTime_Factors F ON D.Factor_ID = F.Factor_ID
WHERE F.Operator_Error = 'Yes'
GROUP BY P.Operator_name, F.Description
HAVING COUNT(D.Downtime_id) > 1 -- بنظهر فقط الأخطاء المتكررة لنفس الشخص
ORDER BY Frequency DESC

--9: Failure Timing (Night vs. Morning)
SELECT 
    P.Shift,
    AVG(D.Downtime_Min) AS Avg_Downtime_Duration,
    SUM(D.Downtime_Min) AS Total_Downtime_Min,
    COUNT(D.Downtime_id) AS Number_of_Incidents
FROM Line_DownTime D
JOIN Line_Productivity P ON D.Batch = P.Batch
WHERE P.Shift IN ('Morning', 'Night') -- أو استخدم M و N حسب اختصاراتك
GROUP BY P.Shift

--10: Setup / Changeover Analysis:
-- How many minutes are lost due to Batch Change setup time? 
-- Is this time consistent, or does it increase in certain shifts? 
SELECT 
    P.Shift,
    COUNT(D.Downtime_id) AS Number_of_Setups,
    SUM(D.Downtime_Min) AS Total_Setup_Minutes,
    AVG(D.Downtime_Min) AS Avg_Setup_Time_Per_Batch
FROM Line_DownTime D
JOIN DownTime_Factors F ON D.Factor_ID = F.Factor_ID
JOIN Line_Productivity P ON D.Batch = P.Batch
WHERE F.Description = 'Batch change'
GROUP BY P.Shift
ORDER BY Avg_Setup_Time_Per_Batch DESC

-- Downtime Effect on Batch Status:
--11: Is there a relationship between certain downtime factors and DELAY status?
SELECT 
    F.Description AS Downtime_Factor,
    COUNT(CASE WHEN P.P_Status = 'DELAY' THEN 1 END) AS Delay_Occurrences,
    SUM(D.Downtime_Min) AS Total_Downtime_Min
FROM Line_DownTime D
JOIN Line_Productivity P ON D.Batch = P.Batch
JOIN DownTime_Factors F ON D.Factor_ID = F.Factor_ID
GROUP BY F.Description
ORDER BY Delay_Occurrences DESC

--12: Are specific products (e.g. RB-600) 
--        repeatedly associated with Labeling Errors or Calibration Errors? 
SELECT 
    P.Product_id,
    F.Description AS Failure_Type,
    COUNT(D.Downtime_id) AS Frequency
FROM Line_DownTime D
JOIN Line_Productivity P ON D.Batch = P.Batch
JOIN DownTime_Factors F ON D.Factor_ID = F.Factor_ID
WHERE F.Description IN ('Labeling error', 'Calibration error', 'Label switch')
GROUP BY P.Product_id, F.Description
ORDER BY Frequency DESC

--13: Night Shift vs. Machine Failure
SELECT 
    P.Shift,
    F.Description AS Failure_Type,
    COUNT(D.Downtime_id) AS Incident_Count,
    SUM(D.Downtime_Min) AS Total_Minutes_Lost
FROM Line_DownTime D
JOIN Line_Productivity P ON D.Batch = P.Batch
JOIN DownTime_Factors F ON D.Factor_ID = F.Factor_ID
WHERE F.Description = 'Machine failure'
GROUP BY P.Shift, F.Description
ORDER BY Incident_Count DESC

--KPIs:
--14: MTTR (Mean Time to Repair)
SELECT 
    AVG(Downtime_Min) AS MTTR_Minutes
FROM Line_DownTime

--15: Downtime Ratio (%)
SELECT 
    (SELECT SUM(Downtime_Min) FROM Line_DownTime) AS Total_Downtime_Min,
    
    (SELECT SUM(productin_Duration) FROM Line_Productivity) AS Total_Production_Duration_Min,
    
    -- النسبة المئوية الصحيحة (إجمالي الأعطال / إجمالي الإنتاج الصافي)
    CAST(
        (SELECT SUM(Downtime_Min) FROM Line_DownTime) * 100.0 / 
        (SELECT SUM(productin_Duration) FROM Line_Productivity) 
    AS DECIMAL(10,2)) AS Corrected_Downtime_Ratio_Pct

--16: Availability Score
SELECT 
    100 - CAST(SUM(D.Downtime_Min) * 100.0 / SUM(DATEDIFF(MINUTE, P.Start_time, P.End_time)) AS DECIMAL(10,2)) AS Availability_Score_Pct
FROM Line_DownTime D
JOIN Line_Productivity P ON D.Batch = P.Batch

--17: Lost Batches Estimation
--كان ممكن ننتج كام باتش زيادة لو مكنش فيه تعطل؟
SELECT 
    P.Product_id,
    SUM(D.Downtime_Min) AS Total_Downtime_Min,
    PR.Min_batch_time,
    CAST(SUM(D.Downtime_Min) * 1.0 / PR.Min_batch_time AS DECIMAL(10,1)) AS Estimated_Lost_Batches
FROM Line_DownTime D
JOIN Line_Productivity P ON D.Batch = P.Batch
JOIN Products PR ON P.Product_id = PR.Product_id
GROUP BY P.Product_id, PR.Min_batch_time

--18: MTBF (Mean Time Between Failures)
--متوسط وقت تشغيل الماكينة بين كل عطل والتاني.
SELECT 
    SUM(DATEDIFF(MINUTE, P.Start_time, P.End_time)) / COUNT(D.Downtime_id) AS MTBF_Minutes
FROM Line_Productivity P
LEFT JOIN Line_DownTime D ON P.Batch = D.Batch

--19: Human Error Rate
SELECT 
    COUNT(D.Downtime_id) AS Total_Incidents,
    
    -- عدد أخطاء العنصر البشري
    SUM(CASE WHEN F.Operator_Error = 'Yes' THEN 1 ELSE 0 END) AS Human_Error_Count,
    
    -- إجمالي دقائق أعطال البشر
    SUM(CASE WHEN F.Operator_Error = 'Yes' THEN D.Downtime_Min ELSE 0 END) AS Human_Error_Total_Min,
    
    -- النسبة المئوية من وقت التعطل الكلي
    CAST(SUM(CASE WHEN F.Operator_Error = 'Yes' THEN D.Downtime_Min ELSE 0 END) * 100.0 / 
         NULLIF(SUM(D.Downtime_Min), 0) AS DECIMAL(10,2)) AS Human_Error_Time_Rate_Pct,
         
    -- النسبة المئوية من عدد الحوادث الكلي
    CAST(SUM(CASE WHEN F.Operator_Error = 'Yes' THEN 1 ELSE 0 END) * 100.0 / 
         NULLIF(COUNT(D.Downtime_id), 0) AS DECIMAL(10,2)) AS Human_Error_Freq_Rate_Pct
FROM Line_DownTime D
JOIN DownTime_Factors F ON D.Factor_ID = F.Factor_ID;

--20: Explained vs Unexplained Delays (Hidden Loss)
SELECT 
    P.Batch, P.Product_id, P.P_Status,
    CASE WHEN D.Downtime_id IS NULL THEN 'Unexplained Delay (Hidden)' ELSE 'Explained' END AS Delay_Type
FROM Line_Productivity P
LEFT JOIN Line_DownTime D ON P.Batch = D.Batch
WHERE P.P_Status = 'DELAY' AND D.Downtime_id IS NULL
--(لو لقيت باتشات DELAY ومعندهاش Downtime، يبقى فيه وقت "بيسرقنا" ومحدش بيسجله!).

--21: Repeated Minor Failures vs Major Failures
SELECT 
    F.Description,
    COUNT(D.Downtime_id) AS Frequency,
    SUM(D.Downtime_Min) AS Total_Duration,
    CASE 
        -- عطل بيتكرر كتير (أكتر من 5 مرات) ومدته صغيرة (أقل من 20 دقيقة)
        WHEN COUNT(D.Downtime_id) > 5 AND AVG(D.Downtime_Min) < 20 THEN 'Frequent Minor Failure'
        
        -- عطل بياخد وقت طويل جداً في المرة الواحدة (أكتر من 45 دقيقة)
        WHEN AVG(D.Downtime_Min) > 45 THEN 'Major Failure (Long Repair)'
        
        -- عطل "مزمن": بيتكرر كتير جداً ومجموع وقته ضخم (أكتر من 200 دقيقة)
        WHEN COUNT(D.Downtime_id) > 8 AND SUM(D.Downtime_Min) > 200 THEN 'Chronic High-Impact Failure'
        
        ELSE 'Normal'
    END AS Failure_Category
FROM Line_DownTime D
JOIN DownTime_Factors F ON D.Factor_ID = F.Factor_ID
GROUP BY F.Description
ORDER BY Total_Duration DESC;



--------------------------------------- Operator ------------------------------------
--1: Most Productive Operator
---- Which operator recorded the highest number of batches? 
SELECT TOP 1
    Operator_name,
    COUNT(Batch) AS Total_Batches
FROM Line_Productivity
GROUP BY Operator_name
ORDER BY Total_Batches DESC

--2: Fastest Operator
---- Which operator has the lowest average production time for the same product? 
SELECT 
    Product_id,
    Operator_name,
    AVG(productin_Duration) AS Avg_Production_Time
FROM Line_Productivity
GROUP BY Product_id, Operator_name
ORDER BY Product_id, Avg_Production_Time ASC

--3: On-Time Performance
---- What is each operator’s ON TIME percentage? 
SELECT 
    Operator_name,
    COUNT(Batch) AS Total_Batches,
    SUM(CASE WHEN P_Status = 'ON TIME' THEN 1 ELSE 0 END) AS On_Time_Batches,
    CAST(SUM(CASE WHEN P_Status = 'ON TIME' THEN 1 ELSE 0 END) * 100.0 / COUNT(Batch) AS DECIMAL(10,2)) AS OT_Percentage
FROM Line_Productivity
GROUP BY Operator_name
ORDER BY OT_Percentage DESC

--4: Target Achievement
---- Which operator performs closest to Min_Batch_Time? 
SELECT 
    P.Operator_name,
    SUM(P.productin_Duration) AS Total_Actual_Duration,
    SUM(PR.Min_batch_time) AS Total_Target_Duration,
    
    -- الحسبة الصحيحة: مجموع التارجت / مجموع الفعلي
    CAST(SUM(PR.Min_batch_time) * 100.0 / NULLIF(SUM(P.productin_Duration), 0) 
    AS DECIMAL(10,2)) AS Real_Efficiency_Score
FROM Line_Productivity P
JOIN Products PR ON P.Product_id = PR.Product_id
GROUP BY P.Operator_name
ORDER BY Real_Efficiency_Score DESC

--5: Most Frequent Operator Errors
---- Which operator is associated with the highest number of operator errors? 
SELECT 
    P.Operator_name,
    COUNT(DISTINCT P.Batch) AS Total_Batches_Worked,
    COUNT(D.Downtime_id) AS Error_Count,
    CAST(COUNT(D.Downtime_id) * 100.0 / COUNT(DISTINCT P.Batch) AS DECIMAL(10,2)) AS Error_Rate_Per_Batch_Pct
FROM Line_Productivity P
LEFT JOIN Line_DownTime D ON P.Batch = D.Batch
LEFT JOIN DownTime_Factors F ON D.Factor_ID = F.Factor_ID AND F.Operator_Error = 'Yes'
GROUP BY P.Operator_name
ORDER BY Error_Rate_Per_Batch_Pct DESC;

--6: Most Common Error Type per Operator
WITH OperatorErrorStats AS (
    SELECT 
        P.Operator_name,
        F.Description AS Error_Type,
        COUNT(D.Downtime_id) AS Frequency,
        RANK() OVER (PARTITION BY P.Operator_name ORDER BY COUNT(D.Downtime_id) DESC) AS Error_Rank
    FROM Line_DownTime D
    JOIN Line_Productivity P ON D.Batch = P.Batch
    JOIN DownTime_Factors F ON D.Factor_ID = F.Factor_ID
    WHERE F.Operator_Error = 'Yes'
    GROUP BY P.Operator_name, F.Description
)
SELECT Operator_name, Error_Type, Frequency
FROM OperatorErrorStats
WHERE Error_Rank = 1;

--7: Total Lost Time by Operator
SELECT 
    P.Operator_name,
    COUNT(D.Downtime_id) AS Total_Incidents,
    SUM(D.Downtime_Min) AS Total_Lost_Minutes,
    AVG(D.Downtime_Min) AS Avg_Downtime_Per_Incident
FROM Line_Productivity P
LEFT JOIN Line_DownTime D ON P.Batch = D.Batch
GROUP BY P.Operator_name
ORDER BY Total_Lost_Minutes DESC

--8: MTTR (Mean Time To Recovery)
---- Which operator restores operation fastest after a failure? 
SELECT 
    P.Operator_name,
    COUNT(D.Downtime_id) AS Total_Failures,
    SUM(D.Downtime_Min) AS Total_Downtime_Min,
    -- متوسط وقت الإصلاح لكل مشغل
    CAST(AVG(D.Downtime_Min * 1.0) AS DECIMAL(10,2)) AS MTTR_Min
FROM Line_Productivity P
JOIN Line_DownTime D ON P.Batch = D.Batch
GROUP BY P.Operator_name
ORDER BY MTTR_Min ASC


--9: Product Variety Effect
---- Does operator efficiency drop when moving from 600ml products to 2L products? 
SELECT 
    P.Operator_name,
    PR.Size,
    COUNT(P.Batch) AS Total_Batches,
    SUM(PR.Min_batch_time) AS Total_Target_Duration,
    SUM(P.productin_Duration) AS Total_Actual_Duration,
    CAST(SUM(PR.Min_batch_time) * 100.0 / NULLIF(SUM(P.productin_Duration), 0) AS DECIMAL(10,2)) AS Efficiency_Score
FROM Line_Productivity P
JOIN Products PR ON P.Product_id = PR.Product_id
GROUP BY P.Operator_name, PR.Size
ORDER BY P.Operator_name, PR.Size;


--10: Performance Consistency
---- Is operator performance consistent across shifts?
SELECT 
    Operator_name,
    Shift,
    COUNT(Batch) AS Total_Batches,
    SUM(CASE WHEN P_Status = 'ON TIME' THEN 1 ELSE 0 END) AS On_Time_Batches,
    CAST(SUM(CASE WHEN P_Status = 'ON TIME' THEN 1 ELSE 0 END) * 100.0 / 
         NULLIF(COUNT(Batch), 0) AS DECIMAL(10,2)) AS OTDR_Pct
FROM Line_Productivity
GROUP BY Operator_name, Shift
ORDER BY Operator_name, Shift


--KPIs: 
--11: Operator Efficiency Index 
SELECT 
    Operator_name,
    SUM(Target_Duration) AS Total_Target,
    SUM(Actual_Duration) AS Total_Actual,
    CAST(SUM(Target_Duration) * 100.0 / NULLIF(SUM(Actual_Duration), 0) AS DECIMAL(10,2)) AS Efficiency_Index
FROM (
    SELECT P.Operator_name, PR.Min_batch_time AS Target_Duration, P.productin_Duration AS Actual_Duration
    FROM Line_Productivity P
    JOIN Products PR ON P.Product_id = PR.Product_id
) AS Sub
GROUP BY Operator_name
ORDER BY Efficiency_Index DESC

--12:  Error-Free Run Time
---- Average production time without Operator Errors. 
SELECT 
    P.Operator_name,
    AVG(P.productin_Duration) AS Avg_Run_Time_Without_Errors
FROM Line_Productivity P
WHERE P.Batch NOT IN (
    SELECT DISTINCT Batch 
    FROM Line_DownTime D
    JOIN DownTime_Factors F ON D.Factor_ID = F.Factor_ID
    WHERE F.Operator_Error = 'Yes'
)
GROUP BY P.Operator_name
ORDER BY Avg_Run_Time_Without_Errors DESC;

--13: Waste Contribution
---- Estimated waste or lost time caused by each operator. 
SELECT 
    P.Operator_name,
    -- استخدام Subquery لحساب وقت الإنتاج الحقيقي بدون تكرار
    (SELECT SUM(productin_Duration) 
     FROM Line_Productivity 
     WHERE Operator_name = P.Operator_name) AS Total_Production_Duration,
    
    SUM(D.Downtime_Min) AS Total_Downtime_Minutes,
    
    SUM(CASE WHEN F.Operator_Error = 'Yes' THEN D.Downtime_Min ELSE 0 END) AS Operator_Mistake_Minutes,
    
    CAST(SUM(CASE WHEN F.Operator_Error = 'Yes' THEN D.Downtime_Min ELSE 0 END) * 100.0 / 
         NULLIF(SUM(D.Downtime_Min), 0) AS DECIMAL(10,2)) AS Operator_Responsibility_Pct

FROM Line_Productivity P
LEFT JOIN Line_DownTime D ON P.Batch = D.Batch
LEFT JOIN DownTime_Factors F ON D.Factor_ID = F.Factor_ID
GROUP BY P.Operator_name
ORDER BY Total_Production_Duration DESC;

--14: Fatigue Effect
---- Does continuous working time affect operator efficiency?
WITH RankedBatches AS (
    SELECT 
        Operator_name,
        productin_Duration,
        ROW_NUMBER() OVER (PARTITION BY Operator_name ORDER BY Start_Time ASC) AS Batch_Order_Start,
        ROW_NUMBER() OVER (PARTITION BY Operator_name ORDER BY Start_Time DESC) AS Batch_Order_End
    FROM Line_Productivity
)
SELECT 
    Operator_name,
    AVG(CASE WHEN Batch_Order_Start <= 2 THEN productin_Duration END) AS Early_Batch_Avg_Time,
    AVG(CASE WHEN Batch_Order_End <= 2 THEN productin_Duration END) AS Late_Batch_Avg_Time
FROM RankedBatches
GROUP BY Operator_name;





--------------------------------------- Shift Analysis ------------------------------------
--1: Shift Productivity
---- Which shift produces the highest batch volume? 
SELECT 
    Shift,
    COUNT(Batch) AS Total_Batches,
    SUM(productin_Duration) AS Total_Production_Time
FROM Line_Productivity
GROUP BY Shift
ORDER BY Total_Batches DESC;

--2: Downtime Patterns
-- Does a certain shift have more downtime? 
-- Are these failures machine-related or material shortages? 
SELECT 
    P.Shift,
    F.Description,
    SUM(D.Downtime_Min) AS Total_Downtime_Minutes,
    COUNT(D.Downtime_id) AS Failure_Count
FROM Line_Productivity P
JOIN Line_DownTime D ON P.Batch = D.Batch
JOIN DownTime_Factors F ON D.Factor_ID = F.Factor_ID
GROUP BY P.Shift, F.Description
ORDER BY P.Shift, Total_Downtime_Minutes DESC;

--3: On-Time Delivery Rate per Shift
-- Which shift performs best against target time? 
SELECT 
    Shift,
    COUNT(Batch) AS Total_Batches,
    SUM(CASE WHEN P_Status = 'ON TIME' THEN 1 ELSE 0 END) AS On_Time_Count,
    CAST(SUM(CASE WHEN P_Status = 'ON TIME' THEN 1 ELSE 0 END) * 100.0 / COUNT(Batch) AS DECIMAL(10,2)) AS OTDR_Percentage
FROM Line_Productivity
GROUP BY Shift
ORDER BY OTDR_Percentage DESC;

--4: Shift Handover Impact
-- Do batches spanning two shifts take longer due to handover issues? 
SELECT 
    CASE WHEN Start_Shift = End_Shift THEN 'Same Shift' ELSE 'Across Shifts (Handover)' END AS Execution_Type,
    AVG(productin_Duration) AS Avg_Duration,
    COUNT(Batch) AS Batch_Count
FROM (
    -- نفترض هنا أن لديك عمود يحدد وردية البداية والنهاية أو وقت البداية والنهاية
    SELECT Batch, productin_Duration, Shift AS Start_Shift, Shift AS End_Shift -- عدل المنطق بناءً على بياناتك
    FROM Line_Productivity
) AS Sub
GROUP BY 
  CASE 
     WHEN Start_Shift = End_Shift 
     THEN 'Same Shift' 
     ELSE 'Across Shifts (Handover)' 
  END;

--5: 5. Human Factor
---- Is any shift associated with more Operator Errors? 
SELECT 
    P.Shift,
    SUM(D.Downtime_Min) AS Grand_Total_Waste_Minutes,
    COUNT(D.Downtime_id) AS Total_Incidents_Count,
    SUM(CASE WHEN F.Operator_Error = 'Yes' THEN D.Downtime_Min ELSE 0 END) AS Operator_Waste_Minutes,
    SUM(CASE WHEN F.Operator_Error = 'Yes' THEN 1 ELSE 0 END) AS Operator_Error_Occurrence,
    CAST(SUM(CASE WHEN F.Operator_Error = 'Yes' THEN D.Downtime_Min ELSE 0 END) * 100.0 / 
         NULLIF(SUM(D.Downtime_Min), 0) AS DECIMAL(10,2)) AS Human_Factor_Pct
FROM Line_Productivity P
LEFT JOIN Line_DownTime D ON P.Batch = D.Batch
LEFT JOIN DownTime_Factors F ON D.Factor_ID = F.Factor_ID
GROUP BY P.Shift
ORDER BY Grand_Total_Waste_Minutes DESC;

--KPIs:
--6: OTDR per Shift
SELECT 
    Shift,
    COUNT(Batch) AS Total_Batches,
    SUM(CASE WHEN P_Status = 'ON TIME' THEN 1 ELSE 0 END) AS On_Time_Batches,
    CAST(SUM(CASE WHEN P_Status = 'ON TIME' THEN 1 ELSE 0 END) * 100.0 / COUNT(Batch) AS DECIMAL(10,2)) AS OTDR_Pct
FROM Line_Productivity
GROUP BY Shift
ORDER BY OTDR_Pct DESC;

--7: Human Factor Impact
SELECT 
    P.Shift,
    SUM(CASE WHEN F.Operator_Error = 'Yes' THEN D.Downtime_Min ELSE 0 END) AS Operator_Waste_Minutes,
    SUM(D.Downtime_Min) AS Total_Downtime_Minutes,
    CAST(SUM(CASE WHEN F.Operator_Error = 'Yes' THEN D.Downtime_Min ELSE 0 END) * 100.0 / 
         NULLIF(SUM(D.Downtime_Min), 0) AS DECIMAL(10,2)) AS Human_Factor_Pct
FROM Line_Productivity P
LEFT JOIN Line_DownTime D ON P.Batch = D.Batch
LEFT JOIN DownTime_Factors F ON D.Factor_ID = F.Factor_ID
GROUP BY P.Shift;

--8: Downtime Severity
SELECT 
    P.Shift,
    SUM(D.Downtime_Min) AS Total_Downtime_Minutes,
    COUNT(D.Downtime_id) AS Number_of_Incidents,
    -- متوسط مدة العطل الواحد (لقياس سرعة الاستجابة)
    CAST(AVG(D.Downtime_Min * 1.0) AS DECIMAL(10,2)) AS Avg_Downtime_Per_Incident
FROM Line_Productivity P
LEFT JOIN Line_DownTime D ON P.Batch = D.Batch
GROUP BY P.Shift
ORDER BY Total_Downtime_Minutes DESC;

--9: Operator Error Occurrence
SELECT 
    P.Shift,
    COUNT(D.Downtime_id) AS Total_Errors_Count,
    SUM(CASE WHEN F.Operator_Error = 'Yes' THEN 1 ELSE 0 END) AS Human_Errors_Only,
    -- نسبة عدد الحوادث البشرية من إجمالي عدد الحوادث
    CAST(SUM(CASE WHEN F.Operator_Error = 'Yes' THEN 1 ELSE 0 END) * 100.0 / 
         COUNT(D.Downtime_id) AS DECIMAL(10,2)) AS Error_Frequency_Pct
FROM Line_Productivity P
JOIN Line_DownTime D ON P.Batch = D.Batch
JOIN DownTime_Factors F ON D.Factor_ID = F.Factor_ID
GROUP BY P.Shift;



--------------------------------------- Product Analysis ------------------------------------
--1: Complexity vs Efficiency
-- Do 2L products consistently have higher delays than 600ml products?
SELECT 
    PR.Size,
    (SELECT SUM(productin_Duration) 
     FROM Line_Productivity 
     WHERE Product_ID IN (SELECT Product_ID 
	                      FROM Products 
						  WHERE Size = PR.Size)
						  ) AS Total_Production_Min,
    SUM(D.Downtime_Min) AS Total_Downtime,
	AVG(P.productin_Duration) AS Avg_Production_Time,
    CAST(SUM(D.Downtime_Min) * 100.0 / 
        (SELECT SUM(productin_Duration) 
         FROM Line_Productivity 
         WHERE Product_ID IN (SELECT Product_ID 
		                      FROM Products 
							  WHERE Size = PR.Size)
							  ) AS DECIMAL(10,2)) AS Delay_Impact_Pct
FROM Products PR
LEFT JOIN Line_Productivity P ON PR.Product_ID = P.Product_ID
LEFT JOIN Line_DownTime D ON P.Batch = D.Batch
GROUP BY PR.Size;

--2: Flavor Impact
-- Does a specific flavor (e.g. Root Berry or Lemon Lime) cause more machine issues or Product Spill incidents? 
SELECT 
    PR.Flavor,
	COUNT(P.Batch) AS Total_Batches,
    SUM(P.productin_Duration) AS Total_Production_Minutes,
    AVG(P.productin_Duration) AS Avg_Batch_Duration
FROM Line_Productivity P
JOIN Products PR ON P.Product_ID = PR.Product_ID
GROUP BY PR.Flavor
ORDER BY Avg_Batch_Duration DESC;

--3: Changeover Cost
-- How many minutes are lost during product changeovers (Factor ID:2)?
-- Does this vary by product type? 
SELECT 
    PR.Size,
    COUNT(D.Downtime_id) AS Changeover_Count,
    SUM(D.Downtime_Min) AS Total_Changeover_Minutes,
    AVG(D.Downtime_Min) AS Avg_Changeover_Duration
FROM Line_Productivity P
JOIN Products PR ON P.Product_ID = PR.Product_ID
JOIN Line_DownTime D ON P.Batch = D.Batch
WHERE D.Factor_ID = 2 -- كود تغيير المنتج
GROUP BY PR.Size


--4: Labeling Issues
-- Is any product more associated with Labeling Errors or Label Switch failures? 
SELECT 
    PR.Flavor,
    PR.Size,
    COUNT(D.Downtime_id) AS Labeling_Failures,
    SUM(D.Downtime_Min) AS Lost_Minutes
FROM Line_Productivity P
JOIN Products PR ON P.Product_ID = PR.Product_ID -- الربط بجدول المنتجات
JOIN Line_DownTime D ON P.Batch = D.Batch
JOIN DownTime_Factors F ON D.Factor_ID = F.Factor_ID
WHERE F.Description LIKE '%Label%' 
GROUP BY PR.Flavor, PR.Size
ORDER BY Labeling_Failures DESC;

--5: Product Priority
-- Based on data, which product is the easiest (usually On-Time) and which is the most difficult for the line? 
SELECT 
    PR.Product_id,
    PR.Size,
    COUNT(P.Batch) AS Total_Batches,
    SUM(CASE WHEN P.P_Status = 'ON TIME' THEN 1 ELSE 0 END) AS On_Time_Count,
    CAST(SUM(CASE WHEN P.P_Status = 'ON TIME' THEN 1 ELSE 0 END) * 100.0 / COUNT(P.Batch) AS DECIMAL(10,2)) AS Success_Rate_Pct
FROM Line_Productivity P
JOIN Products PR ON P.Product_ID = PR.Product_ID -- الربط هنا ضروري لجلب الاسم والحجم
GROUP BY PR.Product_id, PR.Size
ORDER BY Success_Rate_Pct DESC;

--6: Rate vs. Size
SELECT 
    PR.Size,
    MIN(P.productin_Duration) AS Fastest_Batch,
    MAX(P.productin_Duration) AS Slowest_Batch,
    AVG(P.productin_Duration) AS Avg_Batch_Duration,
    (MAX(P.productin_Duration) - MIN(P.productin_Duration)) AS Gap_Duration
FROM Line_Productivity P
JOIN Products PR ON P.Product_ID = PR.Product_ID
GROUP BY PR.Size;

--7: Flavor vs. Material Shortage
SELECT 
    PR.Flavor,
    COUNT(D.Downtime_id) AS Shortage_Incidents,
    SUM(D.Downtime_Min) AS Lost_Min_Due_To_Shortage
FROM Line_Productivity P
JOIN Products PR ON P.Product_ID = PR.Product_ID
JOIN Line_DownTime D ON P.Batch = D.Batch
JOIN DownTime_Factors F ON D.Factor_ID = F.Factor_ID
WHERE F.Description LIKE '%Material%' OR F.Description LIKE '%Shortage%'
GROUP BY PR.Flavor;

SELECT 
    PR.Flavor,
    COUNT(D.Downtime_id) AS Spill_Incidents,
    SUM(D.Downtime_Min) AS Waste_Minutes
FROM Line_Productivity P
JOIN Products PR ON P.Product_ID = PR.Product_ID
JOIN Line_DownTime D ON P.Batch = D.Batch
JOIN DownTime_Factors F ON D.Factor_ID = F.Factor_ID
WHERE F.Description = 'Product spill'
GROUP BY PR.Flavor;

SELECT 
    PR.Size,
    AVG(D.Downtime_Min) AS Avg_Changeover_Time,
    SUM(D.Downtime_Min) AS Total_Setup_Time
FROM Line_Productivity P
JOIN Products PR ON P.Product_ID = PR.Product_ID
JOIN Line_DownTime D ON P.Batch = D.Batch
JOIN DownTime_Factors F ON D.Factor_ID = F.Factor_ID
WHERE F.Description = 'Batch change'
GROUP BY PR.Size;

--8: Product Family Reliability
SELECT 
    CASE 
        WHEN PR.Flavor LIKE '%COLA%' THEN 'Cola'
        ELSE 'Juice'
    END AS Product_Family,
    AVG(P.productin_Duration) AS Avg_Duration,
    SUM(D.Downtime_Min) AS Total_Downtime
FROM Line_Productivity P
JOIN Products PR ON P.Product_ID = PR.Product_ID
LEFT JOIN Line_DownTime D ON P.Batch = D.Batch
GROUP BY 
    CASE 
	    WHEN PR.Flavor LIKE '%COLA%' THEN 'Cola'
        ELSE 'Juice'
    END;

--KPIs:
--9: Shift-Product Matrix
-- A matrix showing average production time for each product in each shift. 
SELECT 
    PR.Product_id,
    AVG(CASE WHEN P.Shift = 'MORNING' THEN P.productin_Duration END) AS Morning_Avg_Time,
    AVG(CASE WHEN P.Shift = 'AFTERNOON' THEN P.productin_Duration END) AS Afternoon_Avg_Time,
    AVG(CASE WHEN P.Shift = 'NIGHT' THEN P.productin_Duration END) AS Night_Avg_Time
FROM Line_Productivity P
JOIN Products PR ON P.Product_ID = PR.Product_ID
GROUP BY PR.Product_id;

--10: Average Downtime per Product
-- Average downtime minutes for each product.
SELECT 
    PR.Product_id,
    CAST(AVG(ISNULL(D.Downtime_Min, 0) * 1.0) AS DECIMAL(10,2)) AS Avg_Downtime_Minutes,
    SUM(D.Downtime_Min) AS Total_Waste_Minutes
FROM Products PR
LEFT JOIN Line_Productivity P ON PR.Product_ID = P.Product_ID
LEFT JOIN Line_DownTime D ON P.Batch = D.Batch
GROUP BY PR.Product_id
ORDER BY Avg_Downtime_Minutes DESC;

--11: Capacity Utilization by Product Type
-- Line utilization ratio by Small vs Large products.
SELECT 
    PR.Size,
    SUM(P.productin_Duration) AS Correct_Total_Run_Time,
    SUM(D.Total_Downtime_Min) AS Total_Down_Time,
    CAST(SUM(PR.Min_batch_time) * 100.0 / 
	NULLIF(SUM(P.productin_Duration), 0) AS DECIMAL(10,2)) AS Utilization_Rate_Pct
FROM Products PR
JOIN Line_Productivity P ON PR.Product_ID = P.Product_ID
LEFT JOIN (
    -- تجميع الأعطال لكل باتش في جدول فرعي لمنع التكرار عند الربط
    SELECT Batch, SUM(Downtime_Min) AS Total_Downtime_Min
    FROM Line_DownTime
    GROUP BY Batch
) D ON P.Batch = D.Batch
GROUP BY PR.Size;

--12: Standard Time Validation
-- Is the 38-minute difference actually respected, or do 2L products consume much more time in reality? 
SELECT 
    PR.Size,
	MIN(P.productin_Duration) AS Min_Time, 
    MAX(P.productin_Duration) AS Max_Time,
    AVG(P.productin_Duration) AS Actual_Avg_Duration,
    CASE WHEN PR.Size = '600ml' THEN 60 ELSE 98 END AS Target_Time,
    AVG(P.productin_Duration) - (CASE WHEN PR.Size = '600ml' THEN 60 ELSE 98 END) AS Variance_Minutes
FROM Products PR
JOIN Line_Productivity P ON PR.Product_ID = P.Product_ID
GROUP BY PR.Size;

-------------------------------------------------------------------------------

--Performance Variance:
SELECT 
    PR.Size,
    PR.Flavor,
    MIN(P.productin_Duration) AS Best_Run,
    MAX(P.productin_Duration) AS Worst_Run,
    (MAX(P.productin_Duration) - MIN(P.productin_Duration)) AS Performance_Gap
FROM Line_Productivity P
JOIN Products PR ON P.Product_ID = PR.Product_ID
GROUP BY PR.Size, PR.Flavor
ORDER BY Performance_Gap DESC;

--Time-of-Day Impact:
SELECT 
    P.Shift,
    COUNT(D.Downtime_id) AS Number_of_Stops,
    SUM(D.Downtime_Min) AS Total_Downtime_Minutes,
    AVG(D.Downtime_Min) AS Avg_Repair_Time
FROM Line_Productivity P
JOIN Line_DownTime D ON P.Batch = D.Batch
GROUP BY P.Shift;

--Chronic vs. Acute Failures:
SELECT 
    F.Description,
    COUNT(D.Downtime_id) AS Frequency, -- التكرار
    SUM(D.Downtime_Min) AS Total_Impact_Minutes, -- التأثير الكلي
    AVG(D.Downtime_Min) AS Avg_Duration_Per_Stop
FROM Line_DownTime D
JOIN DownTime_Factors F ON D.Factor_ID = F.Factor_ID
GROUP BY F.Description
ORDER BY Total_Impact_Minutes DESC;

--Operator vs. Machine Issues:
SELECT 
    P.Operator_name,
    COUNT(D.Downtime_id) AS Issues_Handled,
    AVG(D.Downtime_Min) AS Response_Repair_Speed
FROM Line_Productivity P
JOIN Line_DownTime D ON P.Batch = D.Batch
JOIN DownTime_Factors F ON D.Factor_ID = F.Factor_ID
WHERE F.Description LIKE '%Machine%'
GROUP BY P.Operator_name
ORDER BY Response_Repair_Speed ASC;

--السؤال 1: يخبرك بمدى قابلية التنبؤ (Predictability) بإنتاجك.
--السؤال 2 و 4: يركزان على العنصر البشري وإدارة الوقت.
--السؤال 3: يوجه فريق الصيانة للتركيز على المشاكل الحقيقية بدل إضاعة الوقت في أعطال بسيطة.





