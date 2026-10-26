import type { LiteRuntime, PgliteConnection } from "../../lite/runtime.ts";
import type { Issue } from "../issue.ts";
import type { PresetMigrationFile } from "../types.ts";
import type { SkippedBlock } from "./apply.ts";
import type { RawCatalog } from "./catalog.ts";

import { LITE_INSTALL, loadLite } from "../../lite/runtime.ts";
import { applyFiles, messageOf } from "./apply.ts";
import { catalogQuery, readCatalog } from "./catalog.ts";
import { SUPABASE_PRELUDE } from "./prelude.ts";
import { handleRest } from "./rest.ts";

/** Who a query runs as: the claims a Supabase JWT would carry. */
export interface Persona {
  /** The user id, `auth.uid()`. Leave out for an anonymous caller. */
  readonly sub?: string;
  /** Defaults to `authenticated` with a `sub`, otherwise `anon`. */
  readonly role?: "anon" | "authenticated" | "service_role";
  /** Extra claims, such as `app_metadata` or the tenant claim. */
  readonly claims?: Readonly<Record<string, unknown>>;
}

export interface SandboxError {
  /** The Postgres error code, such as `42501` or `23505`. */
  readonly code: string;
  readonly message: string;
}

export type SandboxResult =
  | { readonly ok: true; readonly rows: readonly unknown[] }
  | { readonly ok: false; readonly error: SandboxError };

export interface SandboxSession {
  /**
   * Runs one statement in a transaction as this persona, with row level
   * security applied. A failed statement rolls back.
   */
  query(sql: string, params?: readonly unknown[]): Promise<SandboxResult>;
  /** A subset of PostgREST over the sandbox, as this persona. */
  rest(request: Request): Promise<Response>;
}

export interface Sandbox extends SandboxSession {
  /** A persona's session. The sandbox itself runs as the database owner. */
  as(persona: Persona): SandboxSession;
  /** Every table, column and key in `public`. */
  catalog(): Promise<RawCatalog>;
  /** SQL errors from applying the project's files. */
  readonly issues: readonly Issue[];
  readonly skipped: readonly SkippedBlock[];
  close(): Promise<void>;
}

export interface SandboxOptions {
  /** A loaded `@supabase/lite`; loaded on demand when left out. */
  readonly runtime?: LiteRuntime;
}

/** What Supabase grants the API roles on `public` by default. */
const API_GRANTS = `
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
`;

const ROLES = new Set(["anon", "authenticated", "service_role"]);

function roleOf(persona: Persona): string {
  return persona.role ?? (persona.sub === undefined ? "anon" : "authenticated");
}

function claimsOf(persona: Persona): Record<string, unknown> {
  return {
    ...persona.claims,
    role: roleOf(persona),
    ...(persona.sub === undefined ? {} : { sub: persona.sub }),
  };
}

function errorOf(error: unknown): SandboxError {
  const code =
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    typeof error.code === "string"
      ? error.code
      : "XX000";

  return { code, message: messageOf(error) };
}

/** Rows, as a plain array, from whatever PGlite returned. */
function rowsOf(result: { rows: unknown[] }): readonly unknown[] {
  return result.rows;
}

type Driver = PgliteConnection["driver"];

class Queue {
  private tail: Promise<unknown> = Promise.resolve();

  run<TValue>(task: () => Promise<TValue>): Promise<TValue> {
    const next = this.tail.then(task);
    this.tail = next.catch(() => undefined);

    return next;
  }
}

async function asPersona(
  driver: Driver,
  queue: Queue,
  persona: Persona,
  sql: string,
  params: readonly unknown[],
): Promise<SandboxResult> {
  return queue.run(async () => {
    const role = roleOf(persona);

    if (!ROLES.has(role)) {
      return {
        ok: false,
        error: { code: "22023", message: `Unknown role ${role}.` },
      };
    }

    await driver.exec("begin");

    try {
      await driver.query(
        `select set_config('role', $1, true),
                set_config('request.jwt.claims', $2, true),
                set_config('request.jwt.claim.sub', $3, true),
                set_config('request.jwt.claim.role', $1, true)`,
        [role, JSON.stringify(claimsOf(persona)), persona.sub ?? ""],
      );

      const rows = rowsOf(await driver.query(sql, params));
      await driver.exec("commit");

      return { ok: true, rows };
    } catch (error) {
      await driver.exec("rollback").catch(() => undefined);

      return { ok: false, error: errorOf(error) };
    }
  });
}

/**
 * Opens an in-memory PGlite database with a project's files applied, the
 * Supabase roles in place and the API roles granted what Supabase grants them
 * by default. Queries run as the database owner, or as a persona through `as({
 * sub, role, claims })` with row level security applied, and `rest` answers a
 * subset of PostgREST: table reads and writes with `select`, filters, `order`,
 * `limit` and `offset`, and `rpc` calls. Embedding, `or`, `and` and range
 * headers are not supported. Throws when `@supabase/lite` isn't installed.
 */
export async function openSandbox(
  project: { readonly files: readonly PresetMigrationFile[] },
  options: SandboxOptions = {},
): Promise<Sandbox> {
  const runtime = options.runtime ?? (await loadLite());

  if (runtime === undefined) {
    throw new Error(LITE_INSTALL);
  }

  const connection = await runtime.createPgliteConnection();
  const { driver } = connection;
  const queue = new Queue();

  await driver.exec(SUPABASE_PRELUDE);
  await driver.exec(API_GRANTS);

  const { issues, skipped } = await applyFiles(driver, project.files);

  const run = (
    persona: Persona,
    sql: string,
    params: readonly unknown[],
  ): Promise<SandboxResult> => asPersona(driver, queue, persona, sql, params);

  const session = (persona: Persona): SandboxSession => ({
    query: (sql, params = []) => run(persona, sql, params),
    rest: (request) => handleRest(request, run, persona),
  });

  const owner: SandboxSession["query"] = (sql, params = []) =>
    queue.run(async () => {
      try {
        return { ok: true, rows: rowsOf(await driver.query(sql, params)) };
      } catch (error) {
        return { ok: false, error: errorOf(error) };
      }
    });

  return {
    query: owner,
    rest: (request) => handleRest(request, run),
    as: session,
    issues,
    skipped,
    catalog: async () => {
      const { rows } = await driver.query(catalogQuery(["public"]));

      return readCatalog(rows);
    },
    close: () => connection.close(),
  };
}
