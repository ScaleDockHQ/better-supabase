import { describe, expectTypeOf, it } from "vitest";

import type { ToolDecision, ToolRef } from "./index.ts";

import { defineSupabase } from "../core/define.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { createMcp, defineTool } from "./index.ts";

const sb = defineSupabase(schema);

describe("mcp authorization hooks", () => {
  it("carries opaque meta to the hooks", () => {
    expectTypeOf<ToolRef["meta"]>().toEqualTypeOf<unknown>();

    createMcp(sb, {
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
