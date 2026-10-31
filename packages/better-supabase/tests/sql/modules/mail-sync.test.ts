import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const sqlOf = (
  options: Record<string, unknown> = {},
  extra: readonly string[] = [],
): string =>
  renderBlocks(["mail-sync", ...extra], {
    subjects: { deal: { table: "public.deals" } },
    modules: { "mail-sync": { options } },
  })
    .filter((file) => file.module === "mail-sync")
    .map((file) => file.contents)
    .join("\n");

describe("mail-sync module", () => {
  it("stores, reads and syncs mail without parties or engagements", () => {
    const sql = sqlOf();
    expect(sql).toContain('function "better_supabase"."ingest_mail"(');
    expect(sql).toContain('function "better_supabase"."record_sent_mail"(');
    expect(sql).not.toContain("match_mail_thread");
    expect(sql).not.toContain("log_mail_thread");
    expect(sql).not.toContain('"activity_id" uuid references');
    expect(sql).toContain("credential_ref must carry the tenant");
  });

  it("matches parties by email and by domain", () => {
    const sql = sqlOf({}, ["contacts"]);
    expect(sql).toContain('function "better_supabase"."match_mail_thread"(');
    expect(sql).toContain("'person', p.\"id\"::text");
    expect(sql).toContain("split_part(x, '@', 2)");
    expect(sqlOf({ matchDomains: false }, ["contacts"])).not.toContain(
      "split_part(x, '@', 2)",
    );
  });

  it("logs threads as engagements of the configured type", () => {
    const sql = sqlOf({}, ["activities"]);
    expect(sql).toContain('function "better_supabase"."log_mail_thread"(');
    expect(sql).toContain("'type', 'email'");
    expect(sql).toMatch(/activity_id" uuid references .*activities/);
    expect(sqlOf({ engagementType: "mail" }, ["activities"])).toContain(
      "'type', 'mail'",
    );
    expect(() => sqlOf({ engagementType: "Mail" })).toThrow(
      /lowercase engagement type/,
    );
  });
});
