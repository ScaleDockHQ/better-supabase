import { type DbError, dbError } from "../core/errors.ts";

/** Authenticator assurance level: `aal2` once a second factor is verified in this session. */
export type Aal = "aal1" | "aal2";

/** One way the user proved who they are in this session (the JWT `amr` claim). */
export interface AmrEntry {
  /** `password`, `otp`, `oauth`, `totp`, `sso/saml`, `anonymous`, ... */
  readonly method: string;
  /** Seconds since epoch. */
  readonly timestamp: number;
  /** SSO provider id, for `sso/saml`. */
  readonly provider?: string;
}

/** The session's assurance level from its claims; anything but `aal2` reads as `aal1`. */
export function aalOf(claims: Readonly<Record<string, unknown>>): Aal {
  return claims["aal"] === "aal2" ? "aal2" : "aal1";
}

/** The `amr` claim as typed entries, skipping malformed ones. */
export function amrOf(
  claims: Readonly<Record<string, unknown>>,
): readonly AmrEntry[] {
  const amr = claims["amr"];
  if (!Array.isArray(amr)) return [];
  return amr.flatMap((entry: unknown): AmrEntry[] => {
    if (typeof entry !== "object" || entry === null) return [];
    const { method, timestamp, provider } = entry as Record<string, unknown>;
    if (typeof method !== "string" || typeof timestamp !== "number") return [];
    return [
      typeof provider === "string"
        ? { method, timestamp, provider }
        : { method, timestamp },
    ];
  });
}

/**
 * `undefined` when a user session meets `required`; otherwise a `forbidden`
 * error with `required` and code `INSUFFICIENT_AAL`, for the client to start
 * an MFA challenge. Non-user sessions pass: `allow` decides about them.
 */
export function checkAal(
  auth:
    | { readonly kind: "user"; readonly claims: object }
    | { readonly kind: string },
  required: Aal,
): DbError | undefined {
  if (required === "aal1" || auth.kind !== "user" || !("claims" in auth))
    return undefined;
  if (aalOf(auth.claims as Record<string, unknown>) === "aal2")
    return undefined;
  return dbError("forbidden", "Verify a second factor to continue", {
    code: "INSUFFICIENT_AAL",
    required,
  });
}
