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

/** Applies migrations, then declarative schemas, with Lite's migrator. */
export async function migrateLite(
  connection: LiteConnection,
  sql: readonly string[],
): Promise<void> {
  const ddl = sql.filter((part) => part.trim() !== "").join("\n;\n");

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
