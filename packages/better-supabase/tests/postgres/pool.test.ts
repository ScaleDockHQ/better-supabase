import { afterEach, describe, expect, it, vi } from "vitest";

import { createPostgres } from "../../src/postgres/pool.ts";
import { fakePgPool } from "../fixtures/fake-pg-pool.ts";

function recordingPool(
  answer: (text: string, values: readonly unknown[]) => unknown[] = () => [],
) {
  const values: (readonly unknown[])[] = [];
  const fake = fakePgPool((text, params) => {
    values.push(params);
    return answer(text, params);
  });
  return Object.assign(fake, { values });
}

const CLAIMS_SQL = "select set_config('request.jwt.claims', $1, true)";

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("createPostgres", () => {
  it("runs an admin query in its own transaction and releases the connection", async () => {
    const fake = recordingPool((text) =>
      text === "select $1::int as n" ? [{ n: 1 }] : [],
    );
    const pg = createPostgres({ pool: fake.pool });
    expect(await pg.admin.queryRaw("select $1::int as n", [1])).toEqual([
      { n: 1 },
    ]);
    expect(fake.log).toEqual(["begin", "select $1::int as n", "commit"]);
    expect(fake.values[1]).toEqual([1]);
    expect(fake.connections).toBe(1);
    expect(fake.released).toBe(1);
  });

  it("sets a truncated statement timeout per transaction", async () => {
    const fake = recordingPool();
    const pg = createPostgres({ pool: fake.pool, statementTimeout: 1500.9 });
    await pg.admin.queryRaw("select 1");
    expect(fake.log).toEqual([
      "begin",
      "set local statement_timeout = 1500",
      "select 1",
      "commit",
    ]);
  });

  it("runs asUser queries as authenticated with the claims set locally", async () => {
    const fake = recordingPool();
    const pg = createPostgres({ pool: fake.pool });
    await pg.asUser({ sub: "u1", tenant_id: "t1" }).queryRaw("select 1");
    expect(fake.log).toEqual([
      "begin",
      CLAIMS_SQL,
      "set local role authenticated",
      "select 1",
      "commit",
    ]);
    expect(JSON.parse(String(fake.values[1]![0]))).toEqual({
      sub: "u1",
      tenant_id: "t1",
      role: "authenticated",
    });
  });

  it("uses anon for claims without a subject, and for postgres.anon", async () => {
    const fake = recordingPool();
    const pg = createPostgres({ pool: fake.pool });
    await pg.asUser({}).queryRaw("select 1");
    await pg.anon.queryRaw("select 2");
    expect(
      fake.log.filter((text) => text.startsWith("set local role")),
    ).toEqual(["set local role anon", "set local role anon"]);
    expect(JSON.parse(String(fake.values[1]![0]))).toEqual({ role: "anon" });
    expect(fake.log[6]).toBe(CLAIMS_SQL);
    expect(JSON.parse(String(fake.values[6]![0]))).toEqual({ role: "anon" });
  });

  it("keeps an explicit anon role even when a subject is present", async () => {
    const fake = recordingPool();
    const pg = createPostgres({ pool: fake.pool });
    await pg.asUser({ sub: "u1", role: "anon" }).queryRaw("select 1");
    expect(fake.log).toContain("set local role anon");
  });

  it("refuses roles other than authenticated and anon", () => {
    const pg = createPostgres({ pool: fakePgPool().pool });
    expect(() => pg.asUser({ sub: "u1", role: "service_role" })).toThrow(
      'Cannot run as role "service_role"',
    );
    expect(() =>
      pg.transaction(async () => 1, { claims: { role: "postgres" } }),
    ).toThrow(TypeError);
  });

  it("runs a transaction with claims on one connection, nested transactions included", async () => {
    const fake = recordingPool();
    const pg = createPostgres({ pool: fake.pool });
    const result = await pg.transaction(
      async (tx) => {
        await tx.queryRaw("insert into a values (1)");
        return tx.transaction!(async (inner) => {
          await inner.queryRaw("insert into b values (2)");
          return "done";
        });
      },
      { claims: { sub: "u1" } },
    );
    expect(result).toBe("done");
    expect(fake.log).toEqual([
      "begin",
      CLAIMS_SQL,
      "set local role authenticated",
      "insert into a values (1)",
      "insert into b values (2)",
      "commit",
    ]);
    expect(fake.connections).toBe(1);
    expect(fake.released).toBe(1);
  });

  it("runs a transaction without claims as the connection role", async () => {
    const fake = recordingPool();
    const pg = createPostgres({ pool: fake.pool });
    await pg.transaction((tx) => tx.queryRaw("select 1"));
    await pg.admin.transaction!((tx) => tx.queryRaw("select 2"));
    expect(fake.log).toEqual([
      "begin",
      "select 1",
      "commit",
      "begin",
      "select 2",
      "commit",
    ]);
  });

  it("rolls back, releases and rethrows when the callback fails", async () => {
    const fake = recordingPool();
    const pg = createPostgres({ pool: fake.pool });
    await expect(
      pg.transaction(async (tx) => {
        await tx.queryRaw("insert into a values (1)");
        throw new Error("roll back");
      }),
    ).rejects.toThrow("roll back");
    expect(fake.log).toEqual(["begin", "insert into a values (1)", "rollback"]);
    expect(fake.released).toBe(1);
  });

  it("rethrows the query error even when the rollback fails too", async () => {
    const failure = Object.assign(new Error("duplicate key"), {
      code: "23505",
    });
    const fake = recordingPool((text) => {
      if (text === "insert") throw failure;
      if (text === "rollback") throw new Error("connection lost");
      return [];
    });
    const pg = createPostgres({ pool: fake.pool });
    await expect(pg.admin.queryRaw("insert")).rejects.toBe(failure);
    expect(fake.log).toEqual(["begin", "insert", "rollback"]);
    expect(fake.released).toBe(1);
  });

  it("propagates a failed connect without releasing anything", async () => {
    const fake = fakePgPool();
    fake.pool.connect = () => Promise.reject(new Error("too many clients"));
    const pg = createPostgres({ pool: fake.pool });
    await expect(pg.admin.queryRaw("select 1")).rejects.toThrow(
      "too many clients",
    );
    expect(fake.released).toBe(0);
  });

  it("ends the pool through end() and Symbol.asyncDispose", async () => {
    const fake = fakePgPool();
    const pg = createPostgres({ pool: fake.pool });
    await pg.end();
    await pg[Symbol.asyncDispose]();
    expect(fake.ended).toBe(2);
  });

  it("opens a pg pool from the connection string or the environment", async () => {
    const explicit = createPostgres({
      connectionString: "postgresql://postgres:postgres@127.0.0.1:1/postgres",
      max: 2,
    });
    await explicit.end();
    vi.stubEnv("SUPABASE_DB_URL", undefined);
    vi.stubEnv("DATABASE_URL", "postgresql://127.0.0.1:1/postgres");
    await createPostgres().end();
    vi.stubEnv("SUPABASE_DB_URL", "postgresql://127.0.0.1:1/postgres");
    await createPostgres().end();
  });

  it("needs a connection string when no pool or environment is set", () => {
    vi.stubEnv("SUPABASE_DB_URL", undefined);
    vi.stubEnv("DATABASE_URL", undefined);
    expect(() => createPostgres()).toThrow(
      "createPostgres needs a connectionString, $SUPABASE_DB_URL or $DATABASE_URL",
    );
  });
});
