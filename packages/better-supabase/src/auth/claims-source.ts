import type { AuthSnapshot } from "../client/bind.ts";
import type { AuthSession } from "./view.ts";

/** Verified claims, read by name. */
export type ClaimsRecord = Readonly<Record<string, unknown>>;

/** A server session, the client's `useAuth()` snapshot, or verified claims. */
export type ClaimsSource<C = unknown, P = unknown> =
  | AuthSession<C, P>
  | AuthSnapshot
  | ClaimsRecord;

const SESSION_KINDS = new Set(["user", "secret", "apiKey", "none", "invalid"]);
const SNAPSHOT_STATUSES = new Set(["loading", "signed-out", "signed-in"]);

function isSessionLike(
  source: ClaimsSource,
): source is AuthSession | AuthSnapshot {
  if ("kind" in source && typeof source.kind === "string") {
    return SESSION_KINDS.has(source.kind);
  }

  return (
    "status" in source &&
    typeof source.status === "string" &&
    SNAPSHOT_STATUSES.has(source.status) &&
    "claims" in source
  );
}

/**
 * The claims of a user session or a signed-in snapshot, or `source` itself when
 * it is a claims record. `undefined` for every other caller.
 */
export function claimsFrom(source: ClaimsSource): ClaimsRecord | undefined {
  if (!isSessionLike(source)) {
    return source;
  }

  if ("kind" in source) {
    return source.kind === "user" ? source.claims : undefined;
  }

  return source.status === "signed-in" ? source.claims : undefined;
}
