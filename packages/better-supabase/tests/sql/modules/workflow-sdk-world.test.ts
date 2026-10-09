import { describe, expect, it } from "vitest";

import { renderModules } from "../../../src/sql/registry.ts";

const schemaOf = (config: Parameters<typeof renderModules>[1]) =>
  renderModules(["workflow-sdk-world"], config)
    .filter(
      (file) => file.kind === "schema" && file.module === "workflow-sdk-world",
    )
    .map((file) => file.contents)
    .join("\n");

describe("workflow-sdk-world module", () => {
  it("installs after jobs and access", () => {
    const names = renderModules(["workflow-sdk-world"], {}).map(
      (file) => file.module,
    );
    expect(names.indexOf("jobs")).toBeLessThan(
      names.indexOf("workflow-sdk-world"),
    );
    expect(names.indexOf("access")).toBeLessThan(
      names.indexOf("workflow-sdk-world"),
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
      schemaOf({ modules: { jobs: { schema: "queue_app" } } }),
    ).toThrow(/sql\.modules\.jobs\.schema/);
  });
});
