import type { OrganizationOverviewRaw } from "../../sql/modules/organizations-overview.ts";
import type {
  OrganizationInvitationRow,
  OrganizationMember,
} from "./organizations.ts";

import { decodeRead } from "../../core/read-type.ts";
import { temporal } from "../../core/temporal-required.ts";
import { ORGANIZATION_OVERVIEW_RESULT } from "../../sql/modules/organizations-overview.ts";

/** What `organizations.overview` returns. */
export interface OrganizationOverview {
  readonly id: string;
  readonly name: string;
  readonly slug: string | null;
  /** The caller's role in the organization. */
  readonly role: string;
  /** The billed seats, or `null` without the billing block or billing access. */
  readonly seats: number | null;
  readonly members: readonly OrganizationMember[];
  readonly invitations: readonly OrganizationInvitationRow[];
}

const instant = (value: string | null): Temporal.Instant | undefined =>
  value === null ? undefined : temporal().Instant.from(value);

/** Decodes the `organization_overview` JSON, turning timestamps into instants. */
export function decodeOverview(value: unknown): OrganizationOverview {
  const raw = decodeRead<OrganizationOverviewRaw>(
    ORGANIZATION_OVERVIEW_RESULT,
    value,
    "organization_overview",
  );

  return {
    ...raw,
    members: raw.members.map((member) => {
      const disabledAt = instant(member.disabledAt);

      return {
        userId: member.userId,
        role: member.role,
        roles: member.roles,
        ...(disabledAt === undefined ? {} : { disabledAt }),
      };
    }),
    invitations: raw.invitations.map((invitation) => {
      const expiresAt = instant(invitation.expiresAt);

      return {
        id: invitation.id,
        email: invitation.email,
        role: invitation.role,
        ...(expiresAt === undefined ? {} : { expiresAt }),
      };
    }),
  };
}
