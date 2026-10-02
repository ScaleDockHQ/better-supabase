import { describe, expect, it } from "vitest";

import { connect } from "../src/db.ts";

const URL = "postgresql://postgres:secret@127.0.0.1:55422/postgres";

function fakePg(connectError?: unknown) {
  const state = { options: [] as unknown[], ended: 0, queries: [] as string[] };
  class Client {
    constructor(options: unknown) {
      state.options.push(options);
    }
    connect(): Promise<void> {
      return connectError === undefined
        ? Promise.resolve()
        : Promise.reject(connectError);
    }
    async query(text: string): Promise<{ rows: unknown[] }> {
      state.queries.push(text);
      return { rows: [{ one: 1 }] };
    }
    async end(): Promise<void> {
      state.ended += 1;
    }
  }
  return { Client, state };
}

describe("connect", () => {
  it("opens a client from the module's named Client export", async () => {
    const pg = fakePg();
    const db = await connect(URL, async () => ({ Client: pg.Client }));
    expect(pg.state.options).toEqual([{ connectionString: URL }]);
    expect(db.describe).toBe(
      "postgresql://postgres:***@127.0.0.1:55422/postgres",
    );
    expect(await db.client.query("select 1")).toEqual({ rows: [{ one: 1 }] });
    await db.close();
    expect(pg.state.ended).toBe(1);
  });

  it("prefers the default export of a CommonJS interop module", async () => {
    const pg = fakePg();
    const db = await connect(URL, async () => ({
      default: { Client: pg.Client },
    }));
    expect(pg.state.options).toHaveLength(1);
    await db.client.query("select 2");
    expect(pg.state.queries).toEqual(["select 2"]);
  });

  it("leaves a URL without a password as it is", async () => {
    const pg = fakePg();
    const db = await connect("postgresql://localhost/app", async () => pg);
    expect(db.describe).toBe("postgresql://localhost/app");
  });

  it("asks to install pg when the module cannot be loaded", async () => {
    await expect(
      connect(URL, () => Promise.reject(new Error("Cannot find module 'pg'"))),
    ).rejects.toThrow(
      'better-supabase needs the "pg" package to read your database. Install it: pnpm add -D pg',
    );
  });

  it("redacts the password and keeps the cause when the connection fails", async () => {
    const refused = new Error("connect ECONNREFUSED 127.0.0.1:55422");
    const pg = fakePg(refused);
    const failure = await connect(URL, async () => pg).catch(
      (error: unknown) => error,
    );
    expect(failure).toBeInstanceOf(Error);
    expect((failure as Error).message).toBe(
      "Could not connect to postgresql://postgres:***@127.0.0.1:55422/postgres: connect ECONNREFUSED 127.0.0.1:55422. Is the local stack running (supabase start)?",
    );
    expect((failure as Error).message).not.toContain("secret");
    expect((failure as Error).cause).toBe(refused);
  });

  it("describes a non-Error connection failure with its string form", async () => {
    const pg = fakePg("socket closed");
    await expect(connect(URL, async () => pg)).rejects.toThrow(
      "postgres: socket closed. Is the local stack running",
    );
  });
});
