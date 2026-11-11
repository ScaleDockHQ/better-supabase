import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { readPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { bsbShell } from "@/lib/supabase/server-shell";

import { SIGNING_KEYS_TAG } from "./signing-keys-cache";
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
 * The organization's published keys, newest first: the first is the active one.
 * Reads with the service role, so it checks the permission itself. A failed
 * read throws, so it is never cached and Retry reads again. `null` without an
 * organization or the permission.
 */
export async function loadSigningKeys(): Promise<SigningKeysOverview | null> {
  "use cache: private";

  const request = await bsbShell.cached();
  cacheTag(SIGNING_KEYS_TAG);
  const { session } = request;
  const permissions = await readPermissions(request);

  const tenant = tenantOf(session);

  if (!tenant || !can(permissions, SIGNING_KEYS_PERMISSION)) {
    return null;
  }

  const jwks = await signingKeys().jwks({ owner: organizationOwner(tenant) });

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
