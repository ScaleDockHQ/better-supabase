import { toStandardJsonSchema } from "@valibot/to-json-schema";
import * as v from "valibot";
import { describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import { defineListQuery } from "../../src/list/index.ts";
import {
  createMcp,
  defineTool,
  MCP_PROTOCOL_VERSION,
} from "../../src/mcp/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { problems, validatorFor } from "./validator.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const ENDPOINT = "https://tools.test/mcp";
const USER = "11111111-1111-4111-8111-111111111111";
const signer = await createTestSigner();
const sb = defineSupabase(schema);

const mcp = createMcp(sb, {
  env: {
    url: PROJECT_URL,
    publishableKey: "sb_publishable_test",
    jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
  },
  auth: { jwks: signer.jwks as never },
  name: "crm",
  version: "1.0.0",
  instructions: "Customer records.",
  resources: {
    customers: {
      list: defineListQuery(sb, "customers", {
        search: ["name"],
        sorts: { name: { name: "asc" } },
        defaultSort: "name",
      }),
    },
  },
  tools: [
    defineTool({
      name: "echo",
      description: "Echoes a message.",
      input: toStandardJsonSchema(
        v.object({ message: v.pipe(v.string(), v.minLength(1)) }),
      ),
      annotations: { readOnlyHint: true },
      run: (args: { message: string }) => ({ echoed: args.message }),
    }),
  ],
});

const LEGACY = ["2025-11-25", "2025-06-18", "2025-03-26"] as const;
const defs = (version: string) =>
  version === "2025-03-26" || version === "2025-06-18"
    ? "definitions"
    : "$defs";
const def = (version: string, name: string) =>
  validatorFor(`mcp-${version}.json`, `#/${defs(version)}/${name}`);

async function post(
  body: unknown,
  headers: Record<string, string> = {},
): Promise<Response> {
  return mcp.fetch(
    new Request(ENDPOINT, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        accept: "application/json, text/event-stream",
        authorization: `Bearer ${await signer.sign({ sub: USER })}`,
        ...headers,
      },
      body: JSON.stringify(body),
    }),
  );
}

const modern = (
  id: number,
  method: string,
  params: Record<string, unknown> = {},
  headers: Record<string, string> = {},
) =>
  post(
    {
      jsonrpc: "2.0",
      id,
      method,
      params: {
        ...params,
        _meta: {
          "io.modelcontextprotocol/protocolVersion": MCP_PROTOCOL_VERSION,
          "io.modelcontextprotocol/clientCapabilities": {},
        },
      },
    },
    {
      "mcp-protocol-version": MCP_PROTOCOL_VERSION,
      "mcp-method": method,
      ...headers,
    },
  );

describe(`MCP ${SPEC_PINS.mcp}`, () => {
  it("MCP_PROTOCOL_VERSION is SPEC_PINS.mcp", () => {
    expect(MCP_PROTOCOL_VERSION).toBe(SPEC_PINS.mcp);
  });

  it("server/discover, tools/list and tools/call results validate against the official schema", async () => {
    const discover = (await (
      await modern(1, "server/discover")
    ).json()) as Record<string, unknown>;
    expect(
      problems(def(SPEC_PINS.mcp, "JSONRPCResultResponse"), discover),
    ).toEqual([]);
    expect(
      problems(def(SPEC_PINS.mcp, "DiscoverResult"), discover["result"]),
    ).toEqual([]);

    const list = (await (await modern(2, "tools/list")).json()) as Record<
      string,
      unknown
    >;
    expect(
      problems(def(SPEC_PINS.mcp, "ListToolsResult"), list["result"]),
    ).toEqual([]);

    const call = (await (
      await modern(
        3,
        "tools/call",
        { name: "echo", arguments: { message: "hi" } },
        { "mcp-name": "echo" },
      )
    ).json()) as Record<string, unknown>;
    expect(
      problems(def(SPEC_PINS.mcp, "CallToolResult"), call["result"]),
    ).toEqual([]);
  });

  it("errors are JSON-RPC error responses with the schema's shape", async () => {
    const response = await modern(
      4,
      "tools/list",
      {},
      { "mcp-method": "tools/call" },
    );
    expect(
      problems(
        def(SPEC_PINS.mcp, "JSONRPCErrorResponse"),
        await response.json(),
      ),
    ).toEqual([]);
  });

  it.each(LEGACY)(
    "serves the %s handshake with schema-valid results",
    async (version) => {
      const init = (await (
        await post({
          jsonrpc: "2.0",
          id: 1,
          method: "initialize",
          params: {
            protocolVersion: version,
            capabilities: {},
            clientInfo: { name: "t", version: "1" },
          },
        })
      ).json()) as Record<string, unknown>;
      expect(problems(def(version, "JSONRPCResponse"), init)).toEqual([]);
      expect(
        problems(def(version, "InitializeResult"), init["result"]),
      ).toEqual([]);
      expect(init["result"]).toMatchObject({ protocolVersion: version });

      const headers = { "mcp-protocol-version": version };
      const list = (await (
        await post({ jsonrpc: "2.0", id: 2, method: "tools/list" }, headers)
      ).json()) as Record<string, unknown>;
      expect(problems(def(version, "ListToolsResult"), list["result"])).toEqual(
        [],
      );

      const call = (await (
        await post(
          {
            jsonrpc: "2.0",
            id: 3,
            method: "tools/call",
            params: { name: "echo", arguments: { message: "" } },
          },
          headers,
        )
      ).json()) as Record<string, unknown>;
      expect(problems(def(version, "CallToolResult"), call["result"])).toEqual(
        [],
      );
      expect(call["result"]).toMatchObject({ isError: true });
    },
  );

  it("every tool definition validates as a Tool and its inputSchema is an object schema", async () => {
    const list = (await (await modern(5, "tools/list")).json()) as {
      result: { tools: unknown[] };
    };
    expect(list.result.tools.length).toBeGreaterThan(1);
    for (const tool of list.result.tools) {
      expect(problems(def(SPEC_PINS.mcp, "Tool"), tool)).toEqual([]);
      expect(tool).toMatchObject({ inputSchema: { type: "object" } });
    }
  });

  it("follows Streamable HTTP: 202 for notifications, 405 for GET, 400 for unparseable JSON", async () => {
    expect(
      (await post({ jsonrpc: "2.0", method: "notifications/initialized" }))
        .status,
    ).toBe(202);
    expect((await mcp.fetch(new Request(ENDPOINT))).status).toBe(405);
    const broken = await mcp.fetch(
      new Request(ENDPOINT, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${await signer.sign({ sub: USER })}`,
        },
        body: "{nope",
      }),
    );
    expect(broken.status).toBe(400);
    expect(await broken.json()).toMatchObject({
      jsonrpc: "2.0",
      error: { code: -32700 },
    });
  });

  it("does not issue an Mcp-Session-Id (stateless server)", async () => {
    const response = await post({
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        protocolVersion: "2025-06-18",
        capabilities: {},
        clientInfo: { name: "t", version: "1" },
      },
    });
    expect(response.headers.get("mcp-session-id")).toBeNull();
  });
});
