import "server-only";
import { toStandardJsonSchema } from "@valibot/to-json-schema";
import { dbError, err } from "better-supabase";
import { defineAction } from "better-supabase/next";
import * as v from "valibot";

import type { bsb } from "@/lib/supabase/server";

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

/** The REST API's base path; the OpenAPI document and the routes share it. */
export const API_BASE_PATH = "/api/v1";

const Team = v.object({
  id: v.string(),
  name: v.string(),
  slug: v.string(),
  description: v.nullable(v.string()),
  status: v.picklist(["active", "archived"]),
  memberIds: v.array(v.string()),
});

const Role = v.object({
  id: v.string(),
  key: v.string(),
  members: v.number(),
  defaultPermissions: v.array(v.string()),
  permissions: v.array(v.string()),
  overrides: v.array(
    v.object({ permission: v.string(), granted: v.boolean() }),
  ),
});

const RoleOverride = toStandardJsonSchema(
  v.object({
    roleId: v.pipe(v.string(), v.minLength(1)),
    permission: v.pipe(v.string(), v.regex(/^[a-z_]+(\.[a-z_]+)+$/)),
    granted: v.nullable(v.boolean()),
  }),
);

/**
 * Teams and catalog roles live in block tables (`better_supabase`), which are
 * not models, so they are actions on the organization they belong to. Roles act
 * in the caller's active organization, so another id answers 404.
 */
const otherOrganization = (tenant: string | undefined, id: string) =>
  tenant === id
    ? undefined
    : err(dbError("not_found", "Not the active organization"));

/**
 * The resources `/api/v1` serves and its OpenAPI document describes: the app's
 * own tables next to the teams and permissions blocks, all as the caller
 * (RLS).
 */
export const apiResources = {
  customers: {
    operations: ["list", "get", "update", "delete"],
    select: ["id", "name", "status", "organizationId"],
    actions: {
      archive: {
        method: "POST",
        path: "/{id}/archive",
        summary: "Archive a customer",
        handler: (ctx, { id }) =>
          ctx.db.customers.update(
            String(id),
            { status: "archived" },
            { select: ["id", "status"] },
          ),
      },
    },
  },
  projects: {
    operations: ["list", "get", "create", "update", "delete"],
    select: ["id", "name", "budgetMinor", "currency", "leadId", "createdAt"],
  },
  tasks: {
    operations: ["list", "get", "create", "update", "delete"],
    select: [
      "id",
      "title",
      "status",
      "startsOn",
      "dueOn",
      "assigneeId",
      "projectId",
    ],
  },
  memberships: {
    operations: ["list"],
    select: ["organizationId", "userId", "role", "createdAt"],
  },
  organizations: {
    operations: ["list", "get"],
    select: ["id", "name", "slug"],
    actions: {
      teams: {
        method: "GET",
        path: "/{id}/teams",
        summary: "List the organization's teams",
        output: toStandardJsonSchema(v.array(Team)),
        handler: (ctx, { id }) => ctx.db.teams.list(String(id)),
      },
      roles: {
        method: "GET",
        path: "/{id}/roles",
        summary: "List the organization's roles and their permissions",
        description: "Needs `members.read`.",
        output: toStandardJsonSchema(v.array(Role)),
        handler: (ctx, { id }) =>
          otherOrganization(ctx.context.tenant, String(id)) ??
          ctx.db.permissions.roles(),
      },
      // TypeScript can't infer the input type next to an explicit `Db`.
      setRoleOverride: defineAction<Db, string, typeof RoleOverride>({
        method: "POST",
        path: "/{id}/role-overrides",
        summary: "Grant, deny or reset one permission of a role",
        description:
          "Needs `roles.manage`, a role the caller could assign and a key the caller holds. `granted: null` restores the default.",
        input: RoleOverride,
        output: toStandardJsonSchema(Role),
        handler: (ctx, { id, data }) =>
          otherOrganization(ctx.context.tenant, String(id)) ??
          ctx.db.permissions.setOverride(
            data.roleId,
            data.permission,
            data.granted,
          ),
      }),
    },
  },
} satisfies Parameters<typeof bsb.resources>[0];
