/** The subset of `pg.Client` the CLI uses. */
export interface PgQueryable {
  query<R = Record<string, unknown>>(
    text: string,
    values?: readonly unknown[],
  ): Promise<{ rows: R[] }>;
}

interface PgClient extends PgQueryable {
  connect(): Promise<unknown>;
  end(): Promise<void>;
}

interface PgModule {
  Client: new (options: { connectionString: string }) => PgClient;
}

/** Opens a `pg` connection. `pg` is an optional peer, loaded on demand. */
export async function connect(url: string): Promise<{
  client: PgQueryable;
  close: () => Promise<void>;
  describe: string;
}> {
  let pg: PgModule;
  try {
    // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- pg is an optional peer loaded without its types.
    const mod = (await import("pg")) as unknown as {
      default?: PgModule;
    } & PgModule;
    pg = mod.default ?? mod;
  } catch {
    throw new Error(
      'better-supabase needs the "pg" package to read your database. Install it: pnpm add -D pg',
    );
  }
  const client = new pg.Client({ connectionString: url });
  try {
    await client.connect();
  } catch (cause) {
    const message = cause instanceof Error ? cause.message : String(cause);
    throw new Error(
      `Could not connect to ${redact(url)}: ${message}. Is the local stack running (supabase start)?`,
      { cause },
    );
  }
  return { client, close: () => client.end(), describe: redact(url) };
}

function redact(url: string): string {
  return url.replace(/\/\/([^:@/]+):([^@/]+)@/, "//$1:***@");
}
