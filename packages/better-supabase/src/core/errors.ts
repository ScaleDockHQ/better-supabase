import { DbException } from "./db-exception.ts";

export { DbException };

/**
 * Extra fields carried by each error kind. Plugins can add kinds through the
 * `errors` extension point; apps that want the new kinds in the union can add
 * them to this interface.
 */
export interface DbErrorKinds {
  not_found: Record<never, never>;
  unauthorized: Record<never, never>;
  /**
   * `required`: the assurance level the route needs, when a second factor is
   * missing. `scopes`: the OAuth scopes the route needs, when a delegated token
   * lacks one (`INSUFFICIENT_SCOPE`). `permission`: the key an `Authorizer`
   * denied. `permissions`: the keys the caller lacks, such as the ones a
   * workflow's steps need (`WORKFLOW_PUBLISHER_FORBIDDEN`). `approval`: the
   * pending approval when the answer is `APPROVAL_REQUIRED`.
   */
  forbidden: {
    required?: "aal1" | "aal2";
    scopes?: readonly string[];
    permission?: string;
    permissions?: readonly string[];
    approval?: { readonly id: string };
  };
  conflict: { constraint?: string; columns?: readonly string[] };
  foreign_key: { constraint?: string; columns?: readonly string[] };
  check: { constraint?: string };
  not_null: { column?: string };
  exclusion: { constraint?: string };
  /**
   * `fields`: the inputs that broke a rule, so a form can place each message
   * next to its field. Block functions fill it; other sources leave it out.
   */
  invalid_input: { fields?: readonly InputField[] };
  /**
   * A stored value the app type can't hold, e.g. `infinity` for a Temporal
   * timestamp.
   */
  invalid_value: { column?: string };
  raised: Record<never, never>;
  timeout: Record<never, never>;
  serialization: Record<never, never>;
  /**
   * The database or a service could not be reached. `retryAfter`: seconds until
   * a retry can succeed, when known (a paused connection pool).
   */
  network: { retryAfter?: number };
  aborted: Record<never, never>;
  invalid_request: Record<never, never>;
  validation: { issues: readonly ValidationIssue[] };
  multiple_rows: Record<never, never>;
  stale: Record<never, never>;
  /**
   * An `update({ where })` or `delete({ where })` matched more rows than its
   * `maxAffected` allows; nothing was written. `maxAffected`: the limit, when
   * known.
   */
  max_affected: { maxAffected?: number };
  /** `retryAfter`: seconds until the window resets (the `Retry-After` header). */
  rate_limited: { retryAfter?: number };
  /**
   * A usage quota is used up (`consume_quota`, SQLSTATE `BSQ29`). `meter`: what
   * was metered, `limit`: the quota, `retryAfter`: seconds until the period
   * resets.
   */
  quota_exceeded: { meter?: string; limit?: number; retryAfter?: number };
  /**
   * An unbounded read returned `maxRows` rows and a further row exists.
   * PostgREST cut the list. Add `limit` or use `page()`.
   */
  truncated: { table: string; maxRows: number };
  /**
   * The executor or its dialect can't run this operation (an include on SQLite,
   * say).
   */
  unsupported: Record<never, never>;
  unexpected: Record<never, never>;
}

export type DbErrorKind = keyof DbErrorKinds;

/** One input a block function rejected. */
export interface InputField {
  /** The input's path in the call, such as `["lines", 0, "quantity"]`. */
  readonly path: readonly (string | number)[];
  /** A hint-style code in upper snake case, such as `QUANTITY_TOO_LOW`. */
  readonly code: string;
  /** An English sentence for the field. */
  readonly message: string;
}

export interface ValidationIssue {
  readonly message: string;
  readonly path?: readonly PropertyKey[];
}

interface DbErrorBase<K extends DbErrorKind> {
  readonly kind: K;
  readonly message: string;
  /** SQLSTATE or PostgREST code (`23505`, `PGRST116`), when known. */
  readonly code?: string;
  /** Suggested HTTP status, used by the RFC 9457 mapping. */
  readonly status: number;
  readonly details?: string;
  /** Postgres `HINT`. `raised` errors use it as an app-level error code. */
  readonly hint?: string;
  /** App-cased table key the operation ran against. */
  readonly table?: string;
}

/**
 * A database error as plain, serializable data. Safe to send across server
 * action and RPC boundaries.
 */
export type DbError = {
  [K in DbErrorKind]: DbErrorBase<K> & DbErrorKinds[K];
}[DbErrorKind];

export type DbErrorOf<K extends DbErrorKind> = Extract<DbError, { kind: K }>;

const STATUS: { readonly [K in DbErrorKind]: number } = {
  not_found: 404,
  unauthorized: 401,
  forbidden: 403,
  conflict: 409,
  foreign_key: 409,
  check: 422,
  not_null: 422,
  exclusion: 409,
  invalid_input: 400,
  invalid_value: 500,
  raised: 400,
  timeout: 504,
  serialization: 409,
  network: 503,
  aborted: 499,
  invalid_request: 400,
  validation: 422,
  multiple_rows: 409,
  stale: 412,
  max_affected: 400,
  rate_limited: 429,
  quota_exceeded: 429,
  truncated: 413,
  unsupported: 501,
  unexpected: 500,
};

export function statusOf(kind: DbErrorKind): number {
  return STATUS[kind];
}

type ExtraOf<K extends DbErrorKind> =
  Record<never, never> extends DbErrorKinds[K]
    ? [extra?: DbErrorKinds[K] & Partial<Omit<DbErrorBase<K>, "kind">>]
    : [extra: DbErrorKinds[K] & Partial<Omit<DbErrorBase<K>, "kind">>];

/** Creates a `DbError` with the default status for its kind. */
export function dbError<K extends DbErrorKind>(
  kind: K,
  message: string,
  ...[extra]: ExtraOf<K>
): DbErrorOf<K> {
  const error: Record<string, unknown> = {
    kind,
    message,
    status: STATUS[kind],
  };

  if (extra) {
    for (const [key, value] of Object.entries(extra)) {
      if (value !== undefined) {
        error[key] = value;
      }
    }
  }

  // SAFETY: the loop above copied the detail fields for K onto the error.
  // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- the fields were copied from the detail map for K above.
  return error as unknown as DbErrorOf<K>;
}

/**
 * An `invalid_input` error that names the inputs at fault, with the first
 * field's code as the `hint` unless `extra.hint` is set.
 */
export function invalidInput(
  message: string,
  fields: readonly InputField[],
  extra: Partial<Pick<DbErrorBase<"invalid_input">, "code" | "details">> & {
    readonly hint?: string;
  } = {},
): DbErrorOf<"invalid_input"> {
  const hint = extra.hint ?? fields[0]?.code;

  return dbError("invalid_input", message, {
    ...extra,
    ...(hint === undefined ? {} : { hint }),
    fields,
  });
}

/**
 * The `DbError` for a failed HTTP response from a service: 400 and 422 are
 * `invalid_input`, 401 `unauthorized`, 403 `forbidden`, 404 `not_found`, 409
 * `conflict`, 408 and 504 `timeout`, 429 `rate_limited`, 5xx `network`, and
 * anything else `unexpected`. `extra` carries `code` or similar detail.
 */
export function dbErrorOfStatus(
  status: number,
  message: string,
  extra: Partial<
    Pick<DbErrorBase<DbErrorKind>, "code" | "details" | "hint">
  > = {},
): DbError {
  switch (status) {
    case 400:
    case 413:
    case 415:
    case 422: {
      return dbError("invalid_input", message, extra);
    }

    case 401: {
      return dbError("unauthorized", message, extra);
    }

    case 403: {
      return dbError("forbidden", message, extra);
    }

    case 404: {
      return dbError("not_found", message, extra);
    }

    case 408:
    case 504: {
      return dbError("timeout", message, extra);
    }

    case 409: {
      return dbError("conflict", message, extra);
    }

    case 429: {
      return dbError("rate_limited", message, extra);
    }

    default: {
      return status >= 500
        ? dbError("network", message, extra)
        : dbError("unexpected", message, extra);
    }
  }
}

/**
 * A plain `DbError`. A `DbException` carries the same fields but is not one;
 * `dbErrorOf()` reads the `DbError` out of it.
 */
export function isDbError(value: unknown): value is DbError {
  // SAFETY: value is a non-null object here, and each property read is type-checked.
  return (
    typeof value === "object" &&
    value !== null &&
    !(value instanceof Error) &&
    typeof (value as { kind?: unknown }).kind === "string" &&
    typeof (value as { message?: unknown }).message === "string" &&
    typeof (value as { status?: unknown }).status === "number"
  );
}

/**
 * The `DbError` in a `DbError`, a `DbException`, or an error whose `cause` is a
 * `DbError` (what `betterSupabase.mapError()` mappers should set).
 */
export function dbErrorOf(value: unknown): DbError | undefined {
  if (value instanceof DbException) {
    return value.error;
  }

  if (value instanceof Error && isDbError(value.cause)) {
    return value.cause;
  }

  return isDbError(value) ? value : undefined;
}

function constraintGuard<K extends "conflict" | "check" | "foreign_key">(
  kind: K,
) {
  return <C extends string = string>(
    error: unknown,
    constraint?: NoInfer<C>,
  ): error is DbErrorOf<K> & { readonly constraint: C } => {
    const found = dbErrorOf(error);

    if (found?.kind !== kind) {
      return false;
    }

    // SAFETY: found.kind === kind, and every kind that takes a constraint has
    // the constraint field.
    return (
      constraint === undefined ||
      (found as { constraint?: string }).constraint === constraint
    );
  };
}

/**
 * A unique violation, optionally for one constraint. Accepts a `DbError` or a
 * `DbException`. Pass the generated `UniqueConstraint` type to check names:
 * `isConflict<UniqueConstraint>(error, 'customers_organization_id_kvk_key')`.
 */
export const isConflict: <C extends string = string>(
  error: unknown,
  constraint?: NoInfer<C>,
) => error is DbErrorOf<"conflict"> & { readonly constraint: C } =
  constraintGuard("conflict");

/** A CHECK violation, optionally for one constraint (`CheckConstraint`). */
export const isCheck: <C extends string = string>(
  error: unknown,
  constraint?: NoInfer<C>,
) => error is DbErrorOf<"check"> & { readonly constraint: C } =
  constraintGuard("check");

/**
 * A foreign key violation, optionally for one constraint
 * (`ForeignKeyConstraint`).
 */
export const isForeignKey: <C extends string = string>(
  error: unknown,
  constraint?: NoInfer<C>,
) => error is DbErrorOf<"foreign_key"> & { readonly constraint: C } =
  constraintGuard("foreign_key");

/**
 * Handlers for `matchDbError`: one per error kind, plus `codes` for SQLSTATE
 * codes.
 */
export type DbErrorMatchers = {
  readonly [K in DbErrorKind]?: (error: DbErrorOf<K>) => unknown;
} & {
  /**
   * Handlers by SQLSTATE or PostgREST code (`23505`, `PGRST116`). They run
   * before the handler for the error's kind.
   */
  readonly codes?: Readonly<Record<string, (error: DbError) => unknown>>;
};

/**
 * Builds the factory `.orThrow()` takes from handlers per error kind and per
 * SQLSTATE code. A handler that returns `undefined`, and an error no handler
 * matches, throw a `DbException`.
 */
export function matchDbError(
  matchers: DbErrorMatchers,
): (error: DbError) => unknown {
  return (error) => {
    const byCode =
      error.code === undefined || !matchers.codes
        ? undefined
        : Object.hasOwn(matchers.codes, error.code)
          ? matchers.codes[error.code]
          : undefined;

    const mapped = byCode?.(error) ?? kindHandler(matchers, error)?.(error);

    return mapped ?? new DbException(error);
  };
}

function kindHandler(
  matchers: DbErrorMatchers,
  error: DbError,
): ((error: DbError) => unknown) | undefined {
  if (!Object.hasOwn(matchers, error.kind)) {
    return undefined;
  }

  // SAFETY: the handler under a kind key takes that kind's error, which is
  // the narrowed `error` here.
  return matchers[error.kind] as ((error: DbError) => unknown) | undefined;
}

/** Raw error shape shared by PostgREST responses and `pg` errors. */
export interface RawDbError {
  readonly message?: string;
  readonly code?: string;
  readonly details?: string | null;
  readonly hint?: string | null;
  readonly constraint?: string;
  readonly column?: string;
  readonly table?: string;
  readonly name?: string;
  /**
   * Milliseconds until a retry can succeed, from `@supabase/server`'s pool
   * errors.
   */
  readonly retryAfterMs?: number;
}

export type ErrorMapper = (
  raw: RawDbError,
  fallback: DbError,
) => DbError | undefined;

const CONSTRAINT_IN_MESSAGE = /constraint "([^"]+)"/;
const KEY_COLUMNS_IN_DETAILS = /^Key \(([^)]+)\)=/;
const COLUMN_IN_MESSAGE = /column "([^"]+)"/;
const RETRY_AFTER = /retry after (\d+)/i;

const PERMISSION_DENIED =
  /^permission denied for (table|view|sequence|function|schema) (\S+)/;

/**
 * The SQL compiler fails a write past `maxAffected` by casting this text,
 * followed by `:<rows>`, to an integer: plain SQL has no `raise`.
 */
export const MAX_AFFECTED_MARKER = "better_supabase:max_affected";
const MAX_AFFECTED_COUNT = /better_supabase:max_affected:(\d+)/;

function constraintOf(raw: RawDbError): string | undefined {
  return raw.constraint ?? CONSTRAINT_IN_MESSAGE.exec(raw.message ?? "")?.[1];
}

/**
 * The hint `better_supabase.check_json_schema()` raises with (the
 * `jsonb-schemas` module).
 */
const JSON_SCHEMA_HINT = "JSON_SCHEMA_INVALID";

/**
 * The prefix of the `jsonb-schemas` check constraints and triggers. `bs_json_`
 * is the name before 0.15, which databases keep until `upgrade` runs.
 */
const JSON_SCHEMA_CONSTRAINT = /^bsb?_json_/;
const JSON_SCHEMA_COLUMN = /^[\w$]+\.([\w$]+) does not match its JSON Schema/;

/**
 * One issue per pg_jsonschema error in DETAIL (a JSON array of strings), at the
 * column's database name. Without the list (the check constraint itself
 * failed), one issue for the whole value.
 */
function jsonSchemaIssues(raw: RawDbError): readonly ValidationIssue[] {
  const column = raw.column ?? JSON_SCHEMA_COLUMN.exec(raw.message ?? "")?.[1];
  const path = column === undefined ? {} : { path: [column] };
  let errors: unknown;

  try {
    errors = JSON.parse(raw.details ?? "");
  } catch {
    errors = undefined;
  }

  const messages = Array.isArray(errors)
    ? errors.filter((entry): entry is string => typeof entry === "string")
    : [];

  return messages.length > 0
    ? messages.map((message) => ({ message, ...path }))
    : [{ message: "The value does not match its JSON Schema", ...path }];
}

function columnsOf(raw: RawDbError): readonly string[] | undefined {
  const match = KEY_COLUMNS_IN_DETAILS.exec(raw.details ?? "");

  return match?.[1]?.split(",").map((column) => column.trim());
}

function optional(raw: RawDbError): {
  code?: string;
  details?: string;
  hint?: string;
} {
  const out: { code?: string; details?: string; hint?: string } = {};

  if (raw.code) {
    out.code = raw.code;
  }

  if (raw.details) {
    out.details = raw.details;
  }

  if (raw.hint) {
    out.hint = raw.hint;
  }

  return out;
}

/**
 * The `permissions` a `42501` raised with `detail = '{"permissions": [...]}'`
 * names, so a refusal from SQL carries the keys the caller lacks.
 */
function permissionsOf(details: string | undefined): {
  permissions?: readonly string[];
} {
  if (details === undefined || !details.startsWith("{")) {
    return {};
  }

  let parsed: unknown;

  try {
    parsed = JSON.parse(details);
  } catch {
    return {};
  }

  if (typeof parsed !== "object" || parsed === null) {
    return {};
  }

  const permissions = "permissions" in parsed ? parsed.permissions : undefined;

  return Array.isArray(permissions) &&
    permissions.every((key) => typeof key === "string")
    ? { permissions }
    : {};
}

function isInputField(value: unknown): value is InputField {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  // SAFETY: value is a non-null object here, and each member is checked below.
  const { path, code, message } = value as Record<string, unknown>;

  return (
    Array.isArray(path) &&
    path.every((key) => typeof key === "string" || typeof key === "number") &&
    typeof code === "string" &&
    typeof message === "string"
  );
}

/**
 * The `fields` an input check in SQL raised with `detail = '{"fields":
 * [{"path": ["name"], "code": "NAME_REQUIRED", "message": "..."}]}'` names, so
 * a rejection from SQL places its message like one from TypeScript.
 */
function fieldsOf(details: string | undefined): {
  fields?: readonly InputField[];
} {
  if (details === undefined || !details.startsWith("{")) {
    return {};
  }

  let parsed: unknown;

  try {
    parsed = JSON.parse(details);
  } catch {
    return {};
  }

  const fields =
    typeof parsed === "object" && parsed !== null && "fields" in parsed
      ? parsed.fields
      : undefined;

  return Array.isArray(fields) &&
    fields.length > 0 &&
    fields.every(isInputField)
    ? { fields }
    : {};
}

/** Adds the operation's limit to a `max_affected` error that doesn't name it. */
export function withMaxAffected(
  error: DbError,
  maxAffected: number | undefined,
): DbError {
  return error.kind === "max_affected" &&
    maxAffected !== undefined &&
    error.maxAffected === undefined
    ? { ...error, maxAffected }
    : error;
}

/**
 * Maps a PostgREST or Postgres error to a `DbError`. Custom mappers run first;
 * the first one that returns an error wins.
 */
export function mapDbError(
  raw: RawDbError,
  mappers: readonly ErrorMapper[] = [],
): DbError {
  const fallback = mapBuiltin(raw);

  for (const mapper of mappers) {
    const mapped = mapper(raw, fallback);

    if (mapped) {
      return mapped;
    }
  }

  return fallback;
}

function mapBuiltin(raw: RawDbError): DbError {
  const message = raw.message ?? "Unknown database error";
  const base = optional(raw);
  const code = raw.code ?? "";

  if (
    raw.name === "AbortError" ||
    code === "20" ||
    message.startsWith("AbortError:")
  ) {
    return dbError("aborted", message, base);
  }

  switch (code) {
    case "23505": {
      const extra: DbErrorKinds["conflict"] = {};
      const constraint = constraintOf(raw);
      const columns = columnsOf(raw);

      if (constraint) {
        extra.constraint = constraint;
      }

      if (columns) {
        extra.columns = columns;
      }

      return dbError("conflict", message, { ...base, ...extra });
    }

    case "BS409": {
      // The SQLSTATE of `STALE_WRITE` (src/core/stale-write.ts).
      return dbError("conflict", message, base);
    }

    case "23503": {
      const extra: DbErrorKinds["foreign_key"] = {};
      const constraint = constraintOf(raw);
      const columns = columnsOf(raw);

      if (constraint) {
        extra.constraint = constraint;
      }

      if (columns) {
        extra.columns = columns;
      }

      return dbError("foreign_key", message, { ...base, ...extra });
    }

    case "23514": {
      const constraint = constraintOf(raw);

      if (
        base.hint === JSON_SCHEMA_HINT ||
        (constraint !== undefined && JSON_SCHEMA_CONSTRAINT.test(constraint))
      ) {
        return dbError("validation", message, {
          ...base,
          issues: jsonSchemaIssues(raw),
        });
      }

      return dbError("check", message, {
        ...base,
        ...(constraint ? { constraint } : {}),
      });
    }

    case "23502": {
      const column = raw.column ?? COLUMN_IN_MESSAGE.exec(message)?.[1];

      return dbError("not_null", message, {
        ...base,
        ...(column ? { column } : {}),
      });
    }

    case "23P01": {
      const constraint = constraintOf(raw);

      return dbError("exclusion", message, {
        ...base,
        ...(constraint ? { constraint } : {}),
      });
    }

    case "42501": {
      const object = PERMISSION_DENIED.exec(message);
      const postgrestHint = base.hint?.startsWith("Grant the required");

      if (!object || (base.hint && !postgrestHint)) {
        return dbError("forbidden", message, {
          ...base,
          ...permissionsOf(base.details),
        });
      }

      // The object name and PostgREST's GRANT recipe stay in `details`, which
      // Problem Details never sends to the client.
      const advice =
        object[1] === "table" || object[1] === "view"
          ? `The Data API role has no grant on this ${object[1]}, as on a project with default privileges turned off: add it to \`expose\` and run \`better-supabase add grants\`. \`better-supabase doctor\` (BS106) lists every missing grant.`
          : `The Data API role has no ${object[1] === "function" ? "execute" : "usage"} grant on this ${object[1]}; grant it to the role that needs it.`;

      const details = [message, base.details, postgrestHint ? base.hint : ""]
        .filter(Boolean)
        .join("\n");

      return dbError("forbidden", "permission denied", {
        ...base,
        details,
        hint: advice,
      });
    }

    case "25006": {
      return dbError(
        "forbidden",
        "This connection is read-only, so the write was refused",
        {
          ...base,
          details: base.details ?? message,
          hint:
            base.hint ??
            "The transaction is read-only, such as in a read-only support session; writes need a writable connection.",
        },
      );
    }

    case "P0001": {
      return dbError("raised", message, base);
    }

    case "P0002": {
      return dbError("not_found", message, base);
    }

    case "57014": {
      return dbError("timeout", message, base);
    }

    case "40001":
    case "40P01": {
      return dbError("serialization", message, base);
    }

    case "PGRST116": {
      return /multiple|more than one/i.test(raw.details ?? message)
        ? dbError("multiple_rows", message, base)
        : dbError("not_found", message, base);
    }

    case "PGRST301":
    case "PGRST302":
    case "PGRST303": {
      return dbError("unauthorized", message, base);
    }

    case "PGRST124": {
      return dbError("max_affected", message, base);
    }

    case "22P02": {
      if (message.includes(MAX_AFFECTED_MARKER)) {
        const affected = MAX_AFFECTED_COUNT.exec(message)?.[1];

        return dbError(
          "max_affected",
          `The write affects ${affected ?? "more"} rows, more than maxAffected allows`,
          { code: "22P02" },
        );
      }

      break;
    }

    case "PGRST123": {
      return dbError("invalid_request", message, {
        ...base,
        hint:
          base.hint ??
          "PostgREST aggregates are off. Run `alter role authenticator set pgrst.db_aggregates_enabled = 'true'; notify pgrst, 'reload config';` (see BS210), or use better-supabase/postgres.",
      });
    }

    case "BS429":
    case "PT429": {
      const seconds = RETRY_AFTER.exec(raw.details ?? "")?.[1];

      return dbError("rate_limited", message, {
        ...base,
        ...(seconds ? { retryAfter: Number(seconds) } : {}),
      });
    }

    case "POSTGRES_POOL_BUSY":
    case "POSTGRES_CONNECT_PAUSED": {
      return dbError("network", message, {
        ...base,
        ...(raw.retryAfterMs === undefined
          ? {}
          : { retryAfter: Math.max(1, Math.ceil(raw.retryAfterMs / 1000)) }),
      });
    }

    case "BSQ29": {
      return dbError("quota_exceeded", message, {
        ...base,
        ...quotaDetails(raw.details),
      });
    }

    default: {
      break;
    }
  }

  if (code.startsWith("22")) {
    return dbError("invalid_input", message, {
      ...base,
      ...fieldsOf(base.details),
    });
  }

  if (code.startsWith("PGRST1") || code.startsWith("PGRST2")) {
    return dbError("invalid_request", message, base);
  }

  if (code.startsWith("08") || /fetch failed|network/i.test(message)) {
    return dbError("network", message, base);
  }

  return dbError("unexpected", message, base);
}

/** `consume_quota` puts `{ meter, limit, retry_after }` in the error's DETAIL. */
function quotaDetails(details: string | null | undefined): {
  meter?: string;
  limit?: number;
  retryAfter?: number;
} {
  let parsed: unknown;

  try {
    parsed = JSON.parse(details ?? "");
  } catch {
    return {};
  }

  if (typeof parsed !== "object" || parsed === null) {
    return {};
  }

  // SAFETY: parsed is a non-null object, and each field read is type-checked below.
  const record = parsed as Record<string, unknown>;
  const field = (key: string): unknown => record[key];
  const meter = field("meter");
  const limit = field("limit");
  const retryAfter = field("retry_after");

  return {
    ...(typeof meter === "string" ? { meter } : {}),
    ...(typeof limit === "number" ? { limit } : {}),
    ...(typeof retryAfter === "number" ? { retryAfter } : {}),
  };
}
