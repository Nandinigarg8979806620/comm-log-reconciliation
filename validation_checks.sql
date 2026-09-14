-- Compact, executable checks for the assignment's critical business rules.
-- All rows should return PASS when run against the supplied SQLite database.

WITH RECURSIVE
campaign_to_root AS (
    SELECT id AS campaign_id, id AS root_campaign_id
    FROM campaign
    WHERE parent_id IS NULL

    UNION ALL

    SELECT child.id, lineage.root_campaign_id
    FROM campaign AS child
    JOIN campaign_to_root AS lineage
      ON child.parent_id = lineage.campaign_id
),
lineage_sizes AS (
    SELECT root_campaign_id, COUNT(*) AS campaigns_in_lineage
    FROM campaign_to_root
    GROUP BY root_campaign_id
),
in_scope AS (
    SELECT
        log.id AS log_id,
        log.communication_id AS campaign_id,
        log.customer_id,
        lineage.root_campaign_id,
        sizes.campaigns_in_lineage,
        campaign.creation_status,
        campaign.processing_status
    FROM communication_log AS log
    JOIN campaign AS campaign
      ON campaign.id = log.communication_id
    JOIN campaign_to_root AS lineage
      ON lineage.campaign_id = campaign.id
    JOIN lineage_sizes AS sizes
      ON sizes.root_campaign_id = lineage.root_campaign_id
    WHERE log.merchant_id = 501
      AND campaign.merchant_id = 501
      AND log.communication_type = '2'
      AND log.sent_time >= '2026-10-01'
      AND log.sent_time <  '2026-11-01'
      AND campaign.name LIKE '%Diwali%'
),
reportable AS (
    SELECT *
    FROM in_scope
    WHERE creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
      AND processing_status = 'processed'
),
reporting_events AS (
    SELECT CASE
        WHEN campaigns_in_lineage > 1
            THEN 'retry:' || root_campaign_id || ':customer:' || customer_id
        ELSE 'standalone:' || campaign_id || ':log:' || log_id
    END AS reporting_event_key
    FROM reportable
),
final_target AS (
    SELECT COUNT(DISTINCT reporting_event_key) AS result
    FROM reporting_events
),
standalone_c20 AS (
    SELECT COUNT(*) AS result
    FROM reportable
    WHERE campaign_id = 9101 AND customer_id = 'C20'
),
pending_campaign_rows AS (
    SELECT COUNT(*) AS result
    FROM in_scope
    WHERE campaign_id = 9004
)
SELECT
    'Raw in-scope send attempts' AS check_name,
    30 AS expected,
    (SELECT COUNT(*) FROM in_scope) AS actual,
    CASE WHEN (SELECT COUNT(*) FROM in_scope) = 30 THEN 'PASS' ELSE 'FAIL' END AS status

UNION ALL

SELECT
    'Pending campaign 9004 is excluded from official reporting',
    4,
    (SELECT result FROM pending_campaign_rows),
    CASE WHEN (SELECT result FROM pending_campaign_rows) = 4 THEN 'PASS' ELSE 'FAIL' END

UNION ALL

SELECT
    'Reportable send attempts after lifecycle filter',
    26,
    (SELECT COUNT(*) FROM reportable),
    CASE WHEN (SELECT COUNT(*) FROM reportable) = 26 THEN 'PASS' ELSE 'FAIL' END

UNION ALL

SELECT
    'Standalone customer C20 remains two events',
    2,
    (SELECT result FROM standalone_c20),
    CASE WHEN (SELECT result FROM standalone_c20) = 2 THEN 'PASS' ELSE 'FAIL' END

UNION ALL

SELECT
    'Final Finance target_base',
    22,
    (SELECT result FROM final_target),
    CASE WHEN (SELECT result FROM final_target) = 22 THEN 'PASS' ELSE 'FAIL' END;
