-- OLIST E-COMMERCE — VERIFY TABLES
SELECT * FROM geolocation_dataset ;
SELECT * FROM customers_dataset ; --(Verify city names were updated properly)
SELECT * FROM sellers_dataset; --(Verify city names were updated properly)
SELECT * FROM products_dataset ;
SELECT * FROM orders_dataset;
SELECT * FROM orders_items_dataset ;
SELECT * FROM order_payments_dataset ;
SELECT * FROM product_category_name_translation ;
SELECT * FROM order_reviews_dataset ;

--View 1 — vw_dim_orders (Enriched Order Header)
CREATE OR REPLACE VIEW vw_dim_orders AS
SELECT
    o.order_id,
    o.customer_id,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_purchase_timestamp::DATE           AS order_date,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    CASE
        WHEN o.order_delivered_customer_date IS NOT NULL
         AND o.order_delivered_customer_date > o.order_estimated_delivery_date
        THEN 1 ELSE 0
    END                                         AS is_late_delivery,
    pp.payment_type                             AS primary_payment_type
FROM orders_dataset o
LEFT JOIN LATERAL (
    SELECT payment_type
    FROM order_payments_dataset p
    WHERE p.order_id = o.order_id
    ORDER BY p.payment_value DESC
    LIMIT 1
) pp ON TRUE;

--View 2 — vw_dim_product (Products with English Category Names)
CREATE OR REPLACE VIEW vw_dim_product AS
SELECT
    p.product_id,
    COALESCE(t.product_category_name_english,
             p.product_category_name,
             'unknown')                         AS product_category,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm
FROM products_dataset p
LEFT JOIN product_category_name_translation t
    ON p.product_category_name = t.product_category_name;

	
--View 3 — vw_dim_customer (Customer Dimension with RFM Segmentation)
CREATE OR REPLACE VIEW vw_dim_customer AS
WITH ref AS (
    SELECT (MAX(order_purchase_timestamp)::DATE + 1) AS ref_date
    FROM orders_dataset
),
cust_metrics AS (
    SELECT
        c.customer_unique_id,
        MAX(c.customer_city)                                  AS customer_city,
        MAX(c.customer_state)                                 AS customer_state,
        (SELECT ref_date FROM ref)
            - MAX(o.order_purchase_timestamp::DATE)           AS recency_days,
        COUNT(DISTINCT o.order_id)                            AS frequency,
        COALESCE(SUM(oi.price), 0)                            AS monetary
    FROM customers_dataset  c
    JOIN orders_dataset      o  ON c.customer_id = o.customer_id
    JOIN orders_items_dataset oi ON o.order_id   = oi.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY c.customer_unique_id
),
scored AS (
    SELECT *,
        NTILE(5) OVER (ORDER BY recency_days DESC)   AS r_score,   
        NTILE(5) OVER (ORDER BY monetary      ASC)   AS m_score,   
        CASE
            WHEN frequency >= 4 THEN 5
            WHEN frequency  = 3 THEN 4
            WHEN frequency  = 2 THEN 3
            ELSE 1                                                  
        END                                           AS f_score
    FROM cust_metrics
),
segmented AS (
    SELECT *,
        CASE
            WHEN f_score >= 3  AND r_score >= 4 AND m_score >= 4
                THEN 'Champion'
            WHEN (f_score >= 3)
              OR (r_score >= 3 AND m_score >= 4 AND f_score >= 1)
                THEN 'Loyal Customer'
            WHEN r_score >= 4
                THEN 'New Customer'
            WHEN r_score = 3
              OR (r_score <= 2 AND m_score >= 4)
                THEN 'Regular Customer'
            ELSE 'At Risk'
        END AS customer_segment
    FROM scored
)
SELECT
    c.customer_id,                    
    s.customer_unique_id,
    c.customer_zip_code_prefix,
    s.customer_city,
    s.customer_state,
    s.recency_days,
    s.frequency,
    s.monetary,
    s.r_score,
    s.f_score,
    s.m_score,
    s.customer_segment
FROM customers_dataset c
JOIN segmented s
    ON c.customer_unique_id = s.customer_unique_id;	
