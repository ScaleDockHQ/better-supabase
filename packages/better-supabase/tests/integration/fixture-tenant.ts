import { readFileSync } from "node:fs";

const MODULES = new URL(
  "../../../../supabase/schemas/_better_supabase/",
  import.meta.url,
);

// The fixture's own renders of the modules whose helpers a suite's default
// render replaces: its memberships run over `public.memberships` and its
// permissions use the catalog model.
const FIXTURE_MODULES = [
  "900_better_supabase_004_memberships.sql",
  "900_better_supabase_019_permissions.sql",
];

const FUNCTION = /^create or replace function [\s\S]+?^\$\$;$/gmu;

function functionsOf(file: string): readonly string[] {
  return readFileSync(new URL(file, MODULES), "utf-8").match(FUNCTION) ?? [];
}

const FIXTURE_FUNCTIONS = FIXTURE_MODULES.flatMap(functionsOf);

// The fixture's member-checked `current_tenant_id()`, which its CRM policies
// read the tenant claim through. Suites that commit module SQL run this in the
// same transaction, so suites running in parallel never see the module's version.
export const FIXTURE_TENANT_SQL: string =
  FIXTURE_FUNCTIONS.find((sql) =>
    sql.startsWith(
      "create or replace function better_supabase.current_tenant_id()",
    ),
  ) ??
  (() => {
    throw new Error(
      "The fixture's memberships render has no current_tenant_id",
    );
  })();

// Every fixture helper a default render replaces (`can`, `member_can`,
// `current_tenant_id` and the rest), for a suite that commits module SQL but
// needs none of the module's helpers. Later suites check the seed's
// `public.memberships` through these.
export const FIXTURE_HELPERS_SQL: string = FIXTURE_FUNCTIONS.join("\n;\n");
