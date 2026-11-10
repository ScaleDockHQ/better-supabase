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

  it("reports an old column name in an audit_row_change trigger list", () => {
    const findings = staleRenameKeys([
      {
        path: "supabase/schemas/audit.sql",
        text: `create trigger bsb_audit
  after insert or update or delete on better_supabase.api_keys
  for each row
  execute function better_supabase.audit_row_change('{"ignore": ["last_used_at", "window_start"], "redact": ["secret_hash"]}');
create trigger bsb_audit after update on better_supabase.api_keys
  for each row execute function better_supabase.audit_row_change('not json');
create trigger bsb_audit after update on better_supabase.api_keys
  for each row execute function better_supabase.audit_row_change('[1]');
create trigger bsb_audit after update on better_supabase.api_keys
  for each row execute function better_supabase.audit_row_change('{"ignore": "window_start", "redact": [1, "window_start"]}');`,
      },
    ]);

    expect(findings).toEqual([
      expect.objectContaining({
        target: "supabase/schemas/audit.sql:window_start",
        message: expect.stringContaining("window_started_at"),
      }),
      expect.objectContaining({
        message: expect.stringContaining("audit redact"),
      }),
    ]);
  });

  it("skips a block it does not know, a null pin and a file upgrade owns", () => {
    const skipped = shadowedBlockColumns(
      {
        sql: { blockDefaults: { schema: "better_supabase" } },
        blocks: {
          "not-a-module": { columns: { rows: { name: "title" } } },
          invoices: {
            tables: { invoices: "invoices" },
            columns: {
              missing: { name: "title" },
              invoices: { companyId: null, id: "id" },
            },
          },
        },
        instances: {},
      } as unknown as ResolvedConfig,
      [
        {
          path: "supabase/schemas/invoices.block-columns.sql",
          text: `alter table "better_supabase"."invoices" add column if not exists "id" uuid;
alter table "better_supabase"."invoices" add column if not exists "company_id" text;`,
        },
      ],
    );

    expect(skipped).toEqual([]);

    const stale = staleRenameKeys([
      { path: "app.ts", text: "select payload ->> 'locked_until';" },
      {
        path: "supabase/schemas/900_better_supabase_core.sql",
        text: "select payload ->> 'locked_until';",
      },
      {
        path: "supabase/schemas/app.sql",
        text: `-- @bsb-block invoices
select better_supabase.audit('ai_harness_sessions', redact => '{locked_until}');
select payload ->> 'organization_id';`,
      },
    ]);

    expect(stale).toEqual([]);

    const dotted = shadowedBlockColumns(
      {
        sql: {},
        blocks: {
          invoices: {
            tables: { invoices: "public.invoices" },
            columns: { invoices: { companyId: "customer_id" } },
          },
          skipped: undefined,
        },
        instances: {},
      } as unknown as ResolvedConfig,
      [
        {
          path: "invoices.block-columns.sql",
          text: "alter table public.invoices add column if not exists company_id text;",
        },
      ],
    );

    expect(dotted.map((finding) => finding.target)).toEqual([
      "public.invoices.company_id",
    ]);

    const keys = staleRenameKeys([
      {
        path: "supabase/schemas/app.sql",
        text: `select better_supabase.audit('ai_harness_sessions', ignore => '{locked_until}');
select better_supabase.audit('public.ai_harness_sessions', redact => '{locked_until}');`,
      },
    ]);

    expect(keys.length).toBeGreaterThan(0);
  });
});
