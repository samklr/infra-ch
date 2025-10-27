# Getting Started with ClickHouse - Complete Tutorial

This tutorial will guide you through connecting to your deployed ClickHouse cluster, creating databases and tables, inserting data, and running queries.

## Table of Contents

1. [Connection Methods](#connection-methods)
2. [Basic Database Operations](#basic-database-operations)
3. [Creating Tables](#creating-tables)
4. [Inserting Data](#inserting-data)
5. [Querying Data](#querying-data)
6. [Advanced Features](#advanced-features)
7. [Best Practices](#best-practices)
8. [Troubleshooting](#troubleshooting)

---

## Connection Methods

### Method 1: Via kubectl (Internal Access)

**Best for**: Development, debugging, quick operations

```bash
# List all ClickHouse pods
kubectl get pods -n clickhouse -l app=clickhouse

# Get the first pod name
POD=$(kubectl get pods -n clickhouse -l app=clickhouse -o jsonpath='{.items[0].metadata.name}')
echo $POD

# Connect to ClickHouse CLI
kubectl exec -it -n clickhouse $POD -- clickhouse-client

# You should see:
# ClickHouse client version 23.8.9.54
# Connecting to localhost:9000 as user default.
# Connected to ClickHouse server version 23.8.9.54
```

**Quick one-liner queries**:
```bash
# Run a single query
kubectl exec -n clickhouse $POD -- clickhouse-client -q "SELECT version()"

# Run query with formatted output
kubectl exec -n clickhouse $POD -- clickhouse-client -q "SELECT * FROM system.databases" --format=PrettyCompact
```

### Method 2: Via Load Balancer (External Access)

**Best for**: Production applications, external tools

#### Get Load Balancer Endpoint

```bash
# Get HTTP endpoint
LB_HTTP=$(kubectl get svc -n clickhouse clickhouse-http-nlb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "HTTP Endpoint: ${LB_HTTP}:8123"

# Get Native protocol endpoint
LB_NATIVE=$(kubectl get svc -n clickhouse clickhouse-native-nlb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "Native Endpoint: ${LB_NATIVE}:9000"
```

#### HTTP Interface (curl)

```bash
# Simple query
curl "http://${LB_HTTP}:8123?query=SELECT%20version()"

# Query with authentication
curl "http://${LB_HTTP}:8123?query=SELECT%20version()" \
  --user default:changeme

# Query with parameters
curl "http://${LB_HTTP}:8123" \
  --user default:changeme \
  --data-binary "SELECT * FROM system.databases FORMAT JSON"

# Insert data via HTTP
curl "http://${LB_HTTP}:8123?query=INSERT%20INTO%20mydb.mytable%20FORMAT%20CSV" \
  --user default:changeme \
  --data-binary @data.csv
```

#### Native Protocol (clickhouse-client)

**Install ClickHouse client locally**:

```bash
# macOS
brew install clickhouse

# Ubuntu/Debian
sudo apt-get install -y clickhouse-client

# CentOS/RHEL
sudo yum install -y clickhouse-client
```

**Connect**:

```bash
# Connect to cluster
clickhouse-client \
  --host $LB_NATIVE \
  --port 9000 \
  --user default \
  --password changeme

# Or with connection string
clickhouse-client \
  --host $LB_NATIVE \
  --port 9000 \
  --user admin \
  --password admin_changeme \
  --database default
```

### Method 3: Via Port Forward (Secure Tunnel)

**Best for**: Secure access from local machine, GUI tools

```bash
# Forward ports to localhost
kubectl port-forward -n clickhouse svc/clickhouse-cluster 8123:8123 9000:9000

# In another terminal, connect
clickhouse-client --host localhost --port 9000

# Or via HTTP
curl "http://localhost:8123?query=SELECT%20version()"
```

### Method 4: Using GUI Tools

#### DBeaver

1. Download DBeaver: https://dbeaver.io/download/
2. Create new connection → ClickHouse
3. Enter connection details:
   - Host: `$LB_NATIVE` (load balancer hostname)
   - Port: `9000`
   - Username: `default`
   - Password: `changeme`
   - Database: `default`
4. Test connection → Finish

#### DataGrip

1. File → New → Data Source → ClickHouse
2. Enter connection details (same as above)
3. Download drivers if prompted
4. Test connection

#### Tabix (Web-based)

```bash
# Use port-forward and access via browser
kubectl port-forward -n clickhouse svc/clickhouse-cluster 8123:8123

# Open browser to http://tabix.io/
# Enter connection: http://localhost:8123
```

---

## Basic Database Operations

### List Databases

```sql
-- Show all databases
SHOW DATABASES;

-- Query system table
SELECT
    name,
    engine,
    data_path,
    metadata_path
FROM system.databases;
```

### Create Database

```sql
-- Simple database
CREATE DATABASE IF NOT EXISTS mydb;

-- With specific engine
CREATE DATABASE analytics
ENGINE = Atomic;  -- Default engine (supports atomic operations)

-- With comment
CREATE DATABASE logs
ENGINE = Atomic
COMMENT 'Application logs database';
```

### Use Database

```sql
-- Switch to database
USE mydb;

-- Or specify in queries
SELECT * FROM mydb.mytable;
```

### Drop Database

```sql
-- Drop database (be careful!)
DROP DATABASE IF EXISTS mydb;
```

---

## Creating Tables

### Basic Table

```sql
-- Create database first
CREATE DATABASE IF NOT EXISTS tutorial;
USE tutorial;

-- Simple table with MergeTree engine
CREATE TABLE events
(
    event_id UInt64,
    event_time DateTime,
    user_id UInt32,
    event_type String,
    value Float64
) ENGINE = MergeTree()
ORDER BY (event_time, user_id);
```

**Explanation**:
- `MergeTree`: Best for most use cases, supports sorting and indexing
- `ORDER BY`: Defines primary key for sorting (determines data layout on disk)

### Table with Partitions

**Use Case**: Time-series data, better query performance, easier data management

```sql
CREATE TABLE user_events
(
    event_date Date,
    event_time DateTime,
    user_id UInt64,
    page_url String,
    session_id String,
    country_code FixedString(2)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(event_date)  -- Monthly partitions
ORDER BY (event_date, user_id);
```

**Benefits of partitioning**:
- Drop old data quickly: `ALTER TABLE user_events DROP PARTITION '202312'`
- Improved query performance when filtering by partition key
- Easier backup/restore of specific time ranges

### Table with TTL (Auto-deletion)

**Use Case**: Automatically delete old data

```sql
CREATE TABLE metrics
(
    metric_time DateTime,
    metric_name String,
    metric_value Float64,
    tags Map(String, String)
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(metric_time)
ORDER BY (metric_name, metric_time)
TTL metric_time + INTERVAL 90 DAY;  -- Delete data older than 90 days
```

### Replicated Table (Distributed Setup)

**Use Case**: Multi-node deployment with replication

```sql
CREATE TABLE replicated_events ON CLUSTER 'clickhouse-cluster'
(
    event_id UInt64,
    event_time DateTime,
    user_id UInt32,
    event_type String
) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/replicated_events', '{replica}')
PARTITION BY toYYYYMM(event_time)
ORDER BY (event_time, user_id);
```

### Distributed Table (Query Across Shards)

**Use Case**: Query data across all shards transparently

```sql
-- Create local table on each node first (see above)

-- Then create distributed table
CREATE TABLE events_distributed ON CLUSTER 'clickhouse-cluster'
AS replicated_events
ENGINE = Distributed(
    'clickhouse-cluster',      -- cluster name
    'tutorial',                -- database
    'replicated_events',       -- local table
    rand()                     -- sharding key (random distribution)
);
```

### Table with Different Data Types

```sql
CREATE TABLE comprehensive_example
(
    -- Numeric types
    id UInt64,
    small_int Int8,
    big_int Int64,
    decimal_val Decimal(18, 2),
    float_val Float64,

    -- String types
    name String,
    fixed_string FixedString(10),

    -- Date/Time types
    date_val Date,
    datetime_val DateTime,
    datetime64_val DateTime64(3),  -- With milliseconds

    -- Boolean
    is_active Bool,

    -- Array types
    tags Array(String),
    numbers Array(Int32),

    -- Map type
    metadata Map(String, String),

    -- Nullable types
    optional_field Nullable(String),

    -- JSON type (experimental)
    json_data String,  -- Store as String, parse in queries

    -- Enum
    status Enum8('pending' = 1, 'active' = 2, 'completed' = 3),

    -- IP addresses
    ip_address IPv4,

    -- UUID
    uuid UUID
) ENGINE = MergeTree()
ORDER BY (id, date_val);
```

### Materialized View (Aggregations)

**Use Case**: Pre-aggregate data for faster queries

```sql
-- Source table
CREATE TABLE raw_events
(
    event_time DateTime,
    user_id UInt32,
    revenue Float64
) ENGINE = MergeTree()
ORDER BY event_time;

-- Aggregated table
CREATE TABLE hourly_revenue
(
    hour DateTime,
    total_users AggregateFunction(uniq, UInt32),
    total_revenue AggregateFunction(sum, Float64)
) ENGINE = AggregatingMergeTree()
ORDER BY hour;

-- Materialized view (auto-updates on inserts)
CREATE MATERIALIZED VIEW hourly_revenue_mv TO hourly_revenue
AS SELECT
    toStartOfHour(event_time) AS hour,
    uniqState(user_id) AS total_users,
    sumState(revenue) AS total_revenue
FROM raw_events
GROUP BY hour;
```

### View Table Details

```sql
-- Show table structure
DESCRIBE TABLE events;

-- Show CREATE statement
SHOW CREATE TABLE events;

-- Table statistics
SELECT
    database,
    table,
    formatReadableSize(sum(bytes)) AS size,
    sum(rows) AS total_rows,
    max(modification_time) AS latest_modification
FROM system.parts
WHERE active AND table = 'events'
GROUP BY database, table;
```

---

## Inserting Data

### Insert Single Row

```sql
USE tutorial;

INSERT INTO events VALUES
    (1, '2024-01-27 10:00:00', 12345, 'click', 1.5);
```

### Insert Multiple Rows

```sql
INSERT INTO events VALUES
    (2, '2024-01-27 10:01:00', 12345, 'view', 0.0),
    (3, '2024-01-27 10:02:00', 12346, 'click', 2.3),
    (4, '2024-01-27 10:03:00', 12347, 'purchase', 99.99),
    (5, '2024-01-27 10:04:00', 12345, 'click', 1.2);
```

### Insert with Column Names

```sql
INSERT INTO events (event_id, event_time, user_id, event_type, value)
VALUES
    (6, now(), 12348, 'signup', 0.0);
```

### Insert from SELECT

```sql
-- Copy data from another table
INSERT INTO events
SELECT * FROM events WHERE event_time < now() - INTERVAL 1 DAY;

-- Insert with transformations
INSERT INTO events
SELECT
    event_id + 1000000,
    event_time + INTERVAL 1 DAY,
    user_id,
    event_type,
    value * 1.1
FROM events
WHERE event_type = 'purchase';
```

### Bulk Insert from File

#### CSV File

Create `data.csv`:
```csv
7,2024-01-27 11:00:00,12349,view,0.0
8,2024-01-27 11:01:00,12350,click,1.8
9,2024-01-27 11:02:00,12351,purchase,150.00
```

Insert:
```bash
# Via clickhouse-client
clickhouse-client \
  --host $LB_NATIVE \
  --port 9000 \
  --query "INSERT INTO tutorial.events FORMAT CSV" \
  < data.csv

# Via kubectl
cat data.csv | kubectl exec -i -n clickhouse $POD -- \
  clickhouse-client --query "INSERT INTO tutorial.events FORMAT CSV"

# Via HTTP
curl "http://${LB_HTTP}:8123?query=INSERT%20INTO%20tutorial.events%20FORMAT%20CSV" \
  --data-binary @data.csv
```

#### JSON File

Create `data.json`:
```json
{"event_id":10,"event_time":"2024-01-27 12:00:00","user_id":12352,"event_type":"view","value":0.0}
{"event_id":11,"event_time":"2024-01-27 12:01:00","user_id":12353,"event_type":"click","value":2.1}
```

Insert:
```bash
clickhouse-client --query "INSERT INTO tutorial.events FORMAT JSONEachRow" < data.json
```

#### Parquet File

```bash
clickhouse-client --query "INSERT INTO tutorial.events FORMAT Parquet" < data.parquet
```

### Insert with Distributed Tables

```sql
-- Insert into distributed table (automatically shards data)
INSERT INTO events_distributed VALUES
    (100, now(), 12354, 'click', 1.5);

-- Data is automatically distributed across shards
```

### Batch Inserts (Best Practice)

**❌ Don't do this** (slow):
```python
for row in rows:
    client.execute(f"INSERT INTO events VALUES ({row})")
```

**✅ Do this** (fast):
```python
# Batch insert (much faster)
client.execute("INSERT INTO events VALUES", rows, types_check=True)
```

**Recommendations**:
- Insert in batches of 10,000 - 100,000 rows
- Use async inserts for real-time data
- Use `FORMAT Native` for best performance

---

## Querying Data

### Basic SELECT

```sql
USE tutorial;

-- Select all
SELECT * FROM events;

-- Select specific columns
SELECT event_id, event_time, user_id FROM events;

-- Limit results
SELECT * FROM events LIMIT 10;
```

### Filtering (WHERE)

```sql
-- Simple filter
SELECT * FROM events
WHERE event_type = 'purchase';

-- Multiple conditions
SELECT * FROM events
WHERE event_type = 'click'
  AND value > 1.0
  AND event_time >= '2024-01-27';

-- IN clause
SELECT * FROM events
WHERE event_type IN ('click', 'purchase');

-- LIKE pattern matching
SELECT * FROM events
WHERE event_type LIKE '%pur%';

-- Date filtering
SELECT * FROM events
WHERE toDate(event_time) = today();

SELECT * FROM events
WHERE event_time >= now() - INTERVAL 1 HOUR;
```

### Sorting (ORDER BY)

```sql
-- Sort ascending
SELECT * FROM events
ORDER BY event_time ASC
LIMIT 10;

-- Sort descending
SELECT * FROM events
ORDER BY value DESC
LIMIT 10;

-- Multiple columns
SELECT * FROM events
ORDER BY event_type ASC, event_time DESC;
```

### Aggregations

```sql
-- Count
SELECT COUNT(*) FROM events;

-- Count distinct
SELECT uniq(user_id) AS unique_users FROM events;

-- Sum, Avg, Min, Max
SELECT
    COUNT(*) AS total_events,
    uniq(user_id) AS unique_users,
    SUM(value) AS total_value,
    AVG(value) AS avg_value,
    MIN(value) AS min_value,
    MAX(value) AS max_value
FROM events
WHERE event_type = 'purchase';
```

### GROUP BY

```sql
-- Group by single column
SELECT
    event_type,
    COUNT(*) AS count
FROM events
GROUP BY event_type;

-- Group by multiple columns
SELECT
    event_type,
    toDate(event_time) AS date,
    COUNT(*) AS count,
    uniq(user_id) AS unique_users
FROM events
GROUP BY event_type, date
ORDER BY date DESC, count DESC;

-- Group by time intervals
SELECT
    toStartOfHour(event_time) AS hour,
    COUNT(*) AS events_per_hour
FROM events
GROUP BY hour
ORDER BY hour;

-- HAVING clause (filter after aggregation)
SELECT
    user_id,
    COUNT(*) AS event_count
FROM events
GROUP BY user_id
HAVING event_count > 5
ORDER BY event_count DESC;
```

### JOIN Operations

```sql
-- Create second table
CREATE TABLE users
(
    user_id UInt32,
    username String,
    email String,
    signup_date Date
) ENGINE = MergeTree()
ORDER BY user_id;

-- Insert sample data
INSERT INTO users VALUES
    (12345, 'alice', 'alice@example.com', '2024-01-01'),
    (12346, 'bob', 'bob@example.com', '2024-01-02'),
    (12347, 'charlie', 'charlie@example.com', '2024-01-03');

-- INNER JOIN
SELECT
    e.event_id,
    e.event_time,
    u.username,
    e.event_type,
    e.value
FROM events e
INNER JOIN users u ON e.user_id = u.user_id
LIMIT 10;

-- LEFT JOIN
SELECT
    u.username,
    COUNT(e.event_id) AS event_count,
    SUM(e.value) AS total_value
FROM users u
LEFT JOIN events e ON u.user_id = e.user_id
GROUP BY u.username;
```

### Subqueries

```sql
-- Subquery in WHERE
SELECT * FROM events
WHERE user_id IN (
    SELECT user_id
    FROM events
    WHERE event_type = 'purchase'
);

-- Subquery in FROM
SELECT
    avg_value,
    COUNT(*) AS count
FROM (
    SELECT
        user_id,
        AVG(value) AS avg_value
    FROM events
    GROUP BY user_id
)
WHERE avg_value > 10;
```

### Common Table Expressions (WITH)

```sql
WITH
    purchasers AS (
        SELECT DISTINCT user_id
        FROM events
        WHERE event_type = 'purchase'
    ),
    clicks_per_user AS (
        SELECT
            user_id,
            COUNT(*) AS click_count
        FROM events
        WHERE event_type = 'click'
        GROUP BY user_id
    )
SELECT
    c.user_id,
    c.click_count
FROM clicks_per_user c
INNER JOIN purchasers p ON c.user_id = p.user_id
ORDER BY c.click_count DESC;
```

### Window Functions

```sql
-- Row number
SELECT
    event_id,
    user_id,
    event_time,
    ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY event_time) AS event_sequence
FROM events;

-- Running total
SELECT
    event_time,
    value,
    SUM(value) OVER (ORDER BY event_time) AS running_total
FROM events
WHERE event_type = 'purchase'
ORDER BY event_time;

-- Moving average
SELECT
    toDate(event_time) AS date,
    AVG(value) AS daily_avg,
    AVG(value) OVER (
        ORDER BY toDate(event_time)
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS moving_avg_7d
FROM events
WHERE event_type = 'purchase'
GROUP BY date
ORDER BY date;
```

### Time-Series Analysis

```sql
-- Events per hour
SELECT
    toStartOfHour(event_time) AS hour,
    COUNT(*) AS events
FROM events
WHERE event_time >= now() - INTERVAL 24 HOUR
GROUP BY hour
ORDER BY hour;

-- Daily active users
SELECT
    toDate(event_time) AS date,
    uniq(user_id) AS daily_active_users
FROM events
GROUP BY date
ORDER BY date;

-- Retention analysis
WITH
    first_events AS (
        SELECT
            user_id,
            MIN(toDate(event_time)) AS first_date
        FROM events
        GROUP BY user_id
    )
SELECT
    f.first_date AS cohort,
    toDate(e.event_time) - f.first_date AS days_since_first,
    uniq(e.user_id) AS retained_users
FROM events e
INNER JOIN first_events f ON e.user_id = f.user_id
GROUP BY cohort, days_since_first
ORDER BY cohort, days_since_first;
```

---

## Advanced Features

### Array Functions

```sql
-- Create table with arrays
CREATE TABLE user_tags
(
    user_id UInt32,
    tags Array(String),
    scores Array(Float64)
) ENGINE = MergeTree()
ORDER BY user_id;

INSERT INTO user_tags VALUES
    (1, ['sports', 'tech', 'music'], [0.8, 0.9, 0.7]),
    (2, ['food', 'travel'], [0.6, 0.85]),
    (3, ['tech', 'gaming', 'movies'], [0.95, 0.7, 0.8]);

-- Array functions
SELECT
    user_id,
    tags,
    length(tags) AS tag_count,
    has(tags, 'tech') AS has_tech,
    arrayElement(tags, 1) AS first_tag,
    arrayMax(scores) AS max_score,
    arrayAvg(scores) AS avg_score
FROM user_tags;

-- Array join (expand array to rows)
SELECT
    user_id,
    tag
FROM user_tags
ARRAY JOIN tags AS tag;
```

### JSON Parsing

```sql
-- Store JSON as String
CREATE TABLE json_events
(
    event_id UInt64,
    event_data String  -- JSON stored as string
) ENGINE = MergeTree()
ORDER BY event_id;

INSERT INTO json_events VALUES
    (1, '{"user":"alice","action":"login","timestamp":"2024-01-27T10:00:00"}'),
    (2, '{"user":"bob","action":"purchase","amount":99.99}');

-- Parse JSON in queries
SELECT
    event_id,
    JSONExtractString(event_data, 'user') AS user,
    JSONExtractString(event_data, 'action') AS action,
    JSONExtract(event_data, 'amount', 'Float64') AS amount
FROM json_events;
```

### Full-Text Search

```sql
-- Using tokenbf_v1 index
CREATE TABLE articles
(
    id UInt64,
    title String,
    content String,
    INDEX content_idx content TYPE tokenbf_v1(32768, 3, 0) GRANULARITY 1
) ENGINE = MergeTree()
ORDER BY id;

-- Search
SELECT * FROM articles
WHERE hasToken(content, 'clickhouse');
```

### Probabilistic Data Structures

```sql
-- HyperLogLog for cardinality estimation
SELECT uniq(user_id) FROM events;  -- Exact count
SELECT uniqHLL12(user_id) FROM events;  -- Approximate (faster)

-- Sampling
SELECT * FROM events SAMPLE 0.1;  -- 10% sample
```

---

## Best Practices

### 1. Choose the Right Engine

```sql
-- MergeTree: General purpose, most common
CREATE TABLE general_data (...) ENGINE = MergeTree() ORDER BY ...;

-- ReplacingMergeTree: Deduplicate rows
CREATE TABLE unique_data (...) ENGINE = ReplacingMergeTree() ORDER BY ...;

-- SummingMergeTree: Pre-aggregate numeric columns
CREATE TABLE metrics (...) ENGINE = SummingMergeTree() ORDER BY ...;

-- AggregatingMergeTree: Pre-aggregate with any aggregate function
CREATE TABLE agg_data (...) ENGINE = AggregatingMergeTree() ORDER BY ...;
```

### 2. Optimize ORDER BY

```sql
-- ✅ Good: Commonly filtered columns first
CREATE TABLE events (
    ...
) ENGINE = MergeTree()
ORDER BY (event_date, user_id, event_type);

-- ❌ Bad: High cardinality column first
CREATE TABLE events (
    ...
) ENGINE = MergeTree()
ORDER BY (event_id);  -- Unique values don't compress well
```

### 3. Use Appropriate Partitioning

```sql
-- ✅ Good: Monthly partitions for time-series
PARTITION BY toYYYYMM(event_date)

-- ✅ Good: Daily if you need to drop daily
PARTITION BY toDate(event_date)

-- ❌ Avoid: Too many partitions (hourly, per-user, etc.)
```

### 4. Batch Inserts

```sql
-- ✅ Good: Batch inserts
INSERT INTO events VALUES (1, ...), (2, ...), ..., (10000, ...);

-- ❌ Bad: Individual inserts
INSERT INTO events VALUES (1, ...);
INSERT INTO events VALUES (2, ...);
```

### 5. Use Appropriate Data Types

```sql
-- ✅ Good: Smallest type that fits
user_id UInt32  -- If IDs < 4 billion

-- ❌ Bad: Oversized types
user_id UInt64  -- If IDs will never exceed 4 billion
```

### 6. Leverage Materialized Views

```sql
-- Pre-aggregate common queries
CREATE MATERIALIZED VIEW daily_stats_mv
ENGINE = SummingMergeTree()
ORDER BY date
AS SELECT
    toDate(event_time) AS date,
    event_type,
    count() AS event_count,
    sum(value) AS total_value
FROM events
GROUP BY date, event_type;

-- Query is instant
SELECT * FROM daily_stats_mv WHERE date = today();
```

---

## Troubleshooting

### Connection Issues

```bash
# Test connectivity
kubectl exec -n clickhouse $POD -- clickhouse-client -q "SELECT 1"

# Check if service is accessible
kubectl get svc -n clickhouse

# Test from outside cluster
curl "http://${LB_HTTP}:8123/ping"
```

### Query Performance Issues

```sql
-- Explain query plan
EXPLAIN SELECT * FROM events WHERE event_time > now() - INTERVAL 1 DAY;

-- Check query statistics
SELECT
    query,
    query_duration_ms,
    read_rows,
    read_bytes
FROM system.query_log
WHERE type = 'QueryFinish'
ORDER BY query_duration_ms DESC
LIMIT 10;

-- Check table statistics
SELECT
    table,
    formatReadableSize(sum(bytes)) AS size,
    sum(rows) AS rows,
    count() AS parts
FROM system.parts
WHERE active
GROUP BY table;
```

### Storage Issues

```sql
-- Check disk usage
SELECT
    name,
    path,
    formatReadableSize(free_space) AS free,
    formatReadableSize(total_space) AS total
FROM system.disks;

-- Drop old partitions
ALTER TABLE events DROP PARTITION '202312';

-- Optimize table (merge parts)
OPTIMIZE TABLE events FINAL;
```

### Common Errors

**Error: Memory limit exceeded**
```sql
-- Increase memory limit for query
SET max_memory_usage = 20000000000;  -- 20 GB

-- Or for user
ALTER USER default SETTINGS max_memory_usage = 20000000000;
```

**Error: Too many parts**
```sql
-- Optimize table to merge parts
OPTIMIZE TABLE events;

-- Increase merge settings
ALTER TABLE events MODIFY SETTING max_parts_in_total = 1000;
```

---

## Next Steps

1. **Explore System Tables**: `SELECT * FROM system.tables`
2. **Read Official Docs**: https://clickhouse.com/docs
3. **Join Community**: ClickHouse Slack
4. **Try Advanced Features**: Dictionaries, TTL, Projections
5. **Optimize Your Queries**: Use EXPLAIN, check query_log

---

## Quick Reference Card

```sql
-- Connect
kubectl exec -it -n clickhouse $POD -- clickhouse-client

-- Create database
CREATE DATABASE mydb;

-- Create table
CREATE TABLE mydb.mytable (
    id UInt64,
    name String,
    created DateTime
) ENGINE = MergeTree()
ORDER BY id;

-- Insert data
INSERT INTO mydb.mytable VALUES (1, 'test', now());

-- Query data
SELECT * FROM mydb.mytable;

-- Aggregate
SELECT name, COUNT(*) FROM mydb.mytable GROUP BY name;

-- Check size
SELECT formatReadableSize(sum(bytes)) FROM system.parts
WHERE table = 'mytable';

-- Drop table
DROP TABLE mydb.mytable;
```

---

**Congratulations!** You now know how to work with ClickHouse. Practice with your own data and explore advanced features as you go.

For more help:
- Official Docs: https://clickhouse.com/docs
- Examples: https://clickhouse.com/docs/en/getting-started/example-datasets
- Community: https://clickhouse.com/slack
