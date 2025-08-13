-- Northwind Sales Analysis

USE Northwind;
GO

-- =======================================
-- 1. Top 10 Best-Selling Products by Revenue
-- Business Question: Which products have generated the most revenue, and who supplies them?

-- Logic:
-- 1. Join OrderDetails -> Products -> Suppliers.
-- 2. Compute revenue as Quantity × Price.
-- 3. Group by product and supplier.
-- 4. Order by revenue descending, select top 10.
-- =======================================

WITH ProductRevenue AS (
    SELECT 
        p.ProductName,
        s.SupplierName,
        ROUND(SUM(p.Price * od.Quantity), 2) AS TotalRevenue
    FROM 
        OrderDetails od
    JOIN Orders o 
        ON od.OrderID = o.OrderID
    JOIN Products p 
        ON od.ProductID = p.ProductID
    JOIN Suppliers s 
        ON p.SupplierID = s.SupplierID
    GROUP BY 
        p.ProductName, s.SupplierName
)
SELECT TOP 10 
    ProductName,
    SupplierName,
    TotalRevenue
FROM ProductRevenue
ORDER BY TotalRevenue DESC;

-- =======================================
-- 2. High-Value Customers (Customer Lifetime Value)
-- Business Question: Who are our top 10 customers by total spend, and how many orders have they placed?

-- Logic:
-- 1. Join Orders -> Customers -> OrderDetails.
-- 2. Compute total spend per customer.
-- 3. Count total orders per customer.
-- 4. Sort by total spend descending, select top 10.
-- =======================================

WITH CustomerSales AS (
    SELECT 
        c.CustomerID,
        c.CustomerName,
        SUM(p.Price * od.Quantity) AS TotalRevenue,
        COUNT(DISTINCT o.OrderID) AS OrderCount
    FROM OrderDetails od
    JOIN Orders o 
        ON od.OrderID = o.OrderID
    JOIN Customers c 
        ON o.CustomerID = c.CustomerID
    JOIN Products p 
        ON od.ProductID = p.ProductID
    GROUP BY c.CustomerID, c.CustomerName
)
SELECT TOP 10
    CustomerName,
    OrderCount,
    ROUND(TotalRevenue, 2) AS TotalRevenue
FROM CustomerSales
ORDER BY TotalRevenue DESC;

-- =======================================
-- 3. Sales by Product Category and Country
-- Business Question: Which product categories are most popular in each country, and what is their total revenue?

-- Logic:
-- 1. Join OrderDetails -> Products -> Categories -> Orders -> Customers.
-- 2. Group by category and customer country.
-- 3. Sum total revenue per category-country pair.
-- 4. Order by revenue descending within each country.
-- =======================================

WITH CategoryCountrySales AS (
    SELECT 
        cat.CategoryName,
        cust.Country,
        SUM(p.Price * od.Quantity) AS TotalRevenue
    FROM OrderDetails od
    JOIN Products p 
        ON od.ProductID = p.ProductID
    JOIN Categories cat 
        ON p.CategoryID = cat.CategoryID
    JOIN Orders o 
        ON od.OrderID = o.OrderID
    JOIN Customers cust 
        ON o.CustomerID = cust.CustomerID
    GROUP BY cat.CategoryName, cust.Country
)
SELECT 
    CategoryName,
    Country,
    ROUND(TotalRevenue, 2) AS TotalRevenue
FROM CategoryCountrySales
ORDER BY Country, TotalRevenue DESC;

-- =======================================
-- 4. Employee Sales Leaderboard
-- Business Question: Which sales representatives brought in the most revenue last year, and what is their average order size?

-- Logic:
-- 1. Join Orders -> Employees -> OrderDetails.
-- 2. Sum total revenue per employee for last year.
-- 3. Calculate average order value per employee.
-- 4. Sort by total revenue descending.
-- =======================================

WITH EmployeeSales AS (
    SELECT 
        e.EmployeeID,
        e.FirstName + ' ' + e.LastName AS EmployeeName,
        o.OrderID,
        SUM(p.Price * od.Quantity) AS OrderRevenue
    FROM OrderDetails od
    JOIN Orders o 
        ON od.OrderID = o.OrderID
    JOIN Products p 
        ON od.ProductID = p.ProductID
    JOIN Employees e 
        ON o.EmployeeID = e.EmployeeID
    WHERE YEAR(o.OrderDate) = (
        SELECT MAX(YEAR(OrderDate)) FROM Orders
    )
    GROUP BY e.EmployeeID, e.FirstName, e.LastName, o.OrderID
),
EmployeeSummary AS (
    SELECT
        EmployeeName,
        SUM(OrderRevenue) AS TotalRevenue,
        ROUND(AVG(OrderRevenue), 2) AS AvgOrderSize
    FROM EmployeeSales
    GROUP BY EmployeeName
)
SELECT 
    EmployeeName,
    ROUND(TotalRevenue, 2) AS TotalRevenue,
    AvgOrderSize
FROM EmployeeSummary
ORDER BY TotalRevenue DESC;

-- =======================================
-- 5. Supplier Contribution to Revenue
-- Business Question: Which suppliers account for the highest share of total sales, and which categories do they dominate?

-- Logic:
-- 1. Join OrderDetails -> Products -> Suppliers -> Categories.
-- 2. Sum total revenue per supplier.
-- 3. Identify top categories for each supplier using revenue.
-- 4. Sort suppliers by total revenue share.
-- =======================================

WITH SupplierCategoryRevenue AS (
    SELECT
        s.SupplierID,
        s.SupplierName,
        c.CategoryName,
        SUM(p.Price * od.Quantity) AS CategoryRevenue
    FROM OrderDetails od
    JOIN Products p 
        ON od.ProductID = p.ProductID
    JOIN Suppliers s 
        ON p.SupplierID = s.SupplierID
    JOIN Categories c 
        ON p.CategoryID = c.CategoryID
    GROUP BY s.SupplierID, s.SupplierName, c.CategoryName
),
SupplierTotals AS (
    SELECT
        SupplierID,
        SupplierName,
        SUM(CategoryRevenue) AS TotalRevenue
    FROM SupplierCategoryRevenue
    GROUP BY SupplierID, SupplierName
),
SupplierRankedCategories AS (
    SELECT
        scr.SupplierID,
        scr.SupplierName,
        scr.CategoryName,
        scr.CategoryRevenue,
        st.TotalRevenue,
        ROUND(100.0 * scr.CategoryRevenue / st.TotalRevenue, 2) AS CategorySharePct,
        ROW_NUMBER() OVER (
            PARTITION BY scr.SupplierID 
            ORDER BY scr.CategoryRevenue DESC
        ) AS CategoryRank
    FROM SupplierCategoryRevenue scr
    JOIN SupplierTotals st
        ON scr.SupplierID = st.SupplierID
)
SELECT
    SupplierName,
    ROUND(TotalRevenue, 2) AS TotalRevenue,
    CategoryName AS DominantCategory,
    CategorySharePct AS DominantCategorySharePct
FROM SupplierRankedCategories
WHERE CategoryRank = 1
ORDER BY TotalRevenue DESC;

-- =======================================
-- 6. Monthly Sales Trend (2-Year Analysis)
-- Business Question: What is the month-over-month sales trend over the last two years, and in which months do sales peak?

-- Logic:
-- 1. Join Orders -> OrderDetails.
-- 2. Extract year and month from OrderDate.
-- 3. Sum total revenue per month for last 2 years.
-- 4. Order by year-month to see trend.
-- =======================================

WITH LatestYear AS (
    SELECT MAX(YEAR(OrderDate)) AS MaxYear
    FROM Orders
),
TwoYearSales AS (
    SELECT 
        YEAR(o.OrderDate) AS OrderYear,
        MONTH(o.OrderDate) AS OrderMonth,
        DATENAME(MONTH, o.OrderDate) AS MonthName,
        SUM(p.Price * od.Quantity) AS TotalRevenue
    FROM OrderDetails od
    JOIN Orders o 
        ON od.OrderID = o.OrderID
    JOIN Products p 
        ON od.ProductID = p.ProductID
    CROSS JOIN LatestYear ly
    WHERE YEAR(o.OrderDate) >= ly.MaxYear - 1
    GROUP BY YEAR(o.OrderDate), MONTH(o.OrderDate), DATENAME(MONTH, o.OrderDate)
),
RankedSales AS (
    SELECT
        OrderYear,
        OrderMonth,
        MonthName,
        TotalRevenue,
        LAG(TotalRevenue) OVER (ORDER BY OrderYear, OrderMonth) AS PrevMonthRevenue
    FROM TwoYearSales
)
SELECT
    OrderYear,
    OrderMonth,
    MonthName,
    ROUND(TotalRevenue, 2) AS TotalRevenue,
    ROUND(
        CASE 
            WHEN PrevMonthRevenue IS NULL THEN NULL
            ELSE ((TotalRevenue - PrevMonthRevenue) / PrevMonthRevenue) * 100
        END, 2
    ) AS MoM_Growth_Pct
FROM RankedSales
ORDER BY OrderYear, OrderMonth;

-- =======================================
-- 7. Order Size & Frequency Analysis
-- Business Question: What is the average, smallest, and largest number of products per order, and how frequently do large orders occur?

-- Logic:
-- 1. Count number of products per order from OrderDetails.
-- 2. Find average, smallest, largest order size.
-- 3. Count frequency of large orders (above chosen threshold).
-- =======================================

WITH OrderSizes AS (
    SELECT 
        o.OrderID,
        COUNT(od.ProductID) AS ProductsPerOrder
    FROM Orders o
    JOIN OrderDetails od 
        ON o.OrderID = od.OrderID
    GROUP BY o.OrderID
),
OrderStats AS (
    SELECT
        ROUND(AVG(ProductsPerOrder), 2) AS AvgOrderSize,
        MIN(ProductsPerOrder) AS MinOrderSize,
        MAX(ProductsPerOrder) AS MaxOrderSize
    FROM OrderSizes
),
LargeOrderCount AS (
    SELECT 
        COUNT(*) AS LargeOrders,
        COUNT(*) * 100.0 / (SELECT COUNT(*) FROM OrderSizes) AS LargeOrderPct
    FROM OrderSizes
    WHERE ProductsPerOrder > 10
)
SELECT 
    os.AvgOrderSize,
    os.MinOrderSize,
    os.MaxOrderSize,
    loc.LargeOrders,
    ROUND(loc.LargeOrderPct, 2) AS LargeOrderPct
FROM OrderStats os
CROSS JOIN LargeOrderCount loc;

-- =======================================
-- 8. Shipper Performance Analysis
-- Business Question: Which shippers handle the most orders?

-- Logic:
-- 1. Join Orders -> Shippers.
-- 2. Count number of orders per shipper.
-- 3. Sort by highest order count.
-- =======================================

WITH ShipperStats AS (
    SELECT 
        s.ShipperID,
        s.ShipperName,
        COUNT(o.OrderID) AS TotalOrders
    FROM Orders o
    JOIN Shippers s 
        ON o.ShipperID = s.ShipperID
    GROUP BY s.ShipperID, s.ShipperName
)
SELECT 
    ShipperName,
    TotalOrders,
    RANK() OVER (ORDER BY TotalOrders DESC) AS VolumeRank
FROM ShipperStats
ORDER BY VolumeRank;

-- =======================================
-- 9. High-Value Orders Breakdown
-- Business Question: Which orders had the highest total value, and what products did they include?

-- Logic:
-- 1. Join Orders -> OrderDetails -> Products.
-- 2. Calculate total order value.
-- 3. Filter top N highest-value orders.
-- 4. List products in each high-value order.
-- =======================================

WITH OrderValues AS (
    SELECT 
        o.OrderID,
        SUM(p.Price * od.Quantity) AS OrderTotal
    FROM OrderDetails od
    JOIN Products p 
        ON od.ProductID = p.ProductID
    JOIN Orders o 
        ON od.OrderID = o.OrderID
    GROUP BY o.OrderID
),
TopOrders AS (
    SELECT 
        OrderID,
        OrderTotal,
        RANK() OVER (ORDER BY OrderTotal DESC) AS OrderRank
    FROM OrderValues
)
SELECT 
    t.OrderID,
    t.OrderTotal,
    p.ProductName,
    od.Quantity,
    p.Price,
    (p.Price * od.Quantity) AS LineTotal
FROM TopOrders t
JOIN OrderDetails od 
    ON t.OrderID = od.OrderID
JOIN Products p 
    ON od.ProductID = p.ProductID
WHERE t.OrderRank <= 10
ORDER BY t.OrderTotal DESC, t.OrderID, LineTotal DESC;