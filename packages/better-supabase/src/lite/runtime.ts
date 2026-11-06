import { importOptionalPeer } from "../core/optional-peer.ts";

/**
 * The parts of `@supabase/lite` that `liteStack()` uses, typed structurally so
 * the optional peer stays out of the published types.
 */
export interface LiteConnection {
  createMigrator(sql: string): { migrate(): Promise<unknown> };
  translateDdl(sql: string): Promise<unknown>;
  transaction(statements: string[]): Promise<void>;
  close(): Promise<void>;
}

export interface PgliteConnection extends LiteConnection {
  /**
   * The PGlite instance: `exec` runs several statements, `query` returns `{
   * rows }`.
   */
  readonly driver: {
    exec(sql: string): Promise<unknown>;
    query(
      sql: string,
      params?: readonly unknown[],
    ): Promise<{ rows: unknown[] }>;
  };
}

export interface LiteAppConfig {
  readonly connection: LiteConnection;
  readonly auth: {
    readonly enabled: boolean;
    readonly jwt_secret: string;
    readonly publishable_key?: string;
    readonly secret_key?: string;
  };
}

export interface LiteApp {
  init(): Promise<unknown>;
  fetch(request: Request): Promise<Response>;
}

export interface LiteRuntime {
  readonly App: new (config: LiteAppConfig) => LiteApp;
  createPgliteConnection(): Promise<PgliteConnection>;
  createSqliteConnection(url: string): Promise<LiteConnection>;
}

export const LITE_INSTALL =
  "Supabase Lite is an optional peer: install it with `pnpm add -D @supabase/lite`";

/**
 * `@supabase/lite` is an optional peer, loaded through `importOptionalPeer` so
 * bundlers leave it out (a literal specifier, even in a `const`, is resolved by
 * Turbopack). A missing install returns `undefined` so callers can say how to
 * add it.
 */
export async function loadLite(): Promise<LiteRuntime | undefined> {
  const [root, pg, sq] = await Promise.all([
    importOptionalPeer("@supabase/lite"),
    importOptionalPeer("@supabase/lite/pglite"),
    importOptionalPeer("@supabase/lite/sqlite"),
  ]);

  if (root === undefined || pg === undefined || sq === undefined) {
    return undefined;
  }

  // SAFETY: @supabase/lite 0.11 exports `App` with this shape.
  const { App } = root as { readonly App: LiteRuntime["App"] };

  // SAFETY: @supabase/lite/pglite 0.11 exports `createPgliteConnection`.
  const pglite = pg as { createPgliteConnection(): Promise<PgliteConnection> };

  // SAFETY: @supabase/lite/sqlite 0.11 exports `createConnection`.
  const sqlite = sq as {
    createConnection(config: { url: string }): Promise<LiteConnection>;
  };

  return {
    App,
    createPgliteConnection: () => pglite.createPgliteConnection(),
    createSqliteConnection: (url) => sqlite.createConnection({ url }),
  };
}

/**
 * The Supabase tables block policies are written on, which a Supabase project
 * always has and Lite does not: Realtime's `messages` with `topic()`, and
 * Storage's `objects`. Module files create their policies on them without a
 * guard.
 */
export const LITE_PLATFORM_SQL: Readonly<
  Record<"realtime" | "storage", string>
> = {
  realtime: `create schema if not exists realtime;
create table if not exists realtime.messages (
  id bigint generated always as identity primary key,
  topic text not null default '',
  extension text not null default 'broadcast',
  payload jsonb,
  private boolean default false,
  inserted_at timestamp not null default now()
);
alter table realtime.messages enable row level security;
create or replace function realtime.topic() returns text
language sql stable
as $$ select nullif(current_setting('realtime.topic', true), '') $$;`,
  storage: `create schema if not exists storage;
create table if not exists storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text,
  name text,
  owner uuid,
  metadata jsonb
);
alter table storage.objects enable row level security;`,
};

/** The table of each schema a shim creates. */
const SHIM_TABLES = {
  realtime: "realtime.messages",
  storage: "storage.objects",
} as const;

/** The shims `parts` need: a platform table it uses and does not create itself. */
function platformShims(parts: readonly string[]): string[] {
  return (["realtime", "storage"] as const)
    .filter(
      (schema) =>
        parts.some((part) => new RegExp(`\\b${schema}\\.`, "u").test(part)) &&
        !parts.some((part) =>
          new RegExp(
            `create table (?:if not exists )?${SHIM_TABLES[schema].replace(".", "\\.")}\\b`,
            "iu",
          ).test(part),
        ),
    )
    .map((schema) => LITE_PLATFORM_SQL[schema]);
}

const isPglite = (connection: LiteConnection): boolean =>
  "driver" in connection;

/** Applies migrations, then declarative schemas, with Lite's migrator. */
export async function migrateLite(
  connection: LiteConnection,
  sql: readonly string[],
): Promise<void> {
  const parts = sql.filter((part) => part.trim() !== "");

  const ddl = (
    isPglite(connection) ? [...platformShims(parts), ...parts] : parts
  ).join("\n;\n");

  if (ddl !== "") {
    await connection.createMigrator(ddl).migrate();
  }
}

/** Runs seed SQL: as is on PGlite, translated to SQLite on `sqlite-postgres`. */
export async function seedLite(
  target:
    | { readonly driver: "pglite"; readonly connection: PgliteConnection }
    | {
        readonly driver: "sqlite-postgres";
        readonly connection: LiteConnection;
      },
  sql: string,
): Promise<void> {
  if (sql.trim() === "") {
    return;
  }

  if (target.driver === "pglite") {
    await target.connection.driver.exec(sql);

    return;
  }

  const { connection } = target;
  const translated = await connection.translateDdl(sql);

  const statements =
    typeof translated === "string"
      ? translated
      : typeof translated === "object" &&
          translated !== null &&
          "ddl" in translated &&
          typeof translated.ddl === "string"
        ? translated.ddl
        : "";

  if (statements !== "") {
    await connection.transaction([statements]);
  }
}
