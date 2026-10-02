import { type DbError, DbException, dbError } from "./errors.ts";
import { optionalTemporal, TEMPORAL_MISSING } from "./temporal.ts";

/** The error for a runtime without Temporal, naming the polyfill to load. */
export function temporalMissing(): DbError {
  return dbError("unexpected", TEMPORAL_MISSING);
}

/**
 * The runtime's `Temporal`. Node 26, Chromium, Firefox and Deno ship it.
 * Elsewhere it throws a `DbException`, which repositories return as an
 * `unexpected` error that names the polyfill.
 */
export function temporal(): typeof Temporal {
  const namespace = optionalTemporal();
  if (namespace === undefined) throw new DbException(temporalMissing());
  return namespace;
}
