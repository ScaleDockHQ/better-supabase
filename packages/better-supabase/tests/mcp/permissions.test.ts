import { describe, expect, it, vi } from "vitest";

import type { AuthorizationRequest } from "../../src/core/authorizer.ts";

import { defineAuthorizer } from "../../src/core/authorizer.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { createMcp } from "../../src/mcp/index.ts";
import {
  checkTool,
  contextOf,
  permittedTools,
  toolPermission,
} from "../../src/mcp/permissions.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";

const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};

const USER = "11111111-1111-4111-8111-111111111111";
const signer = await createTestSigner();

type Ref = "export" | "invite" | "purge";

const decide = (request: AuthorizationRequest<Ref>) =>
  request.action === "export"
    ? ({ outcome: "granted" } as const)
    : request.action === "invite"
      ? ({ outcome: "approval-required", approval: { id: "apr_1" } } as const)
      : ({ outcome: "denied" } as const);

describe("permittedTools", () => {
  it("batches one request per permission and keeps the tool order", async () => {
    const evaluations = vi.fn(
      async (requests: readonly AuthorizationRequest<Ref>[]) =>
        requests.map(decide),
    );

    const authorizer = defineAuthorizer<Ref>({
      name: "test",
      key: (ref) => ref,
      evaluate: decide,
      evaluations,
    });

    const shown = await permittedTools(
      authorizer,
      [
        { name: "a", permission: "export" },
        { name: "b" },
        { name: "c", permission: "purge" },
        { name: "d", permission: "export" },
      ],
      undefined,
    );

    expect(shown).toEqual([true, true, false, true]);
    expect(evaluations).toHaveBeenCalledTimes(2);
    expect(
      evaluations.mock.calls[0]![0].map((request) => request.resource),
    ).toEqual([
      { type: "mcp_tool", id: "a" },
      { type: "mcp_tool", id: "d" },
    ]);
  });

  it("hides gated tools without an authorizer or with an unknown permission", async () => {
    expect(
      await permittedTools(
        undefined,
        [{ name: "a", permission: "x" }],
        undefined,
      ),
    ).toEqual([false]);

    const throwing = defineAuthorizer({
      name: "test",
      key: () => {
        throw new Error("unknown");
      },
      evaluate: () => ({ outcome: "granted" }),
    });

    expect(
      await permittedTools(
        throwing,
        [{ name: "a", permission: "x" }],
        undefined,
      ),
    ).toEqual([false]);
  });
});

describe("toolPermission", () => {
  it("prefers the tool's mcp.tool entry over its declared permission", () => {
    const operations = {
      "mcp.tool.export": { permission: "reports.export" },
      "mcp.tool.blank": { permission: "" },
      "ai.tool.open": { permission: "ignored" },
    };

    expect(toolPermission(operations, "export", "export")).toBe(
      "reports.export",
    );
    expect(toolPermission(operations, "blank", "export")).toBe("export");
    expect(toolPermission(operations, "open", undefined)).toBeUndefined();
    expect(toolPermission(undefined, "export", "export")).toBe("export");
    const ref = { key: "export" };
    expect(toolPermission({}, "export", ref)).toBe(ref);
    expect(toolPermission(operations, "export", ref)).toBe("reports.export");
  });

  it("looks up the tool's own operation in place of mcp.tool.<name>", () => {
    const operations = {
      "invoices.void": { permission: "billing.manage" },
      "mcp.tool.void": { permission: "ignored" },
    };

    expect(toolPermission(operations, "void", "x", "invoices.void")).toBe(
      "billing.manage",
    );
    expect(toolPermission({}, "void", "x", "invoices.void")).toBe("x");
  });
});

describe("checkTool", () => {
  it("passes the arguments as the resource's properties", async () => {
    const evaluate = vi.fn(() => ({ outcome: "granted" }) as const);

    const authorizer = defineAuthorizer({
      name: "test",
      key: String,
      evaluate,
    });

    const result = await checkTool(
      authorizer,
      { info: { name: "send" }, permission: "send" },
      { to: "a" },
      {},
    );

    expect(result.ok).toBe(true);
    expect(
      (await checkTool(authorizer, { info: { name: "open" } }, {}, {})).ok,
    ).toBe(true);
    expect(evaluate).toHaveBeenCalledExactlyOnceWith(
      expect.objectContaining({
        action: "send",
        resource: {
          type: "mcp_tool",
          id: "send",
          properties: { to: "a" },
          source: "input",
        },
        subject: { type: "anon", id: "anonymous" },
        context: { scopes: [], intent: "write", operation: "tool" },
      }),
    );
  });

  it("reads a tool with readOnlyHint as a read", async () => {
    const evaluate = vi.fn(() => ({ outcome: "granted" }) as const);

    const authorizer = defineAuthorizer({
      name: "test",
      key: String,
      evaluate,
    });

    await checkTool(
      authorizer,
      {
        info: { name: "search", annotations: { readOnlyHint: true } },
        permission: "search",
      },
      {},
      {},
    );

    expect(evaluate).toHaveBeenCalledExactlyOnceWith(
      expect.objectContaining({
        context: { scopes: [], intent: "read", operation: "tool" },
      }),
    );
  });

  it("reads no context from a value without one", () => {
    expect(contextOf(undefined)).toBeUndefined();
    expect(contextOf({})).toBeUndefined();
  });
});

describe("createMcp authorizer", () => {
  const authorizer = defineAuthorizer<Ref>({
    name: "test",
    key: (ref) => ref,
    evaluate: decide,
  });

  const mcp = createMcp(defineSupabase(schema), {
    env,
    auth: { jwks: signer.jwks },
    name: "crm",
    version: "1.0.0",
    authorizer,
  })
    .tool({
      name: "export",
      description: "Exports.",
      permission: "export",
      run: () => ({ exported: true }),
    })
    .tool({
      name: "invite",
      description: "Invites.",
      permission: "invite",
      run: () => ({ invited: true }),
    })
    .tool({ name: "open", description: "Open.", run: () => "ok" });

  const send = async (method: string, params?: unknown) =>
    (await (
      await mcp.fetch(
        new Request("https://tools.test/mcp", {
          method: "POST",
          headers: {
            authorization: `Bearer ${await signer.sign({ sub: USER })}`,
            "content-type": "application/json",
          },
          body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
        }),
      )
    ).json()) as { result: Record<string, unknown> };

  it("lists only the tools the caller may call", async () => {
    const { result } = await send("tools/list");
    expect((result["tools"] as { name: string }[]).map((t) => t.name)).toEqual([
      "export",
      "open",
    ]);
  });

  it("checks the permission on a call, with the approval as a tool error", async () => {
    const exported = await send("tools/call", { name: "export" });
    expect(exported.result["structuredContent"]).toEqual({ exported: true });
    const invited = await send("tools/call", { name: "invite" });
    expect(invited.result["isError"]).toBe(true);
    expect(invited.result["structuredContent"]).toMatchObject({
      code: "APPROVAL_REQUIRED",
      approval: { id: "apr_1" },
    });
  });

  it("takes a tool's permission from the operations table first", async () => {
    const keyed: string[] = [];

    const swapped = createMcp(defineSupabase(schema), {
      env,
      auth: { jwks: signer.jwks },
      name: "crm",
      version: "1.0.0",
      authorizer: defineAuthorizer<Ref>({
        name: "test",
        key: (ref) => {
          keyed.push(ref);

          return ref;
        },
        evaluate: decide,
      }),
      operations: {
        "mcp.tool.export": { permission: "purge" },
        "mcp.tool.open": { permission: "invite" },
        "inbox.command.invite": { permission: "purge" },
      },
    })
      .tool({
        name: "export",
        description: "Exports.",
        permission: "export",
        run: () => ({ exported: true }),
      })
      .tool({
        name: "invite",
        description: "Invites.",
        permission: "invite",
        run: () => ({ invited: true }),
      })
      .tool({ name: "open", description: "Open.", run: () => "ok" });

    const response = await swapped.fetch(
      new Request("https://tools.test/mcp", {
        method: "POST",
        headers: {
          authorization: `Bearer ${await signer.sign({ sub: USER })}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/list" }),
      }),
    );

    const { result } = (await response.json()) as {
      result: { tools: { name: string }[] };
    };

    expect(result.tools.map((tool) => tool.name)).toEqual([]);
    expect(new Set(keyed)).toEqual(new Set(["purge", "invite"]));
  });

  it("warns once, naming the tools a missing authorizer hides", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});

    const bare = createMcp(defineSupabase(schema), {
      env,
      auth: { jwks: signer.jwks },
      name: "crm",
      version: "1.0.0",
    })
      .tool({
        name: "export",
        description: "Exports.",
        permission: "export",
        run: () => ({ exported: true }),
      })
      .tool({ name: "open", description: "Open.", run: () => "ok" });

    const list = async () =>
      (await (
        await bare.fetch(
          new Request("https://tools.test/mcp", {
            method: "POST",
            headers: {
              authorization: `Bearer ${await signer.sign({ sub: USER })}`,
              "content-type": "application/json",
            },
            body: JSON.stringify({
              jsonrpc: "2.0",
              id: 1,
              method: "tools/list",
            }),
          }),
        )
      ).json()) as { result: { tools: { name: string }[] } };

    expect((await list()).result.tools.map((tool) => tool.name)).toEqual([
      "open",
    ]);
    await list();

    expect(warn).toHaveBeenCalledOnce();
    expect(warn.mock.calls[0]?.[0]).toContain(
      "createMcp: export has a permission",
    );
    warn.mockRestore();
  });

  it("types permissions from the authorizer", () => {
    mcp.tool({
      name: "x",
      description: "x",
      // @ts-expect-error "delete" is not a permission of this authorizer
      permission: "delete",
      run: () => 1,
    });
  });
});
