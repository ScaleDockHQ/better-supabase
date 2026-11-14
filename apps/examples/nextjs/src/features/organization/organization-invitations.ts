import "server-only";
import { bsb } from "@/lib/supabase/server";

export interface InvitationRow {
  readonly id: string;
  readonly email: string;
  readonly role: string;
  readonly expiresAt: string | null;
}

/**
 * The open invitations of the active organization, through the block's
 * `invitationsPage`.
 */
export async function getOpenInvitations(): Promise<readonly InvitationRow[]> {
  "use cache: private";
  const { db } = await bsb.cached();

  const page = await db.$blocks.organizations
    .invitationsPage({ limit: 50 })
    .orThrow();

  return page.items.map((invitation) => ({
    id: invitation.id,
    email: invitation.email,
    role: invitation.role,
    expiresAt: invitation.expiresAt?.toString() ?? null,
  }));
}
