import { describe, expect, it } from "vitest";

import { renderModules } from "../../../src/sql/render.ts";

const sqlOf = (
  modules: readonly string[] = ["bulk"],
  options: Record<string, unknown> = {},
): string =>
  renderModules(modules, { modules: { bulk: { options } } })
    .filter((file) => file.module === "bulk")
    .map((file) => file.contents)
    .join("\n");

describe("bulk module", () => {
  it("knows only the actions of installed blocks", () => {
    const bare = sqlOf();
    expect(bare).toContain("array[]::text[]");
    expect(bare).not.toContain("'tags.set'");
    const full = sqlOf(["bulk", "tags", "state-machine", "relations", "trash"]);
    expect(full).toContain(
      "array['tags.set', 'stateMachine.transition', 'relations.link', 'trash.trash']",
    );
    expect(full).toContain(
      'perform "better_supabase"."trash"(bulk_row.tenant, bulk_row.subject_type, bulk_row.subject_id);',
    );
    expect(full).toContain("when 'tags.set' then");
    expect(full).toContain('perform "better_supabase"."transition"(');
  });

  it("calls an app's own actions", () => {
    const sql = sqlOf(["bulk"], {
      actions: { "tasks.archive": "app.archive_task" },
    });

    expect(sql).toContain("when 'tasks.archive' then");
    expect(sql).toContain(
      `perform "app"."archive_task"(bulk_row.tenant, bulk_row.subject_type, bulk_row.subject_id, bulk_row.args);`,
    );
  });

  it("rejects bad action options and limits", () => {
    expect(() => sqlOf(["bulk"], { actions: { "tags.set": "app.x" } })).toThrow(
      /built-in/,
    );
    expect(() => sqlOf(["bulk"], { actions: { archive: "app.x" } })).toThrow(
      /block\.method/,
    );
    expect(() =>
      sqlOf(["bulk"], { actions: { "tasks.archive": "app.x; drop" } }),
    ).toThrow(/schema\.function/);
    expect(() => sqlOf(["bulk"], { actions: [] })).toThrow(/map action names/);
    expect(() => sqlOf(["bulk"], { limit: 0 })).toThrow(/limit/);
    expect(sqlOf(["bulk"], { limit: 50 })).toContain("more than 50 rows");
  });

  it("enqueues background runs only with the jobs module", () => {
    expect(sqlOf()).toContain("BULK_NO_JOBS");
    const jobs = sqlOf(["bulk", "jobs"]);
    expect(jobs).not.toContain("BULK_NO_JOBS");
    expect(jobs).toContain("queue => 'bulk'");
  });

  it("runs background steps as the starting user and keeps them for the service role", () => {
    const sql = sqlOf();
    expect(sql).toContain("set local role authenticated;");
    expect(sql).toContain("execute format('set local role %I', v_role);");
    expect(sql).toMatch(
      /revoke execute on function "better_supabase"\."bulk_step"\(uuid, integer\) from public, anon, authenticated;/,
    );
    expect(sql).toContain('using ("created_by" = (select auth.uid()))');
  });
});
