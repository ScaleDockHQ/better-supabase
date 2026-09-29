import {
  type DbError,
  type DbErrorKind,
  type DbErrorKinds,
  dbError,
  type ValidationIssue,
} from './errors.ts';

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
  readonly required?: 'aal1' | 'aal2';
}

export const PROBLEM_TYPE_BASE = 'https://bettersupabase.com/problems/';
export const PROBLEM_CONTENT_TYPE = 'application/problem+json';

const TITLES: { readonly [K in DbErrorKind]: string } = {
  not_found: 'Not found',
  unauthorized: 'Unauthorized',
  forbidden: 'Forbidden',
  conflict: 'Conflict',
  foreign_key: 'Referenced row missing or still referenced',
  check: 'Check constraint violated',
  not_null: 'Required value missing',
  exclusion: 'Exclusion constraint violated',
  invalid_input: 'Invalid input',
  raised: 'Request rejected',
  timeout: 'Timed out',
  serialization: 'Concurrent update, retry',
  network: 'Database unreachable',
  aborted: 'Aborted',
  invalid_request: 'Invalid request',
  validation: 'Validation failed',
  multiple_rows: 'More than one row matched',
  stale: 'Row changed since it was read',
  unexpected: 'Unexpected error',
};

/** Kinds whose message may contain internals (SQL, hostnames), hidden unless `expose` is set. */
const INTERNAL = new Set<DbErrorKind>([
  'unexpected',
  'network',
  'invalid_request',
]);

export interface ProblemOptions {
  /** URI reference for this occurrence, e.g. the request path. */
  readonly instance?: string;
  /** Include messages of internal errors. Defaults to false. */
  readonly expose?: boolean;
}

export interface ProblemResponseOptions extends ProblemOptions {
  readonly headers?: HeadersInit;
  /** `realm` of the RFC 6750 challenge on 401. */
  readonly realm?: string;
}

/** Converts a `DbError` to Problem Details. */
export function toProblem(
  error: DbError,
  options: ProblemOptions = {},
): ProblemDetails {
  const problem: Record<string, unknown> = {
    type: `${PROBLEM_TYPE_BASE}${error.kind.replace(/_/g, '-')}`,
    title: TITLES[error.kind],
    status: error.status,
    kind: error.kind,
  };
  if (!INTERNAL.has(error.kind) || options.expose)
    problem['detail'] = error.message;
  if (options.instance) problem['instance'] = options.instance;
  if (error.code) problem['code'] = error.code;
  if (error.hint) problem['hint'] = error.hint;
  if ('constraint' in error && error.constraint)
    problem['constraint'] = error.constraint;
  if ('columns' in error && error.columns) problem['columns'] = error.columns;
  if ('column' in error && error.column) problem['column'] = error.column;
  if ('issues' in error) problem['issues'] = error.issues;
  if ('required' in error && error.required)
    problem['required'] = error.required;
  return problem as unknown as ProblemDetails;
}

/**
 * An `application/problem+json` response. A 401 carries an RFC 6750
 * `WWW-Authenticate: Bearer` challenge.
 */
export function problemResponse(
  error: DbError,
  options: ProblemResponseOptions = {},
): Response {
  const headers = new Headers(options.headers);
  headers.set('content-type', PROBLEM_CONTENT_TYPE);
  if (error.status === 401 && !headers.has('www-authenticate')) {
    const realm = (options.realm ?? 'supabase').replace(/"/g, '');
    const params =
      error.code === 'MISSING_CREDENTIALS' ? '' : ', error="invalid_token"';
    headers.set('www-authenticate', `Bearer realm="${realm}"${params}`);
  }
  return new Response(JSON.stringify(toProblem(error, options)), {
    status: error.status,
    headers,
  });
}

export function isProblem(value: unknown): value is ProblemDetails {
  if (typeof value !== 'object' || value === null) return false;
  const problem = value as Record<string, unknown>;
  return (
    typeof problem['type'] === 'string' &&
    typeof problem['status'] === 'number' &&
    typeof problem['title'] === 'string'
  );
}

function isKind(value: unknown): value is DbErrorKind {
  return typeof value === 'string' && value in TITLES;
}

/** Turns a Problem Details body back into a `DbError` (client side). */
export function fromProblem(problem: ProblemDetails): DbError {
  const kind = isKind(problem.kind) ? problem.kind : 'unexpected';
  const extra: Record<string, unknown> = { status: problem.status };
  for (const key of [
    'code',
    'hint',
    'constraint',
    'columns',
    'column',
    'required',
  ] as const) {
    if (problem[key] !== undefined) extra[key] = problem[key];
  }
  extra['issues'] = problem.issues ?? [];
  if (kind !== 'validation') delete extra['issues'];
  return dbError(
    kind,
    problem.detail ?? problem.title,
    extra as DbErrorKinds['validation'],
  );
}
