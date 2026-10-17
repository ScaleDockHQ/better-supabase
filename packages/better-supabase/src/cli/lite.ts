import type { LiteDriver } from "../server/index.ts";

/** The parts of `@supabase/lite` that `gen` and `doctor` use, typed structurally. */
export interface CliLiteConnection {
  createMigrator(sql: string): { migrate(): Promise<unknown> };
  close(): Promise<void>;
  readonly driver: {
    query(sql: string): Promise<{ rows: unknown[] }>;
  };
}

export interface CliLite {
  readonly App: new (config: {
    readonly connection: CliLiteConnection;
    readonly auth: { readonly enabled: boolean; readonly jwt_secret: string };
  }) => { init(): Promise<unknown> };
  createPgliteConnection(): Promise<CliLiteConnection>;
}

export const LITE_DRIVERS: readonly LiteDriver[] = [
  "sqlite-postgres",
  "sqlite",
  "pglite",
  "postgres",
];

/** The drivers that store data in SQLite, where Lite has no `rpc()`. */
export function isSqliteLiteDriver(driver: LiteDriver): boolean {
  return driver === "sqlite-postgres" || driver === "sqlite";
}

/**
 * `@supabase/lite` is an optional peer, imported through variable specifiers
 * so the CLI build leaves it out; `undefined` when it is not installed.
 */
export async function loadCliLite(): Promise<CliLite | undefined> {
  const root = "@supabase/lite";
  const pglite = "@supabase/lite/pglite";

  try {
    // SAFETY: @supabase/lite 0.11 exports `App` and `createPgliteConnection`
    // with these shapes; the catch covers a missing install.
    const [{ App }, pg] = (await Promise.all([
      import(root),
      import(pglite),
    ])) as [
      { readonly App: CliLite["App"] },
      { createPgliteConnection(): Promise<CliLiteConnection> },
    ];

    return { App, createPgliteConnection: () => pg.createPgliteConnection() };
  } catch {
    return undefined;
  }
}
