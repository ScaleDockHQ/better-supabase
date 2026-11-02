import "server-only";
import { toStandardJsonSchema } from "@valibot/to-json-schema";
import { createMcp } from "better-supabase/mcp";
import * as v from "valibot";

import { betterSupabase } from "@/lib/supabase";

const Id = v.pipe(v.string(), v.uuid());

/**
 * The MCP server at `/api/mcp`, as the caller: MCP clients send a Supabase
 * access token and RLS decides what the tools see. The permissions block ships
 * no `Authorizer`, so `set_permission_override` gets no `permission`: its SQL
 * function checks `roles.manage` and the tool returns that refusal.
 */
export const bsb = createMcp(betterSupabase, {
  name: "example-saas",
  version: "1.0.0",
  instructions:
    "Customers, projects and tasks of the signed-in user's active organization, plus its teams and roles.",
  resources: {
    customers: {
      operations: ["list", "get"],
      select: ["id", "name", "status"],
    },
    projects: {
      operations: ["list", "get"],
      select: ["id", "name", "budgetMinor", "currency"],
    },
    tasks: {
      operations: ["list", "get", "update"],
      select: ["id", "title", "status", "dueOn", "projectId"],
    },
  },
})
  .tool({
    name: "list_teams",
    description: "List the teams of an organization with their member ids.",
    input: toStandardJsonSchema(v.object({ organizationId: Id })),
    annotations: { readOnlyHint: true },
    run: ({ organizationId }, { db }) => db.teams.list(organizationId),
  })
  .tool({
    name: "archive_customer",
    description: "Archive a customer. Needs `customers.write`.",
    input: toStandardJsonSchema(v.object({ id: Id })),
    annotations: { destructiveHint: true, idempotentHint: true },
    run: ({ id }, { db }) =>
      db.customers.update(
        id,
        { status: "archived" },
        { select: ["id", "status"] },
      ),
  })
  .tool({
    name: "set_permission_override",
    description:
      "Grant (true), deny (false) or reset (null) one permission of a role in the active organization. Needs `roles.manage`.",
    input: toStandardJsonSchema(
      v.object({
        role: v.pipe(v.string(), v.minLength(1)),
        permission: v.pipe(v.string(), v.regex(/^[a-z_]+(\.[a-z_]+)+$/)),
        granted: v.nullable(v.boolean()),
      }),
    ),
    annotations: { idempotentHint: true },
    run: ({ role, permission, granted }, { db }) =>
      db.permissions.setOverride({ role, permission, granted }),
  });
