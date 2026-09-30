import { createMcp, type ToolRef } from "better-supabase/mcp";

import { sb } from "../_shared/supabase.ts";

/** The role a tool's `meta` asks for; table tools have none. */
const requiredRole = (tool: ToolRef): string | undefined =>
  typeof tool.meta === "object" && tool.meta !== null && "role" in tool.meta
    ? String(tool.meta.role)
    : undefined;

const hasRole = (claims: Record<string, unknown>, role: string): boolean => {
  const held = claims["user_role"];
  return Array.isArray(held) ? held.includes(role) : held === role;
};

export const mcp = createMcp(sb, {
  name: "crm",
  version: "0.1.0",
  resources: {
    customers: { select: ["id", "name", "status", "organizationId"] },
    tags: { select: ["id", "name", "organizationId"] },
  },
  // RLS still decides every row. These hooks keep admin tools away from other users.
  visible: (ctx, tool) => {
    const role = requiredRole(tool);
    return (
      role === undefined ||
      (ctx.auth.kind === "user" && hasRole(ctx.auth.claims, role))
    );
  },
  authorize: (ctx, tool) => {
    const role = requiredRole(tool);
    if (role === undefined) return { allowed: true };
    return ctx.auth.kind === "user" && hasRole(ctx.auth.claims, role)
      ? { allowed: true }
      : { allowed: false, reason: `Needs the ${role} role` };
  },
}).tool({
  name: "archive_customer",
  description: "Archive a customer.",
  meta: { role: "admin" },
  inputSchema: {
    type: "object",
    properties: { id: { type: "string", format: "uuid" } },
    required: ["id"],
  },
  run: (args: { id: string }, { db }) =>
    db.customers.update(args.id, { status: "archived" }),
});
