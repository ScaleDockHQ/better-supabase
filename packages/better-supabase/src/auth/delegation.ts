import type { RequestContext } from "../core/plugin.ts";

import { actorOf, type ActClaim } from "./actor.ts";
import { actClaim, impersonatorClaim } from "./impersonation.ts";

/** One RFC 9396 `authorization_details` entry. */
export interface AuthorizationDetail {
  readonly type: string;
  readonly [field: string]: unknown;
}

/**
 * What a delegated token carries, under its wire names: the OAuth client,
 * the scopes the user granted it (space-separated), its RFC 9396
 * authorization details and the RFC 8693 `act` chain of an OAuth client or
 * agent. Jobs and workflows record it so the work they run stays as
 * narrow as the token that queued it.
 */
export interface DelegatedClaims {
  readonly client_id?: string;
  readonly scope?: string;
  readonly authorization_details?: readonly AuthorizationDetail[];
  readonly act?: ActClaim;
}

export type DelegatedClaimsOutcome =
  | { readonly ok: true; readonly delegation?: DelegatedClaims }
  | {
      readonly ok: false;
      readonly reason: "invalid-chain" | "invalid-delegation";
    };

/**
 * The claim `forContext({ permissions })` sets: the permission keys the
 * work may use. `better_supabase.cap_allows` refuses every other key, and
 * a job queued under a cap keeps it.
 */
export const PERMISSION_CAP_CLAIM = "bs_permission_cap";

/** The claims a delegated token adds; `contextClaims` never takes them from `claimsFor`. */
export const DELEGATION_CLAIMS: readonly string[] = [
  "act",
  "client_id",
  "scope",
  "authorization_details",
  PERMISSION_CAP_CLAIM,
];

/** `*` grants every key and `prefix.*` every key under prefix, as `permission_matches` in SQL. */
export function permissionMatches(granted: string, wanted: string): boolean {
  return (
    granted === "*" ||
    granted === wanted ||
    (granted.endsWith(".*") && wanted.startsWith(granted.slice(0, -1)))
  );
}

/**
 * The permission cap in `claims`: `undefined` without one, `false` for a
 * cap that is not a list of strings.
 */
export function permissionCapOf(
  claims: Readonly<Record<string, unknown>>,
): readonly string[] | false | undefined {
  const cap = claims[PERMISSION_CAP_CLAIM];
  if (cap === undefined) return undefined;
  return Array.isArray(cap) && cap.every((key) => typeof key === "string")
    ? cap
    : false;
}

/**
 * The keys of `wanted` that `inherited` allows, so a cap only ever narrows.
 * Either side alone is the cap; neither is no cap.
 */
export function narrowCap(
  inherited: readonly string[] | undefined,
  wanted: readonly string[] | undefined,
): readonly string[] | undefined {
  if (wanted === undefined) return inherited;
  if (inherited === undefined) return wanted;
  return wanted.filter((key) =>
    inherited.some((granted) => permissionMatches(granted, key)),
  );
}

const INVALID: DelegatedClaimsOutcome = {
  ok: false,
  reason: "invalid-delegation",
};

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isDetail(value: unknown): value is AuthorizationDetail {
  return (
    isRecord(value) && typeof value["type"] === "string" && value["type"] !== ""
  );
}

function scopeOf(value: unknown): string | false | undefined {
  if (value === undefined) return undefined;
  const scopes =
    typeof value === "string"
      ? value.split(/\s+/u)
      : Array.isArray(value) && value.every((item) => typeof item === "string")
        ? value
        : undefined;
  if (scopes === undefined) return false;
  const joined = scopes.filter(Boolean).join(" ");
  return joined === "" ? undefined : joined;
}

/**
 * The delegation in `claims`, for a token an OAuth client or agent acts
 * with: a `client_id`, or an `act` chain that is not a support or
 * impersonation level. `{ ok: true }` without `delegation` for any other
 * session. An invalid `act` chain, a `client_id` that is not a non-empty
 * string, a `scope` that is neither a string nor a list of strings, and
 * `authorization_details` that are not objects with a `type` are
 * `{ ok: false }`: the work must not run as the user alone.
 */
export function delegatedClaims(
  claims: Readonly<Record<string, unknown>>,
): DelegatedClaimsOutcome {
  const outcome = actorOf(claims);
  if (!outcome.ok) return { ok: false, reason: "invalid-chain" };
  const client = claims["client_id"];
  if (client !== undefined && (typeof client !== "string" || client === ""))
    return INVALID;
  const actor = outcome.actor;
  const chain =
    actor?.kind === "oauth-client" || actor?.kind === "agent"
      ? actor.chain
      : undefined;
  if (client === undefined && chain === undefined) return { ok: true };
  const scope = scopeOf(claims["scope"]);
  if (scope === false) return INVALID;
  const details = claims["authorization_details"];
  if (
    details !== undefined &&
    !(Array.isArray(details) && details.every(isDetail))
  ) {
    return INVALID;
  }
  return {
    ok: true,
    delegation: {
      ...(client === undefined ? {} : { client_id: client }),
      ...(scope === undefined ? {} : { scope }),
      ...(details === undefined ? {} : { authorization_details: details }),
      ...(chain === undefined ? {} : { act: chain }),
    },
  };
}

/** The claims `forContext` runs with: `sub`, `role` and the context's tenant and delegation win. */
export interface RunClaims {
  readonly sub: string;
  readonly role: string;
  readonly [claim: string]: unknown;
}

export type ContextClaimsOutcome =
  | {
      readonly ok: true;
      readonly claims: RunClaims;
      /** The admin behind the session, for `actor.impersonator`. */
      readonly impersonator?: string;
      /** Set for a read-only support session; the transaction runs read only. */
      readonly readOnly?: boolean;
    }
  | { readonly ok: false; readonly message: string };

export interface ContextClaimsOptions {
  /** `ServerOptions.claimsFor`: added first, without the delegation claims. */
  readonly extra?: Readonly<Record<string, unknown>>;
  /** `act.reason` for an impersonator. Defaults to `"job"`. */
  readonly reason?: string;
  /** `ForContextOptions.permissions`: narrows the recorded cap, never widens it. */
  readonly permissions?: readonly string[];
}

/**
 * The SQL claims for the user in a recorded context: the user as
 * `authenticated`, the tenant as `tenant_id`, and the context's delegation,
 * so the access functions (through `cap_allows`), `token_scope_allows` and
 * the TypeScript scope checks narrow the work to what the queuing token
 * held, and to its permission cap. The `act` claim is the support session,
 * else the OAuth client chain, else the impersonating admin.
 */
export function contextClaims(
  context: RequestContext,
  options: ContextClaimsOptions = {},
): ContextClaimsOutcome {
  const { actor, tenant } = context;
  if (actor?.kind !== "user") {
    return {
      ok: false,
      message: `forContext needs a user actor, got ${actor ? actor.kind : "none"}: use admin() for service work`,
    };
  }
  const claims = context.claims ?? {};
  const recorded = actorOf(claims);
  const delegated = delegatedClaims(claims);
  const inherited = permissionCapOf(claims);
  if (inherited === false) {
    return { ok: false, message: "forContext got an invalid permission cap" };
  }
  const cap = narrowCap(inherited, options.permissions);
  if (!recorded.ok || !delegated.ok) {
    return {
      ok: false,
      message:
        !recorded.ok || (!delegated.ok && delegated.reason === "invalid-chain")
          ? "forContext got an invalid act claim"
          : "forContext got invalid delegation claims",
    };
  }
  const support =
    recorded.actor?.kind === "support" ? recorded.actor : undefined;
  const delegation = delegated.delegation ?? {};
  const act = support
    ? impersonatorClaim(support)
    : (delegation.act ??
      (actor.impersonator
        ? actClaim({
            actor: actor.impersonator,
            reason: options.reason ?? "job",
          })
        : undefined));
  const extra = Object.fromEntries(
    Object.entries(options.extra ?? {}).filter(
      ([key]) => !DELEGATION_CLAIMS.includes(key),
    ),
  );
  const impersonator = support?.id ?? actor.impersonator;
  return {
    ok: true,
    claims: {
      ...extra,
      role: "authenticated",
      sub: actor.id,
      ...(tenant === undefined ? {} : { tenant_id: tenant }),
      ...delegation,
      ...(act === undefined ? {} : { act }),
      ...(cap === undefined ? {} : { [PERMISSION_CAP_CLAIM]: cap }),
    },
    ...(impersonator === undefined ? {} : { impersonator }),
    ...(support?.readOnly ? { readOnly: true } : {}),
  };
}
