import type { AuthState, ResolveAuthOptions } from "../auth/resolve.ts";
import type { EveSessionAuth } from "./types.ts";

import { resolveAuth } from "../auth/resolve.ts";
import { isAnonymousUser } from "../auth/view.ts";
import { isRecord } from "../core/block-helpers.ts";
import { claimAt, DEFAULT_CLAIMS, tenantClaimPaths } from "../core/claims.ts";

/** Thrown by `supabaseAuth` so eve answers with `response` instead of downgrading to anonymous. */
export class EveAuthRejection extends Error {
  override readonly name = "EveAuthRejection";
  readonly response: Response;

  constructor(message: string, status = 401) {
    super(message);
    this.response = new Response(JSON.stringify({ error: message }), {
      status,
      headers: { "content-type": "application/json" },
    });
  }
}

export interface SupabaseAuthOptions extends Omit<
  ResolveAuthOptions,
  "refresh" | "leeway" | "refreshTimeoutMs"
> {
  /** The tenant claim, `config.claims.tenant`. Defaults to `tenant_id`. */
  readonly tenantClaim?: string;
  /** The memberships claim, `config.claims.memberships`. Defaults to `memberships`. */
  readonly membershipsClaim?: string;
  /** Extra attributes from the verified claims, merged over the defaults. */
  readonly attributes?: (
    claims: Readonly<Record<string, unknown>>,
  ) => Readonly<Record<string, string | readonly string[]>>;
}

function rolesIn(
  claims: Readonly<Record<string, unknown>>,
  tenantId: string | undefined,
  claim: string,
): readonly string[] {
  const memberships = claims[claim];
  const strings = (value: unknown): string[] =>
    Array.isArray(value)
      ? value.filter((role): role is string => typeof role === "string")
      : [];
  if (tenantId === undefined) return [];
  if (Array.isArray(memberships)) {
    return [
      ...new Set(
        memberships.flatMap((entry) =>
          isRecord(entry) && entry["id"] === tenantId
            ? strings(entry["roles"])
            : [],
        ),
      ),
    ];
  }
  return isRecord(memberships) ? strings(memberships[tenantId]) : [];
}

/** The eve principal for a verified Supabase user, or `null` for anyone else. */
export function principalOf(
  auth: AuthState,
  options: Pick<
    SupabaseAuthOptions,
    "tenantClaim" | "membershipsClaim" | "attributes"
  > = {},
): EveSessionAuth | null {
  if (auth.kind !== "user") return null;
  const claims: Readonly<Record<string, unknown>> = auth.claims;
  let tenantId: string | undefined;
  for (const path of tenantClaimPaths(options.tenantClaim)) {
    tenantId ??= claimAt(claims, path);
  }
  const issuer = typeof claims["iss"] === "string" ? claims["iss"] : undefined;
  return {
    authenticator: "supabase",
    principalType: "user",
    principalId: auth.claims.sub,
    subject: auth.claims.sub,
    ...(issuer === undefined ? {} : { issuer }),
    attributes: {
      ...(tenantId === undefined ? {} : { tenantId }),
      roles: rolesIn(
        claims,
        tenantId,
        options.membershipsClaim ?? DEFAULT_CLAIMS.memberships,
      ),
      isAnonymous: isAnonymousUser(claims) ? "true" : "false",
      ...options.attributes?.(claims),
    },
  };
}

/**
 * An eve route `AuthFn` that verifies the Supabase session locally (cookie or
 * bearer) and maps the user to a principal. Requests without a session fall
 * through to the next entry; an invalid token is rejected with 401.
 */
export function supabaseAuth(
  options: SupabaseAuthOptions,
): (request: Request) => Promise<EveSessionAuth | null> {
  return async (request) => {
    const { auth } = await resolveAuth(request, options);
    if (auth.kind === "invalid")
      throw new EveAuthRejection("The Supabase session is not valid");
    return principalOf(auth, options);
  };
}
