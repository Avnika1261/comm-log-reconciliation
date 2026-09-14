WITH RECURSIVE
root_map AS (
    SELECT id AS campaign_id, id AS root_id
    FROM campaign
    WHERE parent_id IS NULL
    UNION ALL
    SELECT c.id, rm.root_id
    FROM campaign c
    JOIN root_map rm ON c.parent_id = rm.campaign_id
)
SELECT COUNT(DISTINCT cl.customer_id) AS target_base
FROM communication_log cl
JOIN campaign c ON c.id = cl.communication_id
WHERE cl.delivery_status = 900
  AND c.creation_status = 'approved';
