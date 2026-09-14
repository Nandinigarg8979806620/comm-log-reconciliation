# Comm-Log Send Reconciliation

This repository reconciles Finance's `target_base` for merchant `501`, October 2026, across Diwali campaigns.

**Result: 22 qualifying sends.**

## Reproduce

1. Download `comm_log.db` from the assignment's supporting-data folder.
2. Put it at `data/comm_log.db` (the database is deliberately ignored by Git so the repository contains only the analysis).
3. Run the SQL in `sql/reconciliation.sql` against SQLite. It returns a single row with `target_base = 22`.
4. Run `sql/reconciliation_bridge.sql` to reproduce the audit trail below.

If the SQLite command-line client is available:

```sh
sqlite3 data/comm_log.db < sql/reconciliation.sql
sqlite3 data/comm_log.db < sql/reconciliation_bridge.sql
```

## Reconciliation bridge

| Step | Description | Result | Reason |
|---:|---|---:|---|
| 0 | Count all October 2026 Diwali campaign-log rows for merchant 501 | 30 | This is the straightforward, event-level starting point: each log row is one send attempt. |
| 1 | Keep only reportable campaigns | 26 | Four rows belong to campaign `9004`, which is still `approval_awaiting`. Official reporting requires a finalized creation status and `processing_status = 'processed'`. |
| 2 | Collapse repeated customers only within a retry chain | 22 | `C2`, `C3`, and `D1` appear in multiple attempts of the same retry lineage. Each is one reached customer for that underlying communication. The duplicate `C20` rows remain because campaign `9101` is standalone; the dictionary explicitly says repeated standalone sends are separate events. |

## Method

The query builds a recursive campaign-to-root mapping from `campaign.parent_id`. For each eligible log row it determines whether the root has more than one campaign:

- A retry lineage is counted once per `(root_campaign_id, customer_id)`.
- A standalone campaign is counted at log-row grain, via `(campaign_id, communication_log.id)`.

This conditional grain is important: using `COUNT(DISTINCT customer_id)` across every campaign would incorrectly remove legitimate repeated events from standalone campaign `9101`.

## A data detail that stood out

The useful distinction is not delivery success versus failure: failures still identify customers who were targeted, and Finance asks for customers reached within an underlying communication. The surprising part was that duplicate customers have two different meanings in the same table. `C2`, `C3`, and `D1` are duplicate *attempts* in retry chains and must collapse, whereas `C20` was re-sent in a standalone campaign and must remain twice. Also, campaign `9004` already has send-log rows despite awaiting approval, so log presence alone is not evidence that a campaign belongs in reported totals.

## Files

- `sql/reconciliation.sql` - final query; returns the reported number.
- `sql/reconciliation_bridge.sql` - executable version of the three-step bridge.
