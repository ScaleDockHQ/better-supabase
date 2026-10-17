import { existsSync } from "node:fs";
import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";

import type { LiteDriver } from "../../server/index.ts";
import type { IntrospectionSource } from "./source.ts";

import { connect } from "../db.ts";
import { CliError, errorText } from "../errors.ts";
import { LITE_DRIVERS, loadCliLite } from "../lite.ts";
import { schemaPaths, type SupabaseToml, tomlGet } from "../supabase-toml.ts";
import { pgSource } from "./source.ts";

function isLiteDriver(value: unknown): value is LiteDriver {
  return LITE_DRIVERS.some((driver) => driver === value);
}

/**
 * `[db] driver` from `supabase/config.toml`. Only Supabase Lite reads this
 * key, so its presence marks a Lite project.
 */
export function liteDriverOf(toml?: SupabaseToml): LiteDriver | undefined {
  const driver = tomlGet(toml?.document ?? {}, ["db", "driver"]);
  if (driver === undefined) {
    return undefined;
  }
  if (isLiteDriver(driver)) {
    return driver;
  }
  throw new CliError(
    "config_invalid",
    `[db] driver = ${JSON.stringify(driver)} in ${toml?.path ?? "supabase/config.toml"} is not a Supabase Lite driver (${LITE_DRIVERS.join(", ")}).`,
    { flag: "[db] driver" },
  );
}

/** `supabase/migrations/*.sql` in version order, then the declarative schema files. */
async function schemaSql(root: string, toml?: SupabaseToml): Promise<string[]> {
  const migrations = join(root, toml?.dir ?? "supabase", "migrations");
  const files = existsSync(migrations)
    ? (await readdir(migrations))
        .filter((name) => name.endsWith(".sql"))
        .sort()
        .map((name) => join(migrations, name))
    : [];
  const { files: schemas } = await schemaPaths(root, toml);
  return Promise.all(
    [...files, ...schemas.map((path) => join(root, path))].map((path) =>
      readFile(path, "utf-8"),
    ),
  );
}

/**
 * Where `gen` reads a Supabase Lite project's schema: the `postgres`
 * driver's `[db] url`, or, for `pglite` and `sqlite-postgres`, an in-memory
 * PGlite with Lite's auth schema that `supabase/migrations` and the
 * declarative schema files are replayed into.
 */
export async function liteSource(
  root: string,
  toml: SupabaseToml | undefined,
  driver: LiteDriver,
  open: typeof connect = connect,
): Promise<IntrospectionSource> {
  switch (driver) {
    case "postgres": {
      const url = tomlGet(toml?.document ?? {}, ["db", "url"]);
      if (typeof url !== "string" || !/^postgres(ql)?:\/\//.test(url)) {
        throw new CliError(
          "missing_value",
          'The Supabase Lite postgres driver needs [db] url = "postgres://..." in supabase/config.toml, or pass --db-url-stdin.',
          { flag: "[db] url" },
        );
      }
      return pgSource(url, open);
    }
    case "sqlite": {
      throw new CliError(
        "config_invalid",
        'gen reads Postgres DDL, and the bare sqlite driver takes native SQLite DDL. Switch to [db] driver = "sqlite-postgres" or "pglite", or save a snapshot with `better-supabase introspect`.',
        { flag: "[db] driver" },
      );
    }
    case "pglite":
    case "sqlite-postgres": {
      break;
    }
    default: {
      const exhaustive: never = driver;
      return exhaustive;
    }
  }
  const lite = await loadCliLite();
  if (!lite) {
    throw new CliError(
      "failed",
      "Reading a Supabase Lite project needs @supabase/lite: pnpm add -D @supabase/lite",
    );
  }
  const connection = await lite.createPgliteConnection();
  try {
    const app = new lite.App({
      connection,
      auth: { enabled: true, jwt_secret: "better-supabase-gen".repeat(2) },
    });
    await app.init();
    const ddl = (await schemaSql(root, toml))
      .filter((part) => part.trim() !== "")
      .join("\n;\n");
    if (ddl !== "") {
      await connection.createMigrator(ddl).migrate();
    }
  } catch (error) {
    await connection.close();
    throw new CliError(
      "failed",
      `Replaying the Supabase Lite schema into PGlite failed: ${errorText(error)}`,
      { cause: error },
    );
  }
  return {
    queryable: connection.driver,
    describe: `Supabase Lite schema (${driver}, replayed into PGlite)`,
    replay: `the Supabase Lite ${driver} schema was replayed into an in-memory PGlite, which has no statistics or Supabase roles. Set [db] driver = "postgres" with a [db] url, or pass --db-url-stdin, to check a database.`,
    close: () => connection.close(),
  };
}
