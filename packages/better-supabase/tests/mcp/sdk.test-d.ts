import { McpServer } from "@modelcontextprotocol/server";
import { toStandardJsonSchema } from "@valibot/to-json-schema";
import * as v from "valibot";
import { describe, expectTypeOf, it } from "vitest";

import type { AuthState } from "../../src/auth/resolve.ts";

import { defineSupabase } from "../../src/core/define.ts";
import {
  createMcpAuth,
  withBetterSupabaseMcp,
} from "../../src/mcp/sdk/index.ts";
import { schema } from "../fixtures/generated-camel.ts";

const betterSupabase = defineSupabase(schema);
const auth = createMcpAuth(betterSupabase);

describe("withBetterSupabaseMcp", () => {
  it("types the arguments and the caller's repositories", () => {
    const server = withBetterSupabaseMcp(
      new McpServer({ name: "crm", version: "1.0.0" }),
      auth,
    );
    server.registerTool(
      "rename",
      {
        inputSchema: toStandardJsonSchema(
          v.object({ id: v.string(), name: v.string() }),
        ),
      },
      async (args, ctx) => {
        expectTypeOf(args).toEqualTypeOf<{ id: string; name: string }>();
        expectTypeOf(ctx.auth).toEqualTypeOf<AuthState>();
        expectTypeOf(ctx.db).toEqualTypeOf(ctx.bs.db);
        expectTypeOf(ctx.http).not.toBeAny();
        const found = await ctx.db.customers.findUnique({
          where: { id: args.id },
        });
        expectTypeOf(found.ok).toBeBoolean();
        return { content: [] };
      },
    );
    server.registerTool("ping", {}, (ctx) => {
      expectTypeOf(ctx.db.customers).toHaveProperty("findMany");
      return { content: [] };
    });
  });

  it("keeps the rest of the McpServer surface", () => {
    const server = withBetterSupabaseMcp(
      new McpServer({ name: "crm", version: "1.0.0" }),
      auth,
    );
    expectTypeOf(server).toHaveProperty("connect");
    expectTypeOf(server).not.toHaveProperty("tool");
  });
});
