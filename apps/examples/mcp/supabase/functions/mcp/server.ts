import { createMcp, type ToolRef } from "better-supabase/mcp";
import { type AuthState } from "better-supabase/server";
import * as v from "valibot";

import { sb } from "../_shared/supabase.ts";

/** Tools that need a role carry it in `meta`; table tools have none. */
const RoleMeta = v.object({ role: v.string() });
/** The custom access token hook sets `user_role` to one role or a list. */
const RoleClaims = v.object({
  user_role: v.union([v.string(), v.array(v.string())]),
});

const requiredRole = (tool: ToolRef): string | undefined => {
  const meta = v.safeParse(RoleMeta, tool.meta);
  return meta.success ? meta.output.role : undefined;
};

const hasRole = (auth: AuthState, role: string): boolean => {
  if (auth.kind !== "user") return false;
  const claims = v.safeParse(RoleClaims, auth.claims);
  if (!claims.success) return false;
  const held = claims.output.user_role;
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
    return role === undefined || hasRole(ctx.auth, role);
  },
  authorize: (ctx, tool) => {
    const role = requiredRole(tool);
    if (role === undefined) return { allowed: true };
    return hasRole(ctx.auth, role)
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
