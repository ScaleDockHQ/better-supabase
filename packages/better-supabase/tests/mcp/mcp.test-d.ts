import * as v from "valibot";
import { describe, expectTypeOf, it } from "vitest";

import type { AuthState } from "../../src/auth/resolve.ts";
import type { ToolDecision, ToolRef } from "../../src/mcp/index.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { createMcp, defineTool } from "../../src/mcp/index.ts";
import { schema } from "../fixtures/generated-camel.ts";

const betterSupabase = defineSupabase(schema);

describe("mcp authorization hooks", () => {
  it("carries opaque meta to the hooks", () => {
    expectTypeOf<ToolRef["meta"]>().toEqualTypeOf<unknown>();

    createMcp(betterSupabase, {
      name: "x",
      version: "1",
      tools: [
        defineTool({
          name: "export",
          description: "Exports.",
          meta: { key: "reports.export" },
          run: () => null,
        }),
      ],
      authorize: (ctx, ref, args) => {
        expectTypeOf(ref).toEqualTypeOf<ToolRef>();
        expectTypeOf(args).toEqualTypeOf<unknown>();
        expectTypeOf(ctx.request).toEqualTypeOf<Request>();
        return ctx.auth.kind === "user"
          ? { allowed: true }
          : { allowed: false, reason: "Sign in", scopes: ["openid"] };
      },
      visible: async (_ctx, ref) => ref.info.name !== "hidden",
    });
  });

  it("only accepts a decision with allowed", () => {
    expectTypeOf<{ allowed: true }>().toExtend<ToolDecision>();
    expectTypeOf<{
      allowed: false;
      scopes: string[];
    }>().toExtend<ToolDecision>();
    expectTypeOf<{ reason: string }>().not.toExtend<ToolDecision>();
  });
});

const Claims = v.object({ user_role: v.string() });
type Claims = v.InferOutput<typeof Claims>;

describe("betterSupabase.claims(schema) in MCP", () => {
  it("types the claims in the hooks and tools", () => {
    const bs = createMcp(betterSupabase.claims(Claims), {
      name: "x",
      version: "1",
      authorize: (ctx) => {
        expectTypeOf(ctx.auth).toEqualTypeOf<AuthState<Claims>>();
        return ctx.auth.kind === "user" && ctx.auth.claims.user_role === "admin"
          ? { allowed: true }
          : { allowed: false };
      },
      visible: (ctx) => {
        expectTypeOf(ctx.auth).toEqualTypeOf<AuthState<Claims>>();
        return true;
      },
    });
    bs.tool({
      name: "whoami",
      description: "The caller's role.",
      run: (_args, ctx) => {
        expectTypeOf(ctx.auth).toEqualTypeOf<AuthState<Claims>>();
        return ctx.auth.kind === "user" ? ctx.auth.claims.user_role : null;
      },
    });
    expectTypeOf(bs.endpoint).toEqualTypeOf<
      (request: Request) => Promise<Response>
    >();
  });
});
