-- Executable audit trail for the reconciliation documented in README.md.

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
final_events AS (
    SELECT
        CASE
            WHEN campaigns_in_lineage > 1
                THEN 'retry:' || root_campaign_id || ':customer:' || customer_id
            ELSE 'standalone:' || campaign_id || ':log:' || log_id
        END AS reporting_event_key
    FROM reportable
)
SELECT
    0 AS step,
    'Naive in-scope send-attempt count' AS description,
    COUNT(*) AS result,
    'Each communication_log row is treated as a qualifying send.' AS reason
FROM in_scope

UNION ALL

SELECT
    1,
    'Exclude campaigns not ready for official reporting',
    COUNT(*),
    'Requires a finalized creation status and processed send workflow.'
FROM reportable

UNION ALL

SELECT
    2,
    'Deduplicate customers within retry lineages only',
    COUNT(DISTINCT reporting_event_key),
    'Retry attempts share one underlying communication; standalone repeat sends remain events.'
FROM final_events

ORDER BY step;
