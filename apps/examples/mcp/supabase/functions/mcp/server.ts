import { createMcp, type ToolRef } from "better-supabase/mcp";
import { hasRole } from "better-supabase/server";
import * as v from "valibot";

import { betterSupabase } from "../_shared/supabase.ts";

/** The fixture's token hook writes the role to the top-level `user_role` claim. */
const ROLE_CLAIM = "user_role";

/** Tools that need a role carry it in `meta`; table tools have none. */
const RoleMeta = v.object({ role: v.string() });

const requiredRole = (tool: ToolRef): string | undefined => {
  const meta = v.safeParse(RoleMeta, tool.meta);
  return meta.success ? meta.output.role : undefined;
};

export const bs = createMcp(betterSupabase, {
  name: "crm",
  version: "0.1.0",
  // Users without a CRM role get 403 before any tool is listed.
  requiredRoles: { roles: ["admin", "member"], claim: ROLE_CLAIM },
  resources: {
    customers: { select: ["id", "name", "status", "organizationId"] },
    tags: { select: ["id", "name", "organizationId"] },
  },
  // RLS still decides every row. These hooks keep admin tools away from members.
  visible: (ctx, tool) => {
    const role = requiredRole(tool);
    return role === undefined || hasRole(ctx.auth, [role], ROLE_CLAIM);
  },
  authorize: (ctx, tool) => {
    const role = requiredRole(tool);
    if (role === undefined || hasRole(ctx.auth, [role], ROLE_CLAIM))
      return { allowed: true };
    return { allowed: false, reason: `Needs the ${role} role` };
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
