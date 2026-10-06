import { readFileSync } from "node:fs";

// The fixture has no memberships: its CRM policies read the tenant claim through
// its own `current_tenant_id()`, which the block's member-checked one replaces.
// Suites that commit block SQL run this in the same transaction, so suites
// running in parallel never see the block's version.
export const FIXTURE_TENANT_SQL: string = readFileSync(
  new URL("../../../../supabase/schemas/015_shared.sql", import.meta.url),
  "utf8",
);
