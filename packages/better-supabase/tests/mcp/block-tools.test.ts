import { toStandardJsonSchema } from "@valibot/to-json-schema";
import * as v from "valibot";
import { describe, expect, it } from "vitest";

import { createSupabase } from "../../src/core/define.ts";
import { createMcp, defineTool } from "../../src/mcp/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const signer = await createTestSigner();

const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};

const betterSupabase = createSupabase(schema);

const base = {
  env,
  auth: { jwks: signer.jwks },
  name: "crm",
  version: "1.0.0",
};

/** The names `tools/list` returns for a server. */
async function toolNames(mcp: {
  fetch: (request: Request) => Promise<Response>;
}): Promise<string[]> {
  const token = await signer.sign({
    sub: "11111111-1111-4111-8111-111111111111",
  });

  const response = await mcp.fetch(
    new Request("https://tools.test/mcp", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        accept: "application/json, text/event-stream",
        authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/list" }),
    }),
  );

  const body = (await response.json()) as {
    result: { tools: { name: string }[] };
  };

  return body.result.tools.map((tool) => tool.name);
}

describe("the MCP block-to-tool mapping (docs: frameworks/mcp)", () => {
  it("lists no tool for a server with no resources and no tools", async () => {
    expect(await toolNames(createMcp(betterSupabase, base))).toEqual([]);
  });

  it("maps a resource to one tool per operation, named <table>_<operation>", async () => {
    expect(
      await toolNames(
        createMcp(betterSupabase, {
          ...base,
          resources: { customers: { operations: ["list", "get", "delete"] } },
        }),
      ),
    ).toEqual(["customers_list", "customers_get", "customers_delete"]);
  });

  it("maps a custom tool to its own name and nothing else", async () => {
    expect(
      await toolNames(
        createMcp(betterSupabase, {
          ...base,
          tools: [
            defineTool({
              name: "approve_quote",
              description: "Approve a quote.",
              input: toStandardJsonSchema(v.object({ id: v.string() })),
              run: ({ id }: { id: string }) => ({ approved: id }),
            }),
          ],
        }),
      ),
    ).toEqual(["approve_quote"]);
  });
});
