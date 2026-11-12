import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";

/** The `pgtap` block's manifest (ADR 0029). */
export const pgtapBlock: Block<"pgtap"> = defineBlock({
  name: "pgtap",
  sql: ["pgtap"],
  category: "database",
  entities: { pgtap: { mutability: "read-only" } },
  description:
    "tests.create_user, tests.authenticate_as and catalog checks (every_table_has_rls, policies_use, no_anon_policies, every_table_audited, partitions_have_rls) for `supabase test db`. Written to supabase/tests, never to your schema.",
});
