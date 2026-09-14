-- Diagnostic breakdown for Finance target_base.
-- Expected contributions: root campaign 9001 = 10, 9101 = 7, 9201 = 5.

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
eligible_log_rows AS (
    SELECT
        log.id AS log_id,
        log.communication_id AS campaign_id,
        log.customer_id,
        lineage.root_campaign_id,
        sizes.campaigns_in_lineage
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
      AND campaign.creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
      AND campaign.processing_status = 'processed'
),
scored_events AS (
    SELECT
        *,
        CASE
            WHEN campaigns_in_lineage > 1
                THEN 'retry:' || root_campaign_id || ':customer:' || customer_id
            ELSE 'standalone:' || campaign_id || ':log:' || log_id
        END AS reporting_event_key
    FROM eligible_log_rows
)
SELECT
    events.root_campaign_id,
    root_campaign.name AS root_campaign_name,
    events.campaigns_in_lineage,
    COUNT(*) AS eligible_send_attempts,
    COUNT(DISTINCT events.reporting_event_key) AS target_base_contribution,
    CASE
        WHEN events.campaigns_in_lineage > 1
            THEN 'Distinct customers within retry lineage'
        ELSE 'Every standalone log row'
    END AS counting_rule
FROM scored_events AS events
JOIN campaign AS root_campaign
  ON root_campaign.id = events.root_campaign_id
GROUP BY
    events.root_campaign_id,
    root_campaign.name,
    events.campaigns_in_lineage
ORDER BY events.root_campaign_id;

