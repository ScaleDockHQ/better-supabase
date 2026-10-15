import { describe, expect, it } from "vitest";

import type { SubjectsConfig } from "../../../src/config/index.ts";

import { renderModules } from "../../../src/sql/render.ts";

const SUBJECTS: SubjectsConfig = {
  deal: {
    table: "public.deals",
    permissions: { write: "deals.update" },
    rank: { column: "rank", group: "stage" },
  },
  note: { table: "public.notes", tenant: false, rank: { column: "sort_key" } },
  task: { table: "public.tasks" },
};

const sqlOf = (modules: readonly string[]): string =>
  renderModules(modules, { subjects: SUBJECTS })
    .filter((file) => file.module === "rank")
    .map((file) => file.contents)
    .join("\n");

describe("rank module", () => {
  it("installs subjects and access with it", () => {
    const modules = new Set(
      renderModules(["rank"], { subjects: SUBJECTS }).map(
        (file) => file.module,
      ),
    );
    expect(modules).toContain("subjects");
    expect(modules).toContain("access");
  });

  it("moves ranked subjects as the caller, after can_subject", () => {
    const sql = sqlOf(["rank"]);
    expect(sql).toMatch(
      /"move"\([^)]*\)\nreturns text\nlanguage plpgsql\nsecurity invoker/,
    );
    expect(sql).toContain(
      `if not "better_supabase"."can_subject"(move.subject_type, move.subject_id, 'write') then`,
    );
    expect(sql).toContain(
      `update "public"."deals" s set "rank" = v_key, "stage" = (jsonb_populate_record(null::"public"."deals", jsonb_build_object('stage', v_group)))."stage"`,
    );
    expect(sql).toContain(`update "public"."notes" s set "sort_key" = v_key\n`);
    expect(sql).toContain("hint = 'RANK_NO_GROUP'");
    expect(sql).not.toContain(`"public"."tasks"`);
  });

  it("checks that both neighbours share the tenant and the target group", () => {
    const sql = sqlOf(["rank"]);
    expect(sql).toContain("v_group := coalesce(move.to_group, v_group);");
    expect(sql).toContain(
      "if v_other_tenant is distinct from v_tenant or v_other_group is distinct from v_group then",
    );
    expect(sql).toContain("hint = 'RANK_CONFLICT'");
  });

  it("enqueues a rebalance only with the jobs module", () => {
    expect(sqlOf(["rank"])).not.toContain("rank.rebalance");
    const sql = sqlOf(["rank", "jobs"]);
    expect(sql).toContain("if length(v_key) > 24 then");
    expect(sql).toContain("queue => 'rank.rebalance'");
  });

  it("rebalances per tenant and group as the service role", () => {
    const sql = sqlOf(["rank"]);
    expect(sql).toContain(
      `row_number() over (partition by s."stage" order by s."rank" collate "C", s."id") as nth`,
    );
    expect(sql).toContain(
      `where s."organization_id"::text = rebalance_ranks.tenant`,
    );
    expect(sql).toContain(
      `grant execute on function "better_supabase"."rebalance_ranks"(text, text, text) to service_role;`,
    );
  });

  it("renders only the unknown-subject branch without ranked subjects", () => {
    const sql = renderModules(["rank"])
      .filter((file) => file.module === "rank")
      .map((file) => file.contents)
      .join("\n");
    expect(sql).toContain("hint = 'RANK_SUBJECT_UNKNOWN'");
    expect(sql).not.toContain("case move.subject_type");
  });
});
