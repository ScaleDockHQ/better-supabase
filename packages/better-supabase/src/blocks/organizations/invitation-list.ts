import type { BlockCall } from "../../core/block-helpers.ts";
import type {
  EntityList,
  EntityListSurface,
  TenantOption,
} from "../../core/entity-list.ts";
import type { BlockTenant } from "../../core/tenant-source.ts";
import type { OrganizationInvitationRow } from "./organizations.ts";

import { entityList, tenantOrOption } from "../../core/entity-list.ts";
import { temporal } from "../../core/temporal-required.ts";

/**
 * What `invitationsPage`, `invitationsFacets` and `invitationsCount` accept
 * (ADR 0923). The manifest declares the same names, and the SQL list function
 * `page_organization_invitations` implements them.
 */
export const invitationListSurface: EntityListSurface = {
  sorts: ["expiresAt", "email"],
  facets: ["role"],
  filters: ["role"],
  search: ["email"],
};

/** One `list_organization_invitations` row as an `OrganizationInvitationRow`. */
export function invitationRowOf(
  row: Record<string, unknown>,
): OrganizationInvitationRow {
  const expiresAt = row["expires_at"] ?? row["expiresAt"];

  return {
    id: String(row["id"]),
    email: String(row["email"]),
    role: String(row["role"]),
    ...(typeof expiresAt === "string"
      ? { expiresAt: temporal().Instant.from(expiresAt) }
      : {}),
  };
}

/**
 * The page, facet and count reads over `page_organization_invitations` (ADR
 * 0923). A call names the organization, or reads the block\'s `tenant`.
 */
export function invitationList(
  call: BlockCall,
  tenant: BlockTenant | undefined,
): EntityList<OrganizationInvitationRow, TenantOption> {
  return entityList<OrganizationInvitationRow, TenantOption>({
    entity: "invitation",
    surface: invitationListSurface,
    call,
    tenant: tenantOrOption(tenant),
    fn: "page_organization_invitations",
    rowOf: (row) => invitationRowOf(row),
  });
}
