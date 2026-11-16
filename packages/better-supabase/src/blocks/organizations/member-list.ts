import type { BlockCall } from "../../core/block-helpers.ts";
import type {
  EntityList,
  EntityListSurface,
  TenantOption,
} from "../../core/entity-list.ts";
import type { BlockTenant } from "../../core/tenant-source.ts";
import type { OrganizationMember } from "./organizations.ts";

import { entityList, tenantOrOption } from "../../core/entity-list.ts";
import { temporal } from "../../core/temporal-required.ts";

const text = (value: unknown): string =>
  typeof value === "string" ? value : String(value);

export const rolesOf = (
  row: Record<string, unknown>,
): { readonly roles?: readonly string[] } => {
  const roles = row["roles"];

  return Array.isArray(roles) ? { roles: roles.map((role) => text(role)) } : {};
};

export const disabledAtOf = (
  row: Record<string, unknown>,
): { readonly disabledAt?: Temporal.Instant } => {
  const disabledAt = row["disabled_at"];

  return disabledAt === null || disabledAt === undefined
    ? {}
    : { disabledAt: temporal().Instant.from(text(disabledAt)) };
};

/** An `OrganizationMember` from a `list_members` or member page row. */
export const memberOf = (row: Record<string, unknown>): OrganizationMember => ({
  userId: text(row["user_id"]),
  role: text(row["role"]),
  ...rolesOf(row),
  ...disabledAtOf(row),
});

/**
 * What `membersPage`, `membersFacets` and `membersCount` accept (ADR 1077). The
 * manifest declares the same names, and the SQL list function
 * `page_organization_members` implements them. Members have no searchable text
 * column, so `q` is not accepted.
 */
export const memberListSurface: EntityListSurface = {
  sorts: ["role", "userId"],
  facets: ["role"],
  filters: ["role"],
};

/**
 * The page, facet and count reads over `page_organization_members`. A call
 * names the organization, or reads the block's `tenant`.
 */
export function memberList(
  call: BlockCall,
  tenant: BlockTenant | undefined,
): EntityList<OrganizationMember, TenantOption> {
  return entityList<OrganizationMember, TenantOption>({
    entity: "member",
    surface: memberListSurface,
    call,
    tenant: tenantOrOption(tenant),
    fn: "page_organization_members",
    rowOf: (row) => memberOf(row),
  });
}
