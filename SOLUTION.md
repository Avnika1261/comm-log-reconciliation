# Comm-Log Send Reconciliation — Solution

**Merchant:** 501 | **Period:** October 2026 | **Final target_base:** 22

## 1. Reconciliation Bridge

| Step | Description | Result | Reason |
|---|---|---|---|
| 0 | Naive: `COUNT(*)` of every `communication_log` row, no filters | **30** | Starting point — treat every logged attempt as "a send" |
| 1 | Restrict to `delivery_status = 900` (delivered) | **26** | A failed attempt (`1100`) never actually reached the customer — shouldn't count as "qualifying" |
| 2 | Exclude sends belonging to campaigns still `approval_awaiting` (campaign 9004) | **22** | A campaign isn't in official reporting until its creation/approval workflow clears — the send pipeline ran ahead of approval, but those 4 delivered rows don't count |
| 3 | Checked: collapse retries via `parent_id` and dedupe by customer **per chain** (not globally) | **22** (unchanged) | Doesn't move the number here, but is necessary for correctness — see note below |

**Final = 22** ✓ matches Finance's number.

### Why step 3 still matters despite no numeric change

In this dataset, once a customer is delivered within a retry chain, they're never retried again — so each customer only ever has *one* delivered row per chain, and a plain row-count already happens to equal the deduped count.

However, this isn't safe to assume blindly. A naive `COUNT(DISTINCT customer_id)` taken **globally** (ignoring chain boundaries) gives **21**, not 22 — because it wrongly collapses standalone campaign 9101's legitimately re-targeted customer (`C20`, sent twice on purpose) into the same dedup pool as everything else. The fix: scope dedup **per retry chain** (via a recursive walk up `parent_id`), and explicitly exempt true standalone campaigns (no parent, no children) from dedup entirely.

## 2. Final SQL Query

See `query.sql` (same folder). Verified against `comm_log.db`:

```
target_base = 22
```

Per-root breakdown:
| Root campaign | Type | Customers counted |
|---|---|---|
| 9001 (→9002→9003) | Retry chain | 10 |
| 9101 | Standalone | 7 |
| 9201 (→9202) | Retry chain | 5 |
| **Total** | | **22** |

## 3. What surprised me

The eligibility gate (campaign 9004, `approval_awaiting`) is the loudest trap in the dataset — its send pipeline had already run and delivered to 4 customers, which makes it look identical to a legitimate delivered chain until you check `creation_status`. Subtler: standalone campaign 9101 has one customer (`C20`) sent twice with no `parent_id` involved at all — it's tempting to reflexively `DISTINCT` every customer count as "good practice," but that's exactly the wrong move here, and it's what silently produces 21 instead of 22. The dedup rule needed to be conditional on chain membership, not a blanket default.
