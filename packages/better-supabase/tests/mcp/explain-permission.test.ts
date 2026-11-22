import { describe, expect, it, vi } from "vitest";

import type { Permissions } from "../../src/blocks/permissions/permissions.ts";

import { AsyncResult } from "../../src/core/result.ts";
import { explainPermissionTool } from "../../src/mcp/explain-permission.ts";

const explanation = { allowed: true, roles: ["owner"], reason: "role" };

function tool(name?: string) {
  const explain = vi.fn(() => AsyncResult.ok(explanation));

  // SAFETY: the tool calls only `explain`.
  const permissions = { explain } as unknown as Permissions;

  return {
    explain,
    tool: explainPermissionTool({
      permissions,
      ...(name === undefined ? {} : { name }),
    }),
  };
}

// SAFETY: the tool reads only `ctx.auth`.
const ctxOf = (auth: unknown) => ({ auth }) as never;

const user = ctxOf({ kind: "user", user: { id: "u1" } });

describe("explainPermissionTool", () => {
  it("is a read-only tool named explain_permission by default", () => {
    expect(tool().tool.info).toMatchObject({
      name: "explain_permission",
      annotations: { readOnlyHint: true, idempotentHint: true },
    });
    expect(tool("why").tool.info.name).toBe("why");
  });

  it("explains the caller without a userId", async () => {
    const { explain, tool: t } = tool();

    await expect(t.run({ key: "tasks.write" } as never, user)).resolves.toBe(
      explanation,
    );
    expect(explain).toHaveBeenCalledWith({ userId: "u1", key: "tasks.write" });
  });

  it("explains the given member", async () => {
    const { explain, tool: t } = tool();

    await t.run({ key: "tasks.write", userId: "u2" } as never, user);
    expect(explain).toHaveBeenCalledWith({ userId: "u2", key: "tasks.write" });
  });

  it("needs a key, and a userId when the caller is not a user", () => {
    const { explain, tool: t } = tool();

    expect(() => t.run({ key: "" } as never, user)).toThrow(/needs a key/);
    expect(() => t.run(null as never, user)).toThrow(/needs a key/);
    expect(() =>
      t.run({ key: "tasks.write" } as never, ctxOf({ kind: "anonymous" })),
    ).toThrow(/needs a userId/);
    expect(explain).not.toHaveBeenCalled();
  });
});
