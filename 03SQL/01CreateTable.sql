DROP TABLE IF EXISTS order_reviews_dataset               CASCADE;
DROP TABLE IF EXISTS order_payments_dataset               CASCADE;
DROP TABLE IF EXISTS orders_items_dataset                 CASCADE;
DROP TABLE IF EXISTS orders_dataset                       CASCADE;
DROP TABLE IF EXISTS products_dataset                     CASCADE;
DROP TABLE IF EXISTS product_category_name_translation    CASCADE;
DROP TABLE IF EXISTS sellers_dataset                      CASCADE;
DROP TABLE IF EXISTS customers_dataset                    CASCADE;
DROP TABLE IF EXISTS geolocation_dataset                  CASCADE;

-- 1. CREATE & LOAD GEOLOCATION TABLE 
CREATE TABLE geolocation_dataset (
    geolocation_zip_code_prefix INT,
    geolocation_lat             DECIMAL(10, 8),
    geolocation_lng             DECIMAL(11, 8),
    geolocation_city            VARCHAR(100),
    geolocation_state           CHAR(2)
);

COPY geolocation_dataset
FROM 'C:\Project2\Clean Data\olist_geolocation_dataset_fixed.csv'
WITH (FORMAT csv, HEADER, NULL '');


-- 2. CREATE CUSTOMERS TABLE 
CREATE TABLE customers_dataset (
    customer_id               VARCHAR(50)  PRIMARY KEY,
    customer_unique_id        VARCHAR(50),
    customer_zip_code_prefix  INT,
    customer_city             VARCHAR(100),
    customer_state            CHAR(2)
);

COPY customers_dataset
FROM 'C:\Project2\Raw Data\olist_customers_dataset.csv'
WITH (FORMAT csv, HEADER, NULL '');

UPDATE customers_dataset c
SET customer_city = g.geolocation_city
FROM (
    SELECT geolocation_zip_code_prefix, MAX(geolocation_city) AS geolocation_city
    FROM geolocation_dataset
    GROUP BY geolocation_zip_code_prefix
) g
WHERE c.customer_zip_code_prefix = g.geolocation_zip_code_prefix;

-- 3. CREATE SELLERS TABLE 
CREATE TABLE sellers_dataset (
    seller_id               VARCHAR(50)  PRIMARY KEY,
    seller_zip_code_prefix  INT,
    seller_city             VARCHAR(100),
    seller_state            CHAR(2)
);

COPY sellers_dataset
FROM 'C:\Project2\Raw Data\olist_sellers_dataset.csv'
WITH (FORMAT csv, HEADER, NULL '');

UPDATE sellers_dataset s
SET seller_city = g.geolocation_city
FROM (
    SELECT geolocation_zip_code_prefix, MAX(geolocation_city) AS geolocation_city
    FROM geolocation_dataset
    GROUP BY geolocation_zip_code_prefix
) g
WHERE s.seller_zip_code_prefix = g.geolocation_zip_code_prefix;

-- 4. CREATE PRODUCTS TABLE 
CREATE TABLE products_dataset (
    product_id                  VARCHAR(50)  PRIMARY KEY,
    product_category_name       VARCHAR(100),
    product_name_lenght         INT,
    product_description_lenght  INT,
    product_photos_qty          INT,
    product_weight_g            INT,
    product_length_cm           INT,
    product_height_cm           INT,
    product_width_cm            INT
);

COPY products_dataset
FROM 'C:\Project2\Raw Data\olist_products_dataset.csv'
WITH (FORMAT csv, HEADER, NULL '');

-- 5. CREATE ORDERS TABLE (Via staging table)
CREATE TABLE orders_dataset (
    order_id                      VARCHAR(50) PRIMARY KEY,
    customer_id                   VARCHAR(50) NOT NULL,
    order_status                  VARCHAR(20),
    order_purchase_timestamp      TIMESTAMPTZ,
    order_approved_at             TIMESTAMPTZ,
    order_delivered_carrier_date  TIMESTAMPTZ,
    order_delivered_customer_date TIMESTAMPTZ,
    order_estimated_delivery_date TIMESTAMPTZ,
	CONSTRAINT fk_orders_customer
        FOREIGN KEY (customer_id) REFERENCES customers_dataset (customer_id)
);

COPY orders_dataset
FROM 'C:\Project2\Raw Data\olist_orders_dataset.csv'
WITH (FORMAT csv, HEADER, NULL '');

-- 6. CREATE ORDER ITEMS TABLE 
CREATE TABLE orders_items_dataset (
    order_id            VARCHAR(50)   NOT NULL,
    order_item_id       INT           NOT NULL,
    product_id          VARCHAR(50)   NOT NULL,
    seller_id           VARCHAR(50)   NOT NULL,
    shipping_limit_date TIMESTAMP,
    price               NUMERIC(10,2),
    freight_value       NUMERIC(10,2),
	PRIMARY KEY (order_id, order_item_id),
    CONSTRAINT fk_order_items_order
        FOREIGN KEY (order_id) REFERENCES orders_dataset (order_id),
    CONSTRAINT fk_order_items_product
        FOREIGN KEY (product_id) REFERENCES products_dataset (product_id),
    CONSTRAINT fk_order_items_seller
        FOREIGN KEY (seller_id) REFERENCES sellers_dataset (seller_id)
);

COPY orders_items_dataset
FROM 'C:\Project2\Raw Data\olist_order_items_dataset.csv'
WITH (FORMAT csv, HEADER, NULL '');

-- 7. CREATE ORDER PAYMENTS TABLE 
CREATE TABLE order_payments_dataset (
    order_id              VARCHAR(50)   NOT NULL,
    payment_sequential    INT           NOT NULL,
    payment_type          VARCHAR(50),
    payment_installments  NUMERIC(10,2),
    payment_value         NUMERIC(10,2),

    PRIMARY KEY (order_id, payment_sequential),
    CONSTRAINT fk_order_payments_order
        FOREIGN KEY (order_id) REFERENCES orders_dataset (order_id)
);

COPY order_payments_dataset
FROM 'C:\Project2\Raw Data\olist_order_payments_dataset.csv'
WITH (FORMAT csv, HEADER, NULL '');



-- 8. CREATE PRODUCT CATEGORY NAME TRANSLATION TABLE 
CREATE TABLE product_category_name_translation (
    product_category_name          VARCHAR(50)  PRIMARY KEY,
    product_category_name_english  VARCHAR(50)
);

COPY product_category_name_translation
FROM 'C:\Project2\Raw Data\product_category_name_translation.CSV'
WITH (FORMAT csv, HEADER, NULL '');

-- 9. CREATE ORDER REVIEWS TABLE (Via staging table)
CREATE TABLE order_reviews_dataset (
    review_id                VARCHAR(50),
    order_id                 VARCHAR(50) NOT NULL,
    review_score             INT,
    review_comment_title     TEXT,
    review_comment_message   TEXT,
    review_creation_date     TIMESTAMP,
    review_answer_timestamp  TIMESTAMP,
	CONSTRAINT fk_order_reviews_order
        FOREIGN KEY (order_id) REFERENCES orders_dataset (order_id)
);

COPY order_reviews_dataset
FROM 'C:\Project2\Raw Data\olist_order_reviews_dataset.csv'
WITH (FORMAT csv, HEADER, NULL '');

-- CREATE INDEXES FOR ANALYTICS PERFORMANCE

-- Geolocation: fast lookups for zip-code-based JOINs and city enrichment
CREATE INDEX IF NOT EXISTS idx_geo_zip           ON geolocation_dataset (geolocation_zip_code_prefix);
CREATE INDEX IF NOT EXISTS idx_geo_state         ON geolocation_dataset (geolocation_state);
-- Customers: state-level analytics and zip-code JOINs
CREATE INDEX IF NOT EXISTS idx_cust_unique_id    ON customers_dataset (customer_unique_id);
CREATE INDEX IF NOT EXISTS idx_cust_zip          ON customers_dataset (customer_zip_code_prefix);
CREATE INDEX IF NOT EXISTS idx_cust_state        ON customers_dataset (customer_state);
-- Sellers: zip-code JOINs and state-level analytics
CREATE INDEX IF NOT EXISTS idx_seller_zip        ON sellers_dataset (seller_zip_code_prefix);
CREATE INDEX IF NOT EXISTS idx_seller_state      ON sellers_dataset (seller_state);
-- Products: category-based analytics and JOINs to translation table
CREATE INDEX IF NOT EXISTS idx_prod_category     ON products_dataset (product_category_name);
-- Orders: FK column + frequently filtered date/status columns
CREATE INDEX IF NOT EXISTS idx_orders_customer   ON orders_dataset (customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_status     ON orders_dataset (order_status);
CREATE INDEX IF NOT EXISTS idx_orders_purchase   ON orders_dataset (order_purchase_timestamp);
CREATE INDEX IF NOT EXISTS idx_orders_delivered  ON orders_dataset (order_delivered_customer_date);
CREATE INDEX IF NOT EXISTS idx_orders_estimated  ON orders_dataset (order_estimated_delivery_date);
-- Order Items: FK columns (order_id is part of composite PK, already indexed)
CREATE INDEX IF NOT EXISTS idx_oi_product        ON orders_items_dataset (product_id);
CREATE INDEX IF NOT EXISTS idx_oi_seller         ON orders_items_dataset (seller_id);
CREATE INDEX IF NOT EXISTS idx_oi_shipping       ON orders_items_dataset (shipping_limit_date);
-- Order Payments: payment type for aggregation queries
CREATE INDEX IF NOT EXISTS idx_pay_type          ON order_payments_dataset (payment_type);
-- Order Reviews: FK column + review score for analytics
CREATE INDEX IF NOT EXISTS idx_rev_order         ON order_reviews_dataset (order_id);
CREATE INDEX IF NOT EXISTS idx_rev_score         ON order_reviews_dataset (review_score);
CREATE INDEX IF NOT EXISTS idx_rev_creation      ON order_reviews_dataset (review_creation_date);





