import type { SupabaseClient } from "@supabase/supabase-js";

import { createClient } from "@supabase/supabase-js";

import type { BetterSupabase } from "../core/define.ts";
import type { BetterSupabaseEnv } from "../env/index.ts";
import type { LiteConnection, PgliteConnection } from "../lite/runtime.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type { TestUser } from "./as-user.ts";
import type { TestJwtClaims } from "./jwt.ts";

import { toBase64Url } from "../core/base64.ts";
import {
  LITE_INSTALL,
  loadLite,
  migrateLite,
  seedLite,
} from "../lite/runtime.ts";
import { asUser } from "./as-user.ts";

export interface LiteStackOptions {
  /**
   * `sqlite-postgres` (default) stores data in in-memory SQLite and translates
   * your Postgres SQL, as `lite init` does. `pglite` runs real Postgres
   * in-process, with `rpc()` and `DEFAULT auth.uid()`.
   */
  readonly driver?: "sqlite-postgres" | "pglite";
  /**
   * Migration SQL, applied in order before `schemas`. DDL only; put rows in
   * `seed`.
   */
  readonly migrations?: readonly string[];
  /**
   * Declarative schema SQL (`supabase/schemas/*.sql`), applied after
   * `migrations`.
   */
  readonly schemas?: readonly string[];
  /** Seed SQL, run after the schema as the database owner (RLS does not apply). */
  readonly seed?: string | readonly string[];
  /** The shared HS256 secret. Defaults to a random one. */
  readonly jwtSecret?: string;
}

export interface LiteStack extends AsyncDisposable {
  /** A placeholder URL: requests never leave the process. */
  readonly url: string;
  readonly publishableKey: string;
  readonly secretKey: string;
  readonly jwtSecret: string;
  /**
   * Routes requests to the in-process Lite app. Pass it as `fetch` to
   * `createServer`.
   */
  readonly fetch: typeof globalThis.fetch;
  /**
   * The settings `createServer(betterSupabase, { env, backend: "lite", fetch
   * })` takes.
   */
  readonly env: BetterSupabaseEnv;
  /** Supabase-js with the publishable key, as an anonymous caller. */
  readonly supabase: SupabaseClient;
  /** Supabase-js with the secret key: bypasses RLS, for setup. */
  readonly admin: SupabaseClient;
  /**
   * A user with an HS256 token, as `asUser` signs it, whose clients route
   * through `fetch`.
   */
  asUser<M extends AnyModels, D, F extends AnyFunctions, E>(
    betterSupabase: BetterSupabase<M, D, F, E>,
    claims: TestJwtClaims,
  ): Promise<TestUser<M, F, E>>;
  /** Closes the database. */
  close(): Promise<void>;
}

const LITE_URL = "http://localhost:54321";

function randomToken(bytes: number): string {
  return toBase64Url(crypto.getRandomValues(new Uint8Array(bytes)));
}

function list(value: string | readonly string[] | undefined): string[] {
  if (value === undefined) {
    return [];
  }

  return typeof value === "string" ? [value] : [...value];
}

/**
 * Supabase Lite in this process, for tests without Docker: an in-memory
 * database with your schema, Auth with fresh API keys, and supabase-js clients
 * whose requests go straight to Lite's `fetch` handler (no port).
 *
 * ```ts
 * await using stack = await liteStack({
 *   schemas: [await readFile("supabase/schemas/notes.sql", "utf8")],
 * });
 * const alice = await stack.asUser(betterSupabase, { sub: aliceId });
 * expect(await alice.db.notes.count().orThrow()).toBe(1);
 * ```
 */
export async function liteStack(
  options: LiteStackOptions = {},
): Promise<LiteStack> {
  const lite = await loadLite();

  if (!lite) {
    throw new Error(`liteStack() needs @supabase/lite. ${LITE_INSTALL}`);
  }

  const driver = options.driver ?? "sqlite-postgres";
  const jwtSecret = options.jwtSecret ?? randomToken(32);
  const publishableKey = `sb_publishable_${randomToken(16)}`;
  const secretKey = `sb_secret_${randomToken(16)}`;

  let target:
    | { readonly driver: "pglite"; readonly connection: PgliteConnection }
    | {
        readonly driver: "sqlite-postgres";
        readonly connection: LiteConnection;
      };

  if (driver === "pglite") {
    target = { driver, connection: await lite.createPgliteConnection() };
  } else {
    target = {
      driver,
      connection: await lite.createSqliteConnection(":memory:"),
    };
  }

  const { connection } = target;

  try {
    const app = new lite.App({
      connection,
      auth: {
        enabled: true,
        jwt_secret: jwtSecret,
        publishable_key: publishableKey,
        secret_key: secretKey,
      },
    });

    await app.init();
    await migrateLite(connection, [
      ...(options.migrations ?? []),
      ...(options.schemas ?? []),
    ]);

    for (const seed of list(options.seed)) {
      await seedLite(target, seed);
    }

    const fetch: typeof globalThis.fetch = (input, init) =>
      app.fetch(new Request(input, init));

    const stateless = {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { fetch },
    };

    const close = (): Promise<void> => connection.close();

    return {
      url: LITE_URL,
      publishableKey,
      secretKey,
      jwtSecret,
      fetch,
      env: {
        url: LITE_URL,
        publishableKey,
        secretKey,
        secretKeys: { default: secretKey },
        jwksUrl: new URL(`${LITE_URL}/auth/v1/.well-known/jwks.json`),
        jwtSecret,
      },
      // oxlint-disable-next-line typescript/no-unsafe-assignment -- supabase-js infers `any` for the schema name without a Database type.
      supabase: createClient(LITE_URL, publishableKey, stateless),
      // oxlint-disable-next-line typescript/no-unsafe-assignment -- supabase-js infers `any` for the schema name without a Database type.
      admin: createClient(LITE_URL, secretKey, stateless),
      asUser: (betterSupabase, claims) =>
        asUser(betterSupabase, claims, {
          url: LITE_URL,
          publishableKey,
          alg: "HS256",
          jwtSecret,
          fetch,
        }),
      close,
      [Symbol.asyncDispose]: close,
    };
  } catch (error) {
    await connection.close();
    throw error;
  }
}
