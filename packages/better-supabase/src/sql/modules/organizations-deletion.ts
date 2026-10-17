import type { ModuleContext } from "../context.ts";
import type { OrganizationReadNames } from "./organizations-reads.ts";

import { sqlString } from "../../core/template.ts";
import { SERVICE_CALLER, fail } from "../shared.ts";
import { OPERATIONS } from "./access-model.ts";

export interface DeletionHelpers {
  /** The `deletePlatform` override clause, or nothing when it is unset. */
  readonly platformOverride: string;
  readonly event: (organization: string, user: string) => string;
}

type DeleteMode = "hard" | "soft" | "lifecycle" | "none";

/** `blocks.organizations.options.deleteMode`. */
export function deleteMode(ctx: ModuleContext): DeleteMode {
  const mode = ctx.text("deleteMode", "hard");

  if (
    mode !== "hard" &&
    mode !== "soft" &&
    mode !== "lifecycle" &&
    mode !== "none"
  ) {
    throw new TypeError(
      `blocks.organizations.options.deleteMode must be "hard", "soft", "lifecycle" or "none", not "${mode}"`,
    );
  }

  if (mode === "lifecycle" && !ctx.installed("data-lifecycle")) {
    throw new TypeError(
      'blocks.organizations.options.deleteMode "lifecycle" schedules the deletion with request_organization_deletion, so it needs the data-lifecycle module in blocks',
    );
  }

  return mode;
}

/** `delete_organization(organization)`: requests the purge through data-lifecycle. */
function requestDeletion(ctx: ModuleContext, platformOverride: string): string {
  return `
-- Deletes an organization through data-lifecycle (blocks.organizations.options.deleteMode
-- "lifecycle"): schedules the purge after the grace period and disables it.
create or replace function ${ctx.fn("delete_organization")}(organization ${ctx.idType})
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (${SERVICE_CALLER}) and not coalesce(better_supabase.member_can(auth.uid(), organization, ${ctx.permission("delete", OPERATIONS["organizations.delete"])}), false)${platformOverride} then
    ${fail("ORGANIZATION_FORBIDDEN", "Not allowed to delete the organization")}
  end if;
  perform ${ctx.of("data-lifecycle").fn("request_organization_deletion")}(organization);
  return true;
end;
$$;
`;
}

/** `delete_organization(organization)` under `blocks.organizations.options.deleteMode`. */
export function organizationDeletion(
  ctx: ModuleContext,
  n: OrganizationReadNames,
  helpers: DeletionHelpers,
): string {
  const id = ctx.idType;
  const mode = deleteMode(ctx);

  if (mode === "none") {
    return `
-- blocks.organizations.options.deleteMode is "none": no delete function.
drop function if exists ${ctx.fn("delete_organization")}(${id});
`;
  }

  if (mode === "lifecycle") {
    return requestDeletion(ctx, helpers.platformOverride);
  }

  const soft = mode === "soft";

  if (soft && !ctx.has("organizations", "deletedAt")) {
    throw new TypeError(
      "blocks.organizations.options.deleteMode 'soft' needs the deletedAt column",
    );
  }

  const action = soft
    ? `update ${n.organization} set ${ctx.col("organizations", "deletedAt")} = now() where ${n.id} = organization and ${ctx.col("organizations", "deletedAt")} is null;`
    : `delete from ${n.organization} where ${n.id} = organization;`;

  return `
-- Deletes an organization (blocks.organizations.options.deleteMode: ${soft ? "soft, setting deleted_at" : "hard, with its memberships"}).
create or replace function ${ctx.fn("delete_organization")}(organization ${id})
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (${SERVICE_CALLER}) and not coalesce(better_supabase.member_can(auth.uid(), organization, ${ctx.permission("delete", OPERATIONS["organizations.delete"])}), false)${helpers.platformOverride} then
    ${fail("ORGANIZATION_FORBIDDEN", "Not allowed to delete the organization")}
  end if;
  ${action}
  if not found then
    return false;
  end if;${soft ? "" : `\n  delete from ${n.m} where ${n.tenant} = organization;`}
  ${ctx.record({
    type: "organization.deleted",
    payload: helpers.event("organization", "auth.uid()"),
    subject: "'organizations/' || organization::text",
    tenant: "organization",
    audit: {
      category: "configuration",
      targetType: "organization",
      recordId: "organization::text",
      metadata: `jsonb_build_object('mode', ${sqlString(soft ? "soft" : "hard")})`,
    },
  })}
  return true;
end;
$$;
`;
}
