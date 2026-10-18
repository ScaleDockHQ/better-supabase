import "server-only";
import { tenantOf } from "better-supabase/next";

import { can } from "@/features/user/user-permissions";
import { bs } from "@/lib/supabase/server";

import {
  organizationOwner,
  SIGNING_KEYS_PERMISSION,
  signingKeys,
} from "./signing-keys-server";

export interface SigningKeyRow {
  readonly kid: string;
  readonly algorithm: string;
}

export interface SigningKeysOverview {
  readonly active: SigningKeyRow | null;
  /** Retired keys still published until the tokens they signed expire. */
  readonly previous: readonly SigningKeyRow[];
}

/**
 * The organization's published keys, newest first: the first is the
 * active one. Reads with the service role, so it checks the permission
 * itself. A failed read throws, so it is never cached and Retry reads
 * again. `null` without an organization or the permission.
 */
export async function loadSigningKeys(): Promise<SigningKeysOverview | null> {
  "use cache: private";
  const { session } = await bs.cached();
  const tenant = tenantOf(session);

  if (!tenant || !can(session, SIGNING_KEYS_PERMISSION)) {
    return null;
  }

  const jwks = await signingKeys().jwks(organizationOwner(tenant));

  if (!jwks.ok) {
    throw new Error(jwks.error.message);
  }

  const rows = jwks.data.keys.map((key) => ({
    kid: key.kid ?? "",
    algorithm: key.alg ?? key.crv ?? key.kty,
  }));

  const [active, ...previous] = rows;

  return { active: active ?? null, previous };
}
