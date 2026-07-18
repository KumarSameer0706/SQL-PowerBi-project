-- FILE 1: BEGINNER ANALYTICS — Fundamental Business Metrics
-- SQL concepts    : SELECT, WHERE, GROUP BY, ORDER BY, COUNT, SUM, AVG, ROUND

-- Q1. TOTAL ORDERS BY STATUS
SELECT
    order_status,
    COUNT(*)                                          AS total_orders,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct_of_total
FROM orders_dataset
GROUP BY order_status
ORDER BY total_orders DESC;

-- Q2. CUSTOMER COUNT BY STATE
SELECT
    customer_state                                     AS state,
    COUNT(DISTINCT customer_unique_id)                 AS unique_customers,
    COUNT(*)                                           AS total_customer_records
FROM customers_dataset
GROUP BY customer_state
ORDER BY unique_customers DESC;

-- Q3. TOTAL REVENUE (Gross Merchandise Value)
SELECT
    COUNT(DISTINCT op.order_id)            AS total_paid_orders,
    ROUND(SUM(op.payment_value), 2)        AS total_revenue,
    ROUND(AVG(op.payment_value), 2)        AS avg_payment_per_transaction
FROM order_payments_dataset op
JOIN orders_dataset o ON op.order_id = o.order_id
WHERE o.order_status != 'canceled';

-- Q4. TOP 10 PRODUCT CATEGORIES BY ITEMS SOLD
SELECT
    COALESCE(t.product_category_name_english, p.product_category_name, 'Unknown')
                                           AS category_english,
    COUNT(*)                               AS items_sold,
    ROUND(SUM(oi.price), 2)                AS total_item_revenue
FROM orders_items_dataset oi
JOIN products_dataset p   ON oi.product_id = p.product_id
LEFT JOIN product_category_name_translation t
    ON p.product_category_name = t.product_category_name
GROUP BY category_english
ORDER BY items_sold DESC
LIMIT 10;

-- Q5. AVERAGE REVIEW SCORE AND REVIEW VOLUME
SELECT
    review_score,
    COUNT(*)                                           AS review_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct_of_total
FROM order_reviews_dataset
GROUP BY review_score
ORDER BY review_score DESC;