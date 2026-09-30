import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { mcp } from "@better-supabase/example-mcp/server";

import {
  ACME,
  cleanup,
  createUser,
  OTHER,
  reachable,
  type TestUser,
} from "./stack.ts";

interface RpcResponse {
  readonly result: {
    readonly tools?: readonly { readonly name: string }[];
    readonly isError?: boolean;
    readonly structuredContent?: Record<string, unknown>;
  };
}

describe.skipIf(!(await reachable()))("mcp example", () => {
  let acme: TestUser;
  let other: TestUser;
  const rows = cleanup("customers");

  beforeAll(async () => {
    [acme, other] = await Promise.all([createUser(ACME), createUser(OTHER)]);
  });
  afterAll(async () => {
    await rows.run();
    await Promise.all([acme.remove(), other.remove()]);
  });

  const rpc = async (user: TestUser, method: string, params: unknown) => {
    const response = await mcp.fetch(
      new Request("http://127.0.0.1/mcp", {
        method: "POST",
        headers: {
          authorization: `Bearer ${user.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
      }),
    );
    return ((await response.json()) as RpcResponse).result;
  };
  const tool = (user: TestUser, name: string, args: unknown) =>
    rpc(user, "tools/call", { name, arguments: args });

  it("lists a tool per operation for each exposed table", async () => {
    const { tools } = await rpc(acme, "tools/list", {});
    const names = tools!.map((entry) => entry.name);
    expect(names).toEqual(
      expect.arrayContaining([
        "customers_list",
        "customers_create",
        "tags_get",
      ]),
    );
    expect(names.some((name) => name.startsWith("notes_"))).toBe(false);
  });

  it("runs tools as the caller under RLS", async () => {
    const name = `MCP e2e ${crypto.randomUUID()}`;
    const created = await tool(acme, "customers_create", {
      name,
      organizationId: ACME,
    });
    expect(created.isError).toBeUndefined();
    const id = created.structuredContent!["id"] as string;
    rows.track(id);

    expect(await tool(acme, "customers_get", { id })).toMatchObject({
      structuredContent: { id, name },
    });
    expect(await tool(other, "customers_get", { id })).toMatchObject({
      isError: true,
      structuredContent: { kind: "not_found" },
    });
    expect(await tool(acme, "customers_delete", { id })).toMatchObject({
      structuredContent: { deleted: true },
    });
  });
});
