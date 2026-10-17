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
