import type { AuthSession } from "../auth/view.ts";

/**
 * The user as plain data for Client Components: no token, no session, no
 * claims. `bsb.user()` returns it and `useUser()` reads it.
 */
export interface GateUser {
  readonly id: string;
  readonly email: string | null;
  readonly name: string | null;
  /** The active tenant from the token's tenant claim, `null` without one. */
  readonly organizationId: string | null;
}

const NAME_KEYS = ["full_name", "name", "display_name"] as const;

function nameOf(metadata: Record<string, unknown> | undefined): string | null {
  for (const key of NAME_KEYS) {
    const value = metadata?.[key];

    if (typeof value === "string" && value !== "") {
      return value;
    }
  }

  return null;
}

/** The `GateUser` of a verified view; `null` for anything but a signed-in user. */
export function gateUserOf(
  view: AuthSession,
  tenant: string | undefined,
): GateUser | null {
  if (view.kind !== "user") {
    return null;
  }

  return {
    id: view.user.id,
    email: view.user.email ?? null,
    name: nameOf(view.user.userMetadata),
    organizationId: tenant ?? null,
  };
}
