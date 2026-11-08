import { describe, expect, it } from "vitest";

import type { BetterPostgres, SqlClaims } from "../../src/postgres/pool.ts";

import { createSupabase } from "../../src/core/define.ts";
import { dbError } from "../../src/core/errors.ts";
import { err, ok } from "../../src/core/result.ts";
import { postgresExecutor } from "../../src/postgres/executor.ts";
import { createServer } from "../../src/server/server.ts";
import { fakeSql } from "../fixtures/fake-sql.ts";
import { schema } from "../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";

const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};

const USER = "11111111-1111-4111-8111-111111111111";

function fakePostgres() {
  const fake = fakeSql();
  const claims: SqlClaims[] = [];
  let rolledBack = 0;

  // SAFETY: the server only calls transactionFor.
  const postgres = {
    admin: fake.sql,
    anon: fake.sql,
    executorFor: () => postgresExecutor(fake.sql),
    transactionFor: async <T>(
      value: SqlClaims,
      fn: (executor: ReturnType<typeof postgresExecutor>) => Promise<T>,
    ): Promise<T> => {
      claims.push(value);

      try {
        return await fn(postgresExecutor(fake.sql));
      } catch (cause) {
        rolledBack += 1;
        throw cause;
      }
    },
  } as unknown as BetterPostgres;

  return { postgres, claims, rolledBack: () => rolledBack };
}

describe("server.transaction", () => {
  it("runs fn as the user and commits what it returns", async () => {
    const { postgres, claims, rolledBack } = fakePostgres();
    const server = createServer(createSupabase(schema), { env, postgres });

    const result = await server.transaction(USER, () =>
      Promise.resolve(ok("done")),
    );

    expect(result).toEqual(ok("done"));
    expect(claims[0]).toMatchObject({ sub: USER, role: "authenticated" });
    expect(rolledBack()).toBe(0);
  });

  it("rolls back on a Result that is not ok and still returns it", async () => {
    const { postgres, rolledBack } = fakePostgres();
    const server = createServer(createSupabase(schema), { env, postgres });
    const failure = err(dbError("conflict", "taken"));

    const result = await server.transaction(USER, () =>
      Promise.resolve(failure),
    );

    expect(result).toBe(failure);
    expect(rolledBack()).toBe(1);
  });

  it("rolls back on a throw", async () => {
    const { postgres, rolledBack } = fakePostgres();
    const server = createServer(createSupabase(schema), { env, postgres });

    await expect(
      server.transaction(USER, () => Promise.reject(new Error("boom"))),
    ).rejects.toThrow("boom");
    expect(rolledBack()).toBe(1);
  });

  it("needs a postgres that can run transactions", async () => {
    const server = createServer(createSupabase(schema), { env });

    await expect(
      server.transaction(USER, () => Promise.resolve(1)),
    ).rejects.toThrow("server.transaction needs");
  });
});
