import { describe, expect, it } from "vitest";

import { moduleBody } from "../../../src/sql/render.ts";
import { upgradePlan } from "../../../src/sql/upgrade.ts";

const body = (columns: Record<string, null> = {}) =>
  moduleBody("inbox", {
    modules: { inbox: { columns: { drafts: columns } } },
  })!;

describe("inbox drafts", () => {
  it("keeps one open user draft per author and ai drafts for staff", () => {
    const sql = body();

    expect(sql).toContain(
      'create table if not exists "better_supabase"."inbox_drafts" (',
    );
    expect(sql).toContain("check (\"source\" in ('user', 'ai'))");
    expect(sql).toContain("inbox_drafts_author_check");
    expect(sql).toContain(`where "source" = 'user' and "status" = 'draft';`);
    expect(sql).toContain("create policy inbox_drafts_read");
    expect(sql).toContain(`or "source" = 'ai') and`);
  });

  it("saves, suggests, sends and discards through functions", () => {
    const sql = body();

    for (const name of [
      "save_inbox_draft",
      "suggest_inbox_draft",
      "list_inbox_drafts",
      "send_inbox_draft",
      "discard_inbox_draft",
    ]) {
      expect(sql).toContain(
        `create or replace function "better_supabase"."${name}"(`,
      );
    }

    expect(sql).toContain(
      'grant execute on function "better_supabase"."suggest_inbox_draft"(uuid, jsonb, jsonb) to service_role;',
    );
    expect(sql).toContain(
      '"better_supabase"."send_inbox_message"(v_row."conversation_id"',
    );
    expect(sql).toContain("hint = 'INBOX_DRAFT_NOT_FOUND'");
    expect(sql).toContain("hint = 'INBOX_DRAFT_METADATA'");
  });

  it("drops the metadata handling without the column", () => {
    const sql = body({ metadata: null, createdAt: null });

    expect(sql).not.toContain("INBOX_DRAFT_METADATA");

    const table = sql.slice(
      sql.indexOf(
        'create table if not exists "better_supabase"."inbox_drafts"',
      ),
    );

    expect(table.slice(0, table.indexOf(");"))).not.toContain('"metadata"');
    expect(sql).toContain(
      'insert into "better_supabase"."inbox_drafts" ("tenant_id", "conversation_id", "author_id", "source", "input")',
    );
  });

  it("adds drafts in the upgrade from version 5", () => {
    const [plan] = upgradePlan([{ module: "inbox", version: 5 }]);

    expect(
      plan?.steps
        .filter((step) => step.from === 5)
        .map((step) => step.description),
    ).toEqual([expect.stringContaining("inbox_drafts")]);
  });
});
