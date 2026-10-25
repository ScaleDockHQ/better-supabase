import { describe, expect, it } from "vitest";

import type { BlockTransportRequest } from "../../src/core/block-hooks.ts";

import { blockNames } from "../../src/core/block-names.ts";

async function call(
  naming: Parameters<typeof blockNames>[0],
  fn: string,
  result: unknown = null,
): Promise<{ readonly fn: string; readonly result: unknown }> {
  let seen: BlockTransportRequest | undefined;

  const value = await blockNames(naming).call(
    { schema: "better_supabase", fn, args: { organization: "o1" } },
    async (request) => {
      seen = request;

      return result;
    },
  );

  return { fn: seen?.fn ?? "", result: value };
}

describe("blockNames", () => {
  it("gives rows the tenant column the config renames by its default name", async () => {
    const { result } = await call(
      { columns: { org_id: "tenant_id" } },
      "list_tasks",
      [{ id: "t1", org_id: "o1", metadata: { org_id: "kept" } }],
    );

    expect(result).toEqual([
      { id: "t1", tenant_id: "o1", metadata: { org_id: "kept" } },
    ]);
  });

  it("calls the functions by the tenant name", async () => {
    expect(
      (await call({ tenant: "workspace" }, "create_organization")).fn,
    ).toBe("create_workspace");
    expect((await call({ tenant: "workspace" }, "create_tag")).fn).toBe(
      "create_tag",
    );
  });

  it("applies the functions map by default or renamed name", async () => {
    expect(
      (await call({ functions: { create_tag: "make_tag" } }, "create_tag")).fn,
    ).toBe("make_tag");
    expect(
      (
        await call(
          { tenant: "workspace", functions: { create_workspace: "open" } },
          "create_organization",
        )
      ).fn,
    ).toBe("open");
  });

  it("gives result rows their tenant columns under the default names", async () => {
    const { result } = await call({ tenant: "workspace" }, "list_comments", [
      { id: "c1", workspace_id: "w1", data: { active_workspace_id: "w2" } },
    ]);

    expect(result).toEqual([
      {
        id: "c1",
        organization_id: "w1",
        data: { active_organization_id: "w2" },
      },
    ]);
    const kept = { workspace_id: "w1" };
    expect((await call({}, "list_comments", kept)).result).toBe(kept);
  });
});

const TASKS = {
  entities: [
    {
      from: { singular: "work_item", plural: "work_items" },
      to: { singular: "task", plural: "tasks" },
    },
    {
      from: { singular: "project", plural: "projects" },
      to: { singular: "initiative", plural: "initiatives" },
    },
  ],
} as const;

describe("blockNames with renamed entities", () => {
  async function request(
    fn: string,
    args: Readonly<Record<string, unknown>>,
    result: unknown,
  ): Promise<{
    readonly seen: BlockTransportRequest;
    readonly result: unknown;
  }> {
    const seen: BlockTransportRequest[] = [];

    const value = await blockNames(TASKS).call(
      { schema: "better_supabase", fn, args },
      async (next) => {
        seen.push(next);

        return result;
      },
    );

    return { seen: seen[0] ?? { schema: "", fn: "", args: {} }, result: value };
  }

  it("calls the renamed function with the nested keys renamed", async () => {
    const { seen } = await request(
      "update_work_items",
      {
        work_item: "w1",
        changes: [{ workItemId: "w1", field: "projectId", value: "p1" }],
        attrs: { projectId: "p1", fields: { project_code: "x" } },
      },
      null,
    );

    expect(seen).toEqual({
      schema: "better_supabase",
      fn: "update_tasks",
      args: {
        work_item: "w1",
        changes: [{ taskId: "w1", field: "initiativeId", value: "p1" }],
        attrs: { initiativeId: "p1", fields: { project_code: "x" } },
      },
    });
  });

  it("returns result keys under the default names", async () => {
    const { result } = await request("list_work_items", {}, [
      {
        initiative_id: "p1",
        accepted: [{ taskId: "w1", field: "initiativeId" }],
        metadata: { taskId: "kept" },
      },
    ]);

    expect(result).toEqual([
      {
        project_id: "p1",
        accepted: [{ workItemId: "w1", field: "projectId" }],
        metadata: { taskId: "kept" },
      },
    ]);
  });
});

describe("blockNames with a tenant column", () => {
  it("gives result rows the tenant column as tenant_id", async () => {
    const { fn, result } = await call(
      { tenantColumn: "organization_id" },
      "list_quotes",
      [{ id: "q1", organization_id: "o1", fields: { organization_id: "x" } }],
    );

    expect(fn).toBe("list_quotes");
    expect(result).toEqual([
      { id: "q1", tenant_id: "o1", fields: { organization_id: "x" } },
    ]);
  });
});
