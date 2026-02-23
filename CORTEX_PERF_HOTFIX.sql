-- ====================================================================================
-- CORTEX PERFORMANCE HOTFIX — Drop Duplicate Indexes
-- Run this in the Supabase SQL Editor to eliminate the 3 "Duplicate Index" warnings
-- from the Performance Advisor WITHOUT wiping any data.
--
-- Root cause: UNIQUE constraints on these tables already create implicit B-tree indexes.
-- The explicit CREATE UNIQUE INDEX statements were redundant duplicates.
-- ====================================================================================

-- core.users: UNIQUE(tenant_id, email) in DDL = implicit index already exists
DROP INDEX IF EXISTS core.idx_users_tenant_email;

-- assets.registry: UNIQUE(tenant_id, tag_number) in DDL = implicit index already exists
DROP INDEX IF EXISTS assets.idx_asset_tenant_tag;

-- inventory.parts: UNIQUE(tenant_id, sku) in DDL = implicit index already exists
DROP INDEX IF EXISTS inventory.idx_parts_tenant_sku;

-- Verify: check remaining indexes on these tables
-- SELECT indexname, indexdef FROM pg_indexes
-- WHERE tablename IN ('users', 'registry', 'parts')
-- ORDER BY tablename, indexname;
