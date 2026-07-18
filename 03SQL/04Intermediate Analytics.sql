-- FILE 2: INTERMEDIATE ANALYTICS — Relational & Time-Based Insights
-- SQL concepts    : JOIN, HAVING, DATE_TRUNC, EXTRACT, DATE_PART,
--                  CASE expressions, multiple aggregations

-- Q1. AVERAGE DELIVERY TIME BY CUSTOMER STATE
SELECT
    c.customer_state                                               AS state,
    COUNT(*)                                                       AS delivered_orders,
    ROUND(AVG(EXTRACT(DAY FROM
        o.order_delivered_customer_date - o.order_purchase_timestamp
    )), 1)                                                         AS avg_delivery_days,
    ROUND(AVG(EXTRACT(DAY FROM
        o.order_estimated_delivery_date - o.order_delivered_customer_date
    )), 1)                                                         AS avg_days_ahead_of_estimate
FROM orders_dataset o
JOIN customers_dataset c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
HAVING COUNT(*) >= 100          -- filter out states with very few orders
ORDER BY avg_delivery_days ASC;

-- Q2. TOP 10 BEST-SELLING PRODUCT CATEGORIES BY REVENUE
SELECT
    COALESCE(t.product_category_name_english, p.product_category_name, 'Unknown')
                                           AS category_english,
    COUNT(DISTINCT oi.order_id)            AS total_orders,
    SUM(oi.order_item_id)                  AS total_items,       
    ROUND(SUM(oi.price), 2)                AS total_revenue,
    ROUND(SUM(oi.freight_value), 2)        AS total_freight,
    ROUND(AVG(oi.price), 2)               AS avg_item_price
FROM orders_items_dataset oi
JOIN products_dataset p   ON oi.product_id = p.product_id
LEFT JOIN product_category_name_translation t
    ON p.product_category_name = t.product_category_name
GROUP BY category_english
ORDER BY total_revenue DESC
LIMIT 10;

-- Q3. MONTHLY REVENUE TRENDS
SELECT
    DATE_TRUNC('month', o.order_purchase_timestamp)::DATE   AS order_month,
    COUNT(DISTINCT o.order_id)                              AS total_orders,
    ROUND(SUM(op.payment_value), 2)                         AS monthly_revenue,
    ROUND(AVG(op.payment_value), 2)                         AS avg_order_value
FROM orders_dataset o
JOIN order_payments_dataset op ON o.order_id = op.order_id
WHERE o.order_status != 'canceled'
GROUP BY order_month
ORDER BY order_month;

-- Q4. REVENUE BREAKDOWN BY PAYMENT TYPE
SELECT
    payment_type,
    COUNT(*)                                            AS transaction_count,
    ROUND(SUM(payment_value), 2)                        AS total_value,
    ROUND(AVG(payment_value), 2)                        AS avg_value,
    ROUND(AVG(payment_installments), 1)                 AS avg_installments,
    ROUND(SUM(payment_value) * 100.0
        / SUM(SUM(payment_value)) OVER(), 2)            AS pct_of_revenue
FROM order_payments_dataset
GROUP BY payment_type
ORDER BY total_value DESC;

-- Q5. TOP 10 SELLERS BY REVENUE AND THEIR AVERAGE REVIEW SCORE
SELECT
    oi.seller_id,
    s.seller_city,
    s.seller_state,
    COUNT(DISTINCT oi.order_id)                AS total_orders,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_gmv,
    ROUND(AVG(r.review_score), 2)              AS avg_review_score
FROM orders_items_dataset oi
JOIN sellers_dataset s     ON oi.seller_id = s.seller_id
LEFT JOIN order_reviews_dataset r ON oi.order_id = r.order_id
GROUP BY oi.seller_id, s.seller_city, s.seller_state
ORDER BY total_gmv DESC
LIMIT 10;
