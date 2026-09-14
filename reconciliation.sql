-- Finance target_base: merchant 501, October 2026, Diwali campaigns.
-- Tested against SQLite and data/comm_log.db.

WITH RECURSIVE
campaign_to_root AS (
    -- Every top-level campaign starts a lineage.
    SELECT
        id AS campaign_id,
        id AS root_campaign_id
    FROM campaign
    WHERE parent_id IS NULL

    UNION ALL

    -- Follow retry children until every campaign has its top-level lineage id.
    SELECT
        child.id AS campaign_id,
        lineage.root_campaign_id
    FROM campaign AS child
    JOIN campaign_to_root AS lineage
      ON child.parent_id = lineage.campaign_id
),
lineage_sizes AS (
    SELECT
        root_campaign_id,
        COUNT(*) AS campaigns_in_lineage
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
reporting_events AS (
    SELECT
        CASE
            -- A retry chain represents one underlying communication.
            WHEN campaigns_in_lineage > 1
                THEN 'retry:' || root_campaign_id || ':customer:' || customer_id
            -- For a standalone campaign, each log row is its own event.
            ELSE 'standalone:' || campaign_id || ':log:' || log_id
        END AS reporting_event_key
    FROM eligible_log_rows
)
SELECT COUNT(DISTINCT reporting_event_key) AS target_base
FROM reporting_events;

