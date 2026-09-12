WITH RECURSIVE
-- 1. Go through every campaign up, to its root ancestor (top of its retry chain)
root_map AS (
    SELECT id AS campaign_id, id AS root_id
    FROM campaign
    WHERE parent_id IS NULL
    UNION ALL
    SELECT c.id, rm.root_id
    FROM campaign c
    JOIN root_map rm ON c.parent_id = rm.campaign_id
),
-- 2. How many campaigns sit under each root? >1 means it's a real retry chain
--    exactly 1 means it's a true standalone that was never retried.
chain_size AS (
    SELECT root_id, COUNT(*) AS n_campaigns
    FROM root_map
    GROUP BY root_id
),
-- 3. Qualifying send rows only: delivered, AND belonging to a campaign that
--    has cleared both the approval gate and the processing gate
eligible_sends AS (
    SELECT cl.customer_id, rm.root_id
    FROM communication_log cl
    JOIN campaign c  ON c.id = cl.communication_id
    JOIN root_map rm ON rm.campaign_id = cl.communication_id
    WHERE cl.delivery_status = 900
      AND c.creation_status IN ('approved','aborted','resumed','stopped')  -- finalized creation states
      AND c.processing_status = 'processed'
)
-- 4. For each root: remove customers if it is part of a retry chain(n_campaigns > 1),
--    otherwise count each row as it is (standalone campaigns are never removed)
-- (tried using COUNT(DISTINCT customer_id) overall first. Got 21 which was wrong
--  because it removed the repeat customer for standalone 9101. Fixed by 
--  using DISTINCT, per chain instead see below)
SELECT SUM(root_count) AS target_base
FROM (
    SELECT
        es.root_id,
        CASE
            WHEN cs.n_campaigns > 1 THEN COUNT(DISTINCT es.customer_id)
            ELSE COUNT(*)
        END AS root_count
    FROM eligible_sends es
    JOIN chain_size cs ON cs.root_id = es.root_id
    GROUP BY es.root_id
);