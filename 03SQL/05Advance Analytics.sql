-- FILE 3: ADVANCED ANALYTICS — Window Functions, CTEs & Complex Logic
-- SQL concepts    : CTEs, Window Functions (RANK, NTILE, LAG, SUM OVER,
--                   AVG OVER), CASE, subqueries, date arithmetic

-- Q1. CUSTOMER RFM ANALYSIS (Recency, Frequency, Monetary)
WITH rfm_base AS (
    SELECT
        c.customer_unique_id,
        EXTRACT(DAY FROM (
            (SELECT MAX(order_purchase_timestamp) FROM orders_dataset)
            - MAX(o.order_purchase_timestamp)
        ))::INT                                             AS recency_days,
        COUNT(DISTINCT o.order_id)                          AS frequency,
        ROUND(SUM(op.payment_value), 2)                     AS monetary
    FROM customers_dataset c
    JOIN orders_dataset o          ON c.customer_id = o.customer_id
    JOIN order_payments_dataset op ON o.order_id    = op.order_id
    WHERE o.order_status != 'canceled'
    GROUP BY c.customer_unique_id
),
rfm_scored AS (
    SELECT
        customer_unique_id,
        recency_days,
        frequency,
        monetary,
        NTILE(5) OVER (ORDER BY recency_days DESC)  AS r_score,  
        NTILE(5) OVER (ORDER BY frequency    ASC)    AS f_score,
        NTILE(5) OVER (ORDER BY monetary     ASC)    AS m_score
    FROM rfm_base
)
SELECT
    customer_unique_id,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    (r_score + f_score + m_score)                        AS rfm_total,
    CASE
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
        WHEN r_score >= 4 AND f_score >= 2                   THEN 'Loyal Customers'
        WHEN r_score >= 4                                     THEN 'Recent Customers'
        WHEN r_score >= 3 AND f_score >= 3                   THEN 'Potential Loyalists'
        WHEN r_score <= 2 AND f_score >= 3                   THEN 'At Risk'
        WHEN r_score <= 2 AND f_score <= 2 AND m_score <= 2  THEN 'Lost'
        ELSE 'Others'
    END                                                  AS rfm_segment
FROM rfm_scored
ORDER BY rfm_total DESC, monetary DESC
LIMIT 50;

-- Q2. ROLLING 30-DAY REVENUE AVERAGE
WITH daily_revenue AS (
    SELECT
        o.order_purchase_timestamp::DATE                    AS order_date,
        COUNT(DISTINCT o.order_id)                          AS daily_orders,
        ROUND(SUM(op.payment_value), 2)                     AS daily_revenue
    FROM orders_dataset o
    JOIN order_payments_dataset op ON o.order_id = op.order_id
    WHERE o.order_status != 'canceled'
    GROUP BY order_date
)
SELECT
    order_date,
    daily_orders,
    daily_revenue,
    ROUND(AVG(daily_revenue) OVER (
        ORDER BY order_date
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ), 2)                                                   AS rolling_30d_avg_revenue,
    ROUND(SUM(daily_revenue) OVER (
        ORDER BY order_date
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ), 2)                                                   AS rolling_30d_total_revenue
FROM daily_revenue
ORDER BY order_date;

-- Q3. MONTH-OVER-MONTH REVENUE GROWTH RATE
WITH monthly AS (
    SELECT
        DATE_TRUNC('month', o.order_purchase_timestamp)::DATE   AS month,
        COUNT(DISTINCT o.order_id)                              AS orders,
        ROUND(SUM(op.payment_value), 2)                         AS revenue
    FROM orders_dataset o
    JOIN order_payments_dataset op ON o.order_id = op.order_id
    WHERE o.order_status != 'canceled'
    GROUP BY month
)
SELECT
    month,
    orders,
    revenue,
    LAG(revenue) OVER (ORDER BY month)                          AS prev_month_revenue,
    revenue - LAG(revenue) OVER (ORDER BY month)                AS revenue_change,
    ROUND(
        (revenue - LAG(revenue) OVER (ORDER BY month))
        * 100.0
        / NULLIF(LAG(revenue) OVER (ORDER BY month), 0)
    , 2)                                                        AS growth_pct
FROM monthly
ORDER BY month;

-- Q4. FASTEST & SLOWEST DELIVERY SELLERS (CARRIER PROXY)
WITH seller_delivery AS (
    SELECT
        oi.seller_id,
        s.seller_city,
        s.seller_state,
        COUNT(DISTINCT oi.order_id)                            AS total_orders,
        PERCENTILE_CONT(0.5) WITHIN GROUP (
            ORDER BY EXTRACT(DAY FROM
                o.order_delivered_customer_date - o.order_purchase_timestamp
            )
        )                                                      AS median_delivery_days,
        ROUND(AVG(EXTRACT(DAY FROM
            o.order_estimated_delivery_date - o.order_delivered_customer_date
        )), 1)                                                 AS avg_days_ahead
    FROM orders_items_dataset oi
    JOIN orders_dataset o  ON oi.order_id  = o.order_id
    JOIN sellers_dataset s ON oi.seller_id = s.seller_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
    GROUP BY oi.seller_id, s.seller_city, s.seller_state
    HAVING COUNT(DISTINCT oi.order_id) >= 30   
),
ranked AS (
    SELECT
        *,
        RANK() OVER (ORDER BY median_delivery_days ASC)  AS fast_rank,
        RANK() OVER (ORDER BY median_delivery_days DESC) AS slow_rank
    FROM seller_delivery
)
(
    SELECT 'FASTEST' AS category, seller_id, seller_city, seller_state,
           total_orders, ROUND(median_delivery_days::NUMERIC, 1) AS median_days,
           avg_days_ahead, fast_rank AS rank
    FROM ranked
    WHERE fast_rank <= 10
    ORDER BY fast_rank
)
UNION ALL
(
    SELECT 'SLOWEST', seller_id, seller_city, seller_state,
           total_orders, ROUND(median_delivery_days::NUMERIC, 1), avg_days_ahead, slow_rank
    FROM ranked
    WHERE slow_rank <= 10
    ORDER BY slow_rank
);

-- Q5. CUSTOMER COHORT RETENTION ANALYSIS (First-Purchase Month Cohorts)
WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        DATE_TRUNC('month', o.order_purchase_timestamp)::DATE   AS order_month
    FROM orders_dataset o
    JOIN customers_dataset c ON o.customer_id = c.customer_id
    WHERE o.order_status != 'canceled'
),
first_purchase AS (
    SELECT
        customer_unique_id,
        MIN(order_month)     AS cohort_month
    FROM customer_orders
    GROUP BY customer_unique_id
),
cohort_activity AS (
    SELECT
        fp.cohort_month,
        EXTRACT(YEAR FROM AGE(co.order_month, fp.cohort_month)) * 12
        + EXTRACT(MONTH FROM AGE(co.order_month, fp.cohort_month))
                              AS months_since_first,
        co.customer_unique_id
    FROM customer_orders co
    JOIN first_purchase fp ON co.customer_unique_id = fp.customer_unique_id
)
SELECT
    cohort_month,
    COUNT(DISTINCT customer_unique_id)
        FILTER (WHERE months_since_first = 0)  AS month_0,
    COUNT(DISTINCT customer_unique_id)
        FILTER (WHERE months_since_first = 1)  AS month_1,
    COUNT(DISTINCT customer_unique_id)
        FILTER (WHERE months_since_first = 2)  AS month_2,
    COUNT(DISTINCT customer_unique_id)
        FILTER (WHERE months_since_first = 3)  AS month_3,
    COUNT(DISTINCT customer_unique_id)
        FILTER (WHERE months_since_first = 6)  AS month_6,
    COUNT(DISTINCT customer_unique_id)
        FILTER (WHERE months_since_first = 12) AS month_12
FROM cohort_activity
GROUP BY cohort_month
ORDER BY cohort_month;
