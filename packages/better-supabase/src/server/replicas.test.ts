import { afterEach, describe, expect, it, vi } from "vitest";

import type { Executor } from "../core/executor.ts";
import type { Operation } from "../ir/types.ts";

import { defineSupabase } from "../core/define.ts";
import { err, ok } from "../core/result.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { createTestSigner } from "../testing/jwt.ts";
import {
  PRIMARY_COOKIE,
  pinnedUntil,
  primaryCookie,
  replicaState,
  routedExecutor,
} from "./replicas.ts";
import { createServer } from "./server.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const READ_URL = "https://abcdefghijklmnopqrst-all.supabase.co";
const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};
const signer = await createTestSigner();

afterEach(() => {
  vi.unstubAllGlobals();
});

function recording(name: string, calls: string[], fail = false): Executor {
  return {
    name,
    execute: (op: Operation) => {
      calls.push(`${name}:${op.kind}`);
      return Promise.resolve(
        fail
          ? err({ kind: "conflict", message: "no", status: 409 } as never)
          : ok({ rows: [], count: null }),
      );
    },
    rpc: (fn, _args, context) => {
      calls.push(`${name}:rpc:${fn}:${context.get ? "get" : "post"}`);
      return Promise.resolve(ok(null));
    },
  };
}

const select = { kind: "select" } as Operation;
const insert = { kind: "insert" } as Operation;
const context = { errorMappers: [] };

describe("routedExecutor", () => {
  it("reads from the replica until a write succeeds", async () => {
    const calls: string[] = [];
    const state = replicaState();
    const executor = routedExecutor(
      recording("primary", calls),
      recording("replica", calls),
      state,
    );
    await executor.execute(select, context);
    await executor.rpc!(
      "stats",
      {},
      { ...context, schema: "public", get: true },
    );
    expect(state.pinned).toBe(false);
    await executor.execute(insert, context);
    expect(state).toMatchObject({ pinned: true, wrote: true });
    await executor.execute(select, context);
    await executor.rpc!(
      "stats",
      {},
      { ...context, schema: "public", get: true },
    );
    expect(calls).toEqual([
      "replica:select",
      "replica:rpc:stats:get",
      "primary:insert",
      "primary:select",
      "primary:rpc:stats:get",
    ]);
  });

  it("stays on the replica after a failed write and pins after a volatile rpc", async () => {
    const calls: string[] = [];
    const state = replicaState();
    const failing = routedExecutor(
      recording("primary", calls, true),
      recording("replica", calls),
      state,
    );
    await failing.execute(insert, context);
    expect(state.pinned).toBe(false);
    await failing.rpc!("touch", {}, { ...context, schema: "public" });
    expect(state.pinned).toBe(true);
  });

  it("inherits a pin from the cookie until it expires", () => {
    const now = 1_000_000;
    expect(replicaState(now + 1, now)).toMatchObject({
      pinned: true,
      wrote: false,
    });
    expect(replicaState(now - 1, now).pinned).toBe(false);
    expect(pinnedUntil(`a=1; ${PRIMARY_COOKIE}=${String(now)}`)).toBe(now);
    expect(pinnedUntil(`${PRIMARY_COOKIE}=soon`)).toBe(0);
    expect(pinnedUntil(null)).toBe(0);
    expect(primaryCookie(5000, now)).toBe(
      `${PRIMARY_COOKIE}=1005000; Path=/; Max-Age=5; HttpOnly; SameSite=Lax`,
    );
  });
});

describe("createServer read URL", () => {
  const hosts = () => {
    const seen: string[] = [];
    const fetch = vi.fn<typeof globalThis.fetch>((input, init) => {
      seen.push(`${init?.method ?? "GET"} ${new URL(String(input)).host}`);
      return Promise.resolve(
        Response.json(init?.method === "POST" ? [{ id: "c1" }] : []),
      );
    });
    vi.stubGlobal("fetch", fetch);
    return seen;
  };

  it("reads from SUPABASE_READ_URL and writes to the primary", async () => {
    const seen = hosts();
    const server = createServer(defineSupabase(schema), {
      env: { ...env, readUrl: READ_URL },
      auth: { jwks: signer.jwks as never },
    });
    const token = await signer.sign({
      sub: "11111111-1111-4111-8111-111111111111",
    });
    const request = (cookie?: string) =>
      new Request("https://app.test/", {
        headers: {
          authorization: `Bearer ${token}`,
          ...(cookie ? { cookie } : {}),
        },
      });

    const ctx = await server.context(request());
    await ctx.db.customers.findMany({ select: ["id"] }).orThrow();
    await ctx.db.customers
      .create({ name: "Acme", organizationId: "o1" }, { select: ["id"] })
      .orThrow();
    await ctx.db.customers.findMany({ select: ["id"] }).orThrow();
    expect(ctx.replica).toMatchObject({ pinned: true, wrote: true });

    const pinned = await server.context(
      request(`${PRIMARY_COOKIE}=${String(Date.now() + 5000)}`),
    );
    await pinned.db.customers.findMany({ select: ["id"] }).orThrow();
    expect(pinned.replica).toMatchObject({ pinned: true, wrote: false });

    expect(seen).toEqual([
      "GET abcdefghijklmnopqrst-all.supabase.co",
      "POST abcdefghijklmnopqrst.supabase.co",
      "GET abcdefghijklmnopqrst.supabase.co",
      "GET abcdefghijklmnopqrst.supabase.co",
    ]);
  });

  it("reads from the primary with readUrl: false or no read URL", async () => {
    const seen = hosts();
    for (const options of [
      { env: { ...env, readUrl: READ_URL }, readUrl: false as const },
      { env },
    ]) {
      const server = createServer(defineSupabase(schema), options);
      const ctx = await server.context(new Request("https://app.test/"));
      await ctx.db.customers.findMany({ select: ["id"] }).orThrow();
      expect(ctx.replica).toBeUndefined();
    }
    expect(seen).toEqual([
      "GET abcdefghijklmnopqrst.supabase.co",
      "GET abcdefghijklmnopqrst.supabase.co",
    ]);
  });
});
