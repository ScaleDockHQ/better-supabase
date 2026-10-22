import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const schemaOf = (config: Parameters<typeof renderBlocks>[1]) =>
  renderBlocks(["workflow-sdk"], config)
    .filter((file) => file.kind === "schema" && file.module === "workflow-sdk")
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
      "not coalesce(better_supabase.can_user(v_actor, 'tenant', v_tenant, 'workflow.run'), false)",
    );

    expect(check).toBeGreaterThan(-1);
    expect(sql.indexOf("v_tenant := null;", check)).toBeGreaterThan(check);
    expect(check).toBeLessThan(sql.indexOf('"record_workflow_run"('));
  });

  it("rejects a jobs schema, since the jobs functions live in better_supabase", () => {
    expect(() =>
      schemaOf({ modules: { queue: { schema: "queue_app" } } }),
    ).toThrow(/blocks\.queue\.schema/);
  });
});
