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

In this dataset a customer is never put back into a retry chain once they have been delivered. This means each customer has one delivered row per chain. Therefore a simple count of the rows equals the number after deduping.

It would not be safe however to assume this without thinking. If you simply carry out a COUNT(DISTINCT customer_id) globally without taking the chain boundaries into account you get 21 than 22. That happens because the count incorrectly places the customer who was legitimately re‑targeted in standalone campaign 9101 (customer C20, who was sent to twice on purpose) into the deduplication pool as all the other customers. The solution is to apply deduplication on a per‑retry‑chain basis by means of a walk up the parent_id. Also explicitly exclude standalone campaigns (those with no parent and no children), from deduplication altogether.

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
