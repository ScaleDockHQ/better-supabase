import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const schemaOf = (config: Parameters<typeof renderBlocks>[1]) =>
  renderBlocks(["workflow-sdk"], config)
    .filter((file) => file.kind === "schema" && file.module === "workflow-sdk")
    .map((file) => file.contents)
    .join("\n");

const dataOf = (config: Parameters<typeof renderBlocks>[1]) =>
  renderBlocks(["workflow-sdk"], config)
    .filter((file) => file.kind === "data" && file.module === "workflow-sdk")
    .map((file) => file.contents)
    .join("\n");

describe("workflow-sdk module", () => {
  it("installs after jobs and access", () => {
    const names = renderBlocks(["workflow-sdk"], {}).map((file) => file.module);

    expect(names.indexOf("queue")).toBeLessThan(names.indexOf("workflow-sdk"));
    expect(names.indexOf("permissions")).toBeLessThan(
      names.indexOf("workflow-sdk"),
    );
  });

  it("keeps a run's tenant only when its actor may run workflows there", () => {
    const sql = schemaOf({});

    const check = sql.indexOf(
      "not coalesce(better_supabase.can_user(v_actor, 'tenant', v_tenant, 'workflows.run'), false)",
    );

    expect(check).toBeGreaterThan(-1);
    expect(sql.indexOf("v_tenant := null;", check)).toBeGreaterThan(check);
    expect(check).toBeLessThan(sql.indexOf('"record_workflow_run"('));
  });

  it("closes the run keys, purge and open hooks to the API roles", () => {
    const sql = schemaOf({});

    expect(sql).toContain(
      "create table if not exists workflow.workflow_run_keys",
    );

    for (const fn of [
      "workflow_claim_run_key",
      "workflow_purge_runs",
      "workflow_open_hooks",
    ]) {
      expect(sql).toMatch(
        new RegExp(
          `revoke execute on function "better_supabase"\\."${fn}"\\([^)]*\\) from public, anon, authenticated`,
          "u",
        ),
      );
    }
  });

  it("schedules the purge only with a retention", () => {
    expect(dataOf({})).not.toContain("better-supabase-workflow-purge");
    expect(
      dataOf({
        modules: { "workflow-sdk": { options: { retention: "14 days" } } },
      }),
    ).toContain("workflow_purge_runs\"(interval ''14 days'')");
    expect(() =>
      dataOf({
        modules: { "workflow-sdk": { options: { retention: "2 weeks" } } },
      }),
    ).toThrow(/options\.retention/);
  });

  it("rejects a jobs schema, since the jobs functions live in better_supabase", () => {
    expect(() =>
      schemaOf({ modules: { queue: { schema: "queue_app" } } }),
    ).toThrow(/blocks\.queue\.schema/);
  });
});
