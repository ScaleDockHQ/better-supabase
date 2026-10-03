/** The subset of `pg.Client` the CLI uses. */
export interface PgQueryable {
  query<R = Record<string, unknown>>(
    text: string,
    values?: readonly unknown[],
  ): Promise<{ rows: R[] }>;
}

interface PgEvents {
  on?(event: "error", listener: (error: unknown) => void): unknown;
}

interface PgClient extends PgQueryable, PgEvents {
  connect(): Promise<unknown>;
  end(): Promise<void>;
}

interface PgPool extends PgQueryable, PgEvents {
  connect(): Promise<{ release(): void }>;
  end(): Promise<void>;
}

interface PgOptions {
  readonly connectionString: string;
  readonly connectionTimeoutMillis: number;
  readonly statement_timeout?: number;
}

interface PgModule {
  Client: new (options: PgOptions) => PgClient;
  Pool?: new (options: PgOptions & { readonly max: number }) => PgPool;
}

export interface ConnectOptions {
  /** Opens a pool of this many connections, for callers that query concurrently. */
  readonly pool?: number;
  /** Server-side limit for each statement, in milliseconds. */
  readonly statementTimeout?: number;
  /** Ends the connection when aborted, so Ctrl-C stops a running query. */
  readonly signal?: AbortSignal;
}

/** A connection that queues its queries, or a pool that runs them concurrently. */
export interface PgConnection {
  readonly client: PgQueryable;
  readonly pooled?: boolean;
  close: () => Promise<void>;
  describe: string;
}

const CONNECT_TIMEOUT_MS = 10_000;

const loadPg = (): Promise<unknown> => import("pg");

/** Opens a `pg` connection. `pg` is an optional peer, loaded on demand. */
export async function connect(
  url: string,
  load: () => Promise<unknown> = loadPg,
  options: ConnectOptions = {},
): Promise<PgConnection> {
  let pg: PgModule;
  try {
    // SAFETY: pg is an optional peer loaded without its types.
    const mod = (await load()) as {
      default?: PgModule;
    } & PgModule;
    pg = mod.default ?? mod;
  } catch {
    throw new Error(
      'better-supabase needs the "pg" package to read your database. Install it: pnpm add -D pg',
    );
  }
  options.signal?.throwIfAborted();
  const settings: PgOptions = {
    connectionString: url,
    connectionTimeoutMillis: CONNECT_TIMEOUT_MS,
    ...(options.statementTimeout === undefined
      ? {}
      : { statement_timeout: options.statementTimeout }),
  };
  const pool =
    options.pool === undefined || pg.Pool === undefined
      ? undefined
      : new pg.Pool({ ...settings, max: options.pool });
  const client: PgPool | PgClient = pool ?? new pg.Client(settings);
  const pooled = pool !== undefined;
  // An unhandled "error" event (the server restarting under `gen --watch`)
  // would crash the process; the next query reports the failure instead.
  client.on?.("error", () => undefined);
  let ended: Promise<void> | undefined;
  const close = (): Promise<void> => (ended ??= client.end());
  const onAbort = (): void => void close().catch(() => undefined);
  try {
    if (pool) (await pool.connect()).release();
    else await client.connect();
  } catch (cause) {
    await close().catch(() => undefined);
    const message = cause instanceof Error ? cause.message : String(cause);
    throw new Error(
      `Could not connect to ${redact(url)}: ${message}. Is the local stack running (supabase start)?`,
      { cause },
    );
  }
  options.signal?.addEventListener("abort", onAbort, { once: true });
  return {
    client,
    ...(pooled ? { pooled } : {}),
    close: () => {
      options.signal?.removeEventListener("abort", onAbort);
      return close();
    },
    describe: redact(url),
  };
}

function redact(url: string): string {
  return url.replace(/\/\/([^:@/]+):([^@/]+)@/, "//$1:***@");
}
