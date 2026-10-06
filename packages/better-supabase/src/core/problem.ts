import {
  type DbError,
  type DbErrorKind,
  type DbErrorKinds,
  dbError,
  type ValidationIssue,
} from "./errors.ts";

/** RFC 9457 Problem Details, with the `DbError` fields as extension members. */
export interface ProblemDetails {
  readonly type: string;
  readonly title: string;
  readonly status: number;
  readonly detail?: string;
  readonly instance?: string;
  /** The `DbError` kind. */
  readonly kind: DbErrorKind;
  readonly code?: string;
  readonly hint?: string;
  readonly constraint?: string;
  readonly columns?: readonly string[];
  readonly column?: string;
  readonly issues?: readonly ValidationIssue[];
  /** The assurance level a `forbidden` answer needs (`aal2`). */
  readonly required?: "aal1" | "aal2";
  /** The OAuth scopes a `forbidden` answer needs. */
  readonly scopes?: readonly string[];
  /** Seconds until a `rate_limited` or `quota_exceeded` caller may retry. */
  readonly retryAfter?: number;
  /** The meter a `quota_exceeded` answer ran out of, and its limit. */
  readonly meter?: string;
  readonly limit?: number;
  /** The row limit a `max_affected` write exceeded. */
  readonly maxAffected?: number;
}

export const PROBLEM_TYPE_BASE = "https://bettersupabase.com/problems/";
export const PROBLEM_CONTENT_TYPE = "application/problem+json";

const TITLES: { readonly [K in DbErrorKind]: string } = {
  not_found: "Not found",
  unauthorized: "Unauthorized",
  forbidden: "Forbidden",
  conflict: "Conflict",
  foreign_key: "Referenced row missing or still referenced",
  check: "Check constraint violated",
  not_null: "Required value missing",
  exclusion: "Exclusion constraint violated",
  invalid_input: "Invalid input",
  invalid_value: "Stored value not representable",
  raised: "Request rejected",
  timeout: "Timed out",
  serialization: "Concurrent update, retry",
  network: "Database unreachable",
  aborted: "Aborted",
  invalid_request: "Invalid request",
  validation: "Validation failed",
  multiple_rows: "More than one row matched",
  stale: "Row changed since it was read",
  max_affected: "Too many rows affected",
  rate_limited: "Too many requests",
  quota_exceeded: "Quota exceeded",
  unsupported: "Not supported by this executor",
  unexpected: "Unexpected error",
};

/** Kinds whose message may contain internals (SQL, hostnames), hidden unless `expose` is set. */
const INTERNAL = new Set<DbErrorKind>([
  "unexpected",
  "network",
  "invalid_request",
]);

export interface ProblemOptions {
  /** URI reference for this occurrence, e.g. the request path. */
  readonly instance?: string;
  /** Include messages of internal errors. Defaults to false. */
  readonly expose?: boolean;
}

export interface ProblemResponseOptions extends ProblemOptions {
  readonly headers?: ConstructorParameters<typeof Headers>[0];
  /** `realm` of the RFC 6750 challenge on 401. */
  readonly realm?: string;
}

/** Converts a `DbError` to Problem Details. */
export function toProblem(
  error: DbError,
  options: ProblemOptions = {},
): ProblemDetails {
  const problem: Record<string, unknown> = {
    type: `${PROBLEM_TYPE_BASE}${error.kind.replaceAll("_", "-")}`,
    title: TITLES[error.kind],
    status: error.status,
    kind: error.kind,
  };
  if (!INTERNAL.has(error.kind) || options.expose)
    problem["detail"] = error.message;
  if (options.instance) problem["instance"] = options.instance;
  if (error.code) problem["code"] = error.code;
  if (error.hint) problem["hint"] = error.hint;
  if ("constraint" in error && error.constraint)
    problem["constraint"] = error.constraint;
  if ("columns" in error) problem["columns"] = error.columns;
  if ("column" in error && error.column) problem["column"] = error.column;
  if ("issues" in error) problem["issues"] = error.issues;
  if ("required" in error) problem["required"] = error.required;
  if ("scopes" in error) problem["scopes"] = error.scopes;
  if ("retryAfter" in error) problem["retryAfter"] = error.retryAfter;
  if ("meter" in error) problem["meter"] = error.meter;
  if ("limit" in error) problem["limit"] = error.limit;
  if ("maxAffected" in error) problem["maxAffected"] = error.maxAffected;
  // SAFETY: the fields were copied from a DbError, whose shape matches ProblemDetails.
  // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- the fields were copied from a DbError, whose shape matches ProblemDetails.
  return problem as unknown as ProblemDetails;
}

/**
 * An `application/problem+json` response. A 401, and a 403 for a missing
 * OAuth scope, carry an RFC 6750 `WWW-Authenticate: Bearer` challenge.
 */
export function problemResponse(
  error: DbError,
  options: ProblemResponseOptions = {},
): Response {
  const headers = new Headers(options.headers);
  headers.set("content-type", PROBLEM_CONTENT_TYPE);
  const realm = (options.realm ?? "supabase").replaceAll('"', "");
  if (error.status === 401 && !headers.has("www-authenticate")) {
    const params =
      error.code === "MISSING_CREDENTIALS" ? "" : ', error="invalid_token"';
    headers.set("www-authenticate", `Bearer realm="${realm}"${params}`);
  }
  if (
    "scopes" in error &&
    error.code === "INSUFFICIENT_SCOPE" &&
    !headers.has("www-authenticate")
  ) {
    const scope = error.scopes.join(" ").replaceAll('"', "");
    headers.set(
      "www-authenticate",
      `Bearer realm="${realm}", error="insufficient_scope", scope="${scope}"`,
    );
  }
  if ("retryAfter" in error && !headers.has("retry-after"))
    headers.set("retry-after", String(error.retryAfter));
  return new Response(JSON.stringify(toProblem(error, options)), {
    status: error.status,
    headers,
  });
}

export function isProblem(value: unknown): value is ProblemDetails {
  if (typeof value !== "object" || value === null) return false;
  // SAFETY: value is a non-null object here, and every field is checked below.
  const problem = value as Record<string, unknown>;
  return (
    typeof problem["type"] === "string" &&
    typeof problem["status"] === "number" &&
    typeof problem["title"] === "string"
  );
}

function isKind(value: unknown): value is DbErrorKind {
  return typeof value === "string" && value in TITLES;
}

/** Turns a Problem Details body back into a `DbError` (client side). */
export function fromProblem(problem: ProblemDetails): DbError {
  const kind = isKind(problem.kind) ? problem.kind : "unexpected";
  const extra: Record<string, unknown> = { status: problem.status };
  for (const key of [
    "code",
    "hint",
    "constraint",
    "columns",
    "column",
    "required",
    "scopes",
    "retryAfter",
    "meter",
    "limit",
    "maxAffected",
  ] as const) {
    if (problem[key] !== undefined) extra[key] = problem[key];
  }
  extra["issues"] = problem.issues ?? [];
  if (kind !== "validation") delete extra["issues"];
  // SAFETY: extra holds the extension fields of the problem, which are optional
  // on every DbError kind.
  return dbError(
    kind,
    problem.detail ?? problem.title,
    extra as DbErrorKinds["validation"],
  );
}
