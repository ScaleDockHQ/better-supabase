import { readdirSync, readFileSync } from "node:fs";

const FUNCTIONS = new URL(
  "../../../../supabase/schemas/better_supabase/functions/",
  import.meta.url,
);

// The fixture has no memberships: its CRM policies read the tenant claim through
// its own `current_tenant_id()`, which the module's member-checked one replaces.
// Suites that commit module SQL run this in the same transaction, so suites
// running in parallel never see the module's version.
export const FIXTURE_TENANT_SQL: string = readFileSync(
  new URL("current_tenant_id.sql", FUNCTIONS),
  "utf-8",
);

// Every fixture helper the `tenant` module replaces (`can`, `role_permissions`,
// `organization_member_role` and the rest), for a suite that commits module SQL
// but needs none of the module's helpers. Later suites check the seed's
// `public.memberships` through these.
export const FIXTURE_HELPERS_SQL: string = readdirSync(FUNCTIONS)
  .filter((name) => name.endsWith(".sql"))
  .toSorted()
  .map((name) => readFileSync(new URL(name, FUNCTIONS), "utf-8"))
  .join("\n;\n");
