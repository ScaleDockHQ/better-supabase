import "server-only";
import * as v from "valibot";

import { Role } from "@/lib/claims";
import { bsb } from "@/lib/supabase/server";

export interface InvitationSummary {
  readonly status: "pending" | "accepted" | "declined" | "revoked" | "expired";
  readonly email: string;
  readonly role: Role;
  readonly organizationName: string | null;
  /** ISO 8601. */
  readonly expiresAt: string;
}

/**
 * What an invitation link points to, callable without a session
 * (`invitation_preview`). `null` for an unknown token.
 */
export async function getInvitationPreview(
  token: string,
): Promise<InvitationSummary | null> {
  "use cache: private";
  const { db } = await bsb.cached();

  const preview = await db.$blocks.organizations
    .previewInvitation(token)
    .orThrow();

  if (!preview) {
    return null;
  }

  const name = preview.organization?.["name"];

  return {
    status: preview.status,
    email: preview.email,
    role: v.is(Role, preview.role) ? preview.role : "member",
    organizationName: v.is(v.string(), name) ? name : null,
    expiresAt: preview.expiresAt.toString(),
  };
}
