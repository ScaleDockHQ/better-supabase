import { describe, expect, it } from "vitest";

import { renderModules } from "../../../src/sql/render.ts";

const SUBJECTS: Record<string, unknown> = {
  deal: { table: "public.deals", idType: "uuid", deletedAt: "archived_at" },
  lead: { table: "public.leads", permissions: { read: "leads.read" } },
};

const sqlOf = (
  module: string,
  options: Record<string, unknown> = {},
  subjects = SUBJECTS,
): string =>
  renderModules([module, "outbox"], {
    subjects,
    modules: { [module]: { options } },
    // SAFETY: the subject entries are partial configs the renderer fills in.
  } as never)
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("segments module", () => {
  it("evaluates each registered subject type over its live rows", () => {
    const sql = sqlOf("segments");
    expect(sql).toContain('function "better_supabase"."evaluate_segment"(');
    expect(sql).toContain('from "public"."deals" s');
    expect(sql).toContain('s."archived_at" is null');
    expect(sql).toContain("limit 10001");
    expect(sql).toContain("'leads.read'");
    expect(sql).toContain("('deal', 'lead')");
  });

  it("caps members with maxMembers and rejects a bad cap", () => {
    expect(sqlOf("segments", { maxMembers: 50 })).toContain("limit 51");
    expect(() => sqlOf("segments", { maxMembers: 0 })).toThrow(
      /positive integer/,
    );
  });

  it("renders without subjects or subject permissions", () => {
    const none = sqlOf("segments", {}, {});
    expect(none).toContain("(null)");
    expect(none).toContain("SEGMENT_SUBJECT_UNKNOWN");
    expect(none).not.toContain('from "public".');
    const open = sqlOf("segments", {}, { deal: { table: "public.deals" } });
    expect(open).not.toContain("'leads.read'");
  });
});

describe("assignment module", () => {
  it("assigns by round robin or weight within a territory", () => {
    const sql = sqlOf("assignment");
    expect(sql).toContain('function "better_supabase"."assign_subject"(');
    expect(sql).toContain("'weighted'");
    expect(sql).toContain('"better_supabase"."rule_matches"(');
    expect(sql).toContain("subject.assigned");
  });
});
