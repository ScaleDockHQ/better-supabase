import { describe, expectTypeOf, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { createMcp, defineTool } from "../../src/mcp/index.ts";
import { schema } from "../fixtures/generated-camel.ts";

const betterSupabase = defineSupabase(schema);

// Structural stand-ins for permdock's `Permission`, `isPermission`, `mayUse`
// and `PermDock.can`, so the recipe on the PermDock docs page type-checks
// without installing permdock.
interface Permission {
  readonly key: string;
  readonly scope: string;
  readonly resource: string;
  readonly action: string;
  readonly meta: object;
}
interface PermDock {
  can(permission: Permission): boolean;
}
declare function isPermission(value: unknown): value is Permission;
declare function mayUse(dock: PermDock, permission: Permission): boolean;
declare function dockFor(ctx: unknown): Promise<PermDock>;
declare const exportCustomers: Permission;

describe("createMcp with PermDock permissions", () => {
  it("narrows meta with isPermission before can and mayUse", () => {
    createMcp(betterSupabase, {
      name: "crm",
      version: "1.0.0",
      tools: [
        defineTool({
          name: "export_customers",
          description: "Export the customers.",
          meta: exportCustomers,
          run: () => null,
        }),
      ],
      authorize: async (ctx, tool) => {
        if (!isPermission(tool.meta)) return { allowed: true };
        expectTypeOf(tool.meta).toEqualTypeOf<Permission>();
        return (await dockFor(ctx)).can(tool.meta)
          ? { allowed: true }
          : { allowed: false, reason: "PermDock denied this tool" };
      },
      visible: async (ctx, tool) =>
        !isPermission(tool.meta) || mayUse(await dockFor(ctx), tool.meta),
    });
  });

  it("rejects passing meta to mayUse without narrowing", () => {
    createMcp(betterSupabase, {
      name: "crm",
      version: "1.0.0",
      visible: async (ctx, tool) =>
        // @ts-expect-error meta is unknown until isPermission narrows it
        mayUse(await dockFor(ctx), tool.meta),
    });
  });
});
