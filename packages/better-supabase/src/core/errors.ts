/**
 * Extra fields carried by each error kind. Plugins can add kinds through the
 * `errors` extension point; apps that want the new kinds in the union can add
 * them to this interface.
 */
export interface DbErrorKinds {
  not_found: Record<never, never>;
  unauthorized: Record<never, never>;
  /** `required`: the assurance level the route needs, when a second factor is missing. */
  forbidden: { required?: 'aal1' | 'aal2' };
  conflict: { constraint?: string; columns?: readonly string[] };
  foreign_key: { constraint?: string; columns?: readonly string[] };
  check: { constraint?: string };
  not_null: { column?: string };
  exclusion: { constraint?: string };
  invalid_input: Record<never, never>;
  raised: Record<never, never>;
  timeout: Record<never, never>;
  serialization: Record<never, never>;
  network: Record<never, never>;
  aborted: Record<never, never>;
  invalid_request: Record<never, never>;
  validation: { issues: readonly ValidationIssue[] };
  multiple_rows: Record<never, never>;
  stale: Record<never, never>;
  /** `retryAfter`: seconds until the window resets (the `Retry-After` header). */
  rate_limited: { retryAfter?: number };
  unexpected: Record<never, never>;
}

export type DbErrorKind = keyof DbErrorKinds;

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
  raised: 400,
  timeout: 504,
  serialization: 409,
  network: 503,
  aborted: 499,
  invalid_request: 400,
  validation: 422,
  multiple_rows: 409,
  stale: 412,
  rate_limited: 429,
  unexpected: 500,
};

export function statusOf(kind: DbErrorKind): number {
  return STATUS[kind];
}

type ExtraOf<K extends DbErrorKind> =
  Record<never, never> extends DbErrorKinds[K]
    ? [extra?: DbErrorKinds[K] & Partial<Omit<DbErrorBase<K>, 'kind'>>]
    : [extra: DbErrorKinds[K] & Partial<Omit<DbErrorBase<K>, 'kind'>>];

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
      if (value !== undefined) error[key] = value;
    }
  }
  return error as unknown as DbErrorOf<K>;
}

export function isDbError(value: unknown): value is DbError {
  return (
    typeof value === 'object' &&
    value !== null &&
    typeof (value as { kind?: unknown }).kind === 'string' &&
    typeof (value as { message?: unknown }).message === 'string' &&
    typeof (value as { status?: unknown }).status === 'number'
  );
}

/**
 * The `DbError` in a `DbError`, a `DbException`, or an error whose `cause`
 * is a `DbError` (what `sb.mapError()` mappers should set).
 */
export function dbErrorOf(value: unknown): DbError | undefined {
  if (value instanceof DbException) return value.error;
  if (value instanceof Error && isDbError(value.cause)) return value.cause;
  return isDbError(value) ? value : undefined;
}

function constraintGuard<K extends 'conflict' | 'check' | 'foreign_key'>(
  kind: K,
) {
  return <C extends string = string>(
    error: unknown,
    constraint?: NoInfer<C>,
  ): error is DbErrorOf<K> & { readonly constraint: C } => {
    const found = dbErrorOf(error);
    if (found?.kind !== kind) return false;
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
) => error is DbErrorOf<'conflict'> & { readonly constraint: C } =
  constraintGuard('conflict');

/** A CHECK violation, optionally for one constraint (`CheckConstraint`). */
export const isCheck: <C extends string = string>(
  error: unknown,
  constraint?: NoInfer<C>,
) => error is DbErrorOf<'check'> & { readonly constraint: C } =
  constraintGuard('check');

/** A foreign key violation, optionally for one constraint (`ForeignKeyConstraint`). */
export const isForeignKey: <C extends string = string>(
  error: unknown,
  constraint?: NoInfer<C>,
) => error is DbErrorOf<'foreign_key'> & { readonly constraint: C } =
  constraintGuard('foreign_key');

/** Thrown by `.orThrow()`. Carries the plain `DbError` as `error`. */
export class DbException extends Error {
  override readonly name = 'DbException';
  readonly error: DbError;

  constructor(error: DbError) {
    super(error.message);
    this.error = error;
  }

  get kind(): DbErrorKind {
    return this.error.kind;
  }
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

function constraintOf(raw: RawDbError): string | undefined {
  return raw.constraint ?? CONSTRAINT_IN_MESSAGE.exec(raw.message ?? '')?.[1];
}

function columnsOf(raw: RawDbError): readonly string[] | undefined {
  const match = KEY_COLUMNS_IN_DETAILS.exec(raw.details ?? '');
  return match?.[1]?.split(',').map((column) => column.trim());
}

function optional(raw: RawDbError): {
  code?: string;
  details?: string;
  hint?: string;
} {
  const out: { code?: string; details?: string; hint?: string } = {};
  if (raw.code) out.code = raw.code;
  if (raw.details) out.details = raw.details;
  if (raw.hint) out.hint = raw.hint;
  return out;
}

/**
 * Maps a PostgREST or Postgres error to a `DbError`. Custom mappers run
 * first; the first one that returns an error wins.
 */
export function mapDbError(
  raw: RawDbError,
  mappers: readonly ErrorMapper[] = [],
): DbError {
  const fallback = mapBuiltin(raw);
  for (const mapper of mappers) {
    const mapped = mapper(raw, fallback);
    if (mapped) return mapped;
  }
  return fallback;
}

function mapBuiltin(raw: RawDbError): DbError {
  const message = raw.message ?? 'Unknown database error';
  const base = optional(raw);
  const code = raw.code ?? '';

  if (
    raw.name === 'AbortError' ||
    code === '20' ||
    message.startsWith('AbortError:')
  ) {
    return dbError('aborted', message, base);
  }

  switch (code) {
    case '23505': {
      const extra: DbErrorKinds['conflict'] = {};
      const constraint = constraintOf(raw);
      const columns = columnsOf(raw);
      if (constraint) extra.constraint = constraint;
      if (columns) extra.columns = columns;
      return dbError('conflict', message, { ...base, ...extra });
    }
    case '23503': {
      const extra: DbErrorKinds['foreign_key'] = {};
      const constraint = constraintOf(raw);
      const columns = columnsOf(raw);
      if (constraint) extra.constraint = constraint;
      if (columns) extra.columns = columns;
      return dbError('foreign_key', message, { ...base, ...extra });
    }
    case '23514': {
      const constraint = constraintOf(raw);
      return dbError('check', message, {
        ...base,
        ...(constraint ? { constraint } : {}),
      });
    }
    case '23502': {
      const column = raw.column ?? COLUMN_IN_MESSAGE.exec(message)?.[1];
      return dbError('not_null', message, {
        ...base,
        ...(column ? { column } : {}),
      });
    }
    case '23P01': {
      const constraint = constraintOf(raw);
      return dbError('exclusion', message, {
        ...base,
        ...(constraint ? { constraint } : {}),
      });
    }
    case '42501': {
      const object = PERMISSION_DENIED.exec(message);
      const postgrestHint = base.hint?.startsWith('Grant the required');
      if (!object || (base.hint && !postgrestHint))
        return dbError('forbidden', message, base);
      const advice =
        object[1] === 'table' || object[1] === 'view'
          ? `Supabase no longer grants new tables to the Data API roles: add ${object[2]} to \`expose\` and run \`better-supabase sql add grants\`. \`better-supabase doctor\` (BS106) lists every missing grant.`
          : `Supabase no longer grants new objects to the Data API roles automatically; grant ${object[1] === 'function' ? 'execute' : 'usage'} on ${object[1]} ${object[2]} to the role that needs it.`;
      return dbError('forbidden', message, {
        ...base,
        hint: postgrestHint ? `${base.hint} ${advice}` : advice,
      });
    }
    case 'P0001':
      return dbError('raised', message, base);
    case '57014':
      return dbError('timeout', message, base);
    case '40001':
    case '40P01':
      return dbError('serialization', message, base);
    case 'PGRST116':
      return /multiple|more than one/i.test(raw.details ?? message)
        ? dbError('multiple_rows', message, base)
        : dbError('not_found', message, base);
    case 'PGRST301':
    case 'PGRST302':
    case 'PGRST303':
      return dbError('unauthorized', message, base);
    case 'PGRST123':
      return dbError('invalid_request', message, {
        ...base,
        hint:
          base.hint ??
          "PostgREST aggregates are off. Run `alter role authenticator set pgrst.db_aggregates_enabled = 'true'; notify pgrst, 'reload config';` (see BS210), or use better-supabase/postgres.",
      });
    case 'BS429':
    case 'PT429': {
      const seconds = RETRY_AFTER.exec(raw.details ?? '')?.[1];
      return dbError('rate_limited', message, {
        ...base,
        ...(seconds ? { retryAfter: Number(seconds) } : {}),
      });
    }
    default:
      break;
  }

  if (code.startsWith('22')) return dbError('invalid_input', message, base);
  if (code.startsWith('PGRST1') || code.startsWith('PGRST2')) {
    return dbError('invalid_request', message, base);
  }
  if (code.startsWith('08') || /fetch failed|network/i.test(message)) {
    return dbError('network', message, base);
  }
  return dbError('unexpected', message, base);
}
