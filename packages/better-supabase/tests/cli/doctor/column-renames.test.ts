import { describe, expect, it } from "vitest";

import type { ResolvedConfig } from "../../../src/config/index.ts";

import {
  shadowedBlockColumns,
  staleRenameKeys,
} from "../../../src/cli/doctor/column-renames.ts";

const config = {
  sql: { blockDefaults: { schema: "better_supabase" } },
  blocks: { invoices: { columns: { invoices: { companyId: "customer_id" } } } },
  instances: {
    billing: {
      name: "billing",
      block: "invoices",
      config: { columns: { invoices: { companyId: "buyer_id" } } },
    },
  },
} as unknown as ResolvedConfig;

describe("column rename doctor checks", () => {
  it("reports a pinned column that a block file adds again", () => {
    const findings = shadowedBlockColumns(config, [
      {
        path: "supabase/schemas/invoices.block-columns.sql",
        text: `alter table better_supabase.invoices add column if not exists company_id text;`,
      },
      {
        path: "supabase/schemas/notes.sql",
        text: "alter table public.notes add column if not exists body text;",
      },
    ]);

    expect(findings.map((finding) => finding.target)).toEqual([
      "better_supabase.invoices.company_id",
      "better_supabase.invoices.company_id",
    ]);
  });

  it("reports an old column name still read by app SQL", () => {
    const findings = staleRenameKeys([
      {
        path: "supabase/schemas/app.sql",
        text: `select better_supabase.audit('better_supabase.ai_harness_sessions', ignore => '{locked_until}');
select payload ->> 'locked_until';`,
      },
      {
        path: "supabase/migrations/old.sql",
        text: "select payload ->> 'locked_until';",
      },
    ]);

    expect(findings.length).toBeGreaterThan(0);
    expect(
      findings.some((finding) => finding.message.includes("lock_expires_at")),
    ).toBe(true);
  });
});
