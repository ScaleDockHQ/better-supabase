import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { createSupabase } from "../../src/core/define.ts";
import { defineReadSet } from "../../src/core/read-set.ts";
import { bootstrapWith, mapBootstrapMemo } from "../../src/server/bootstrap.ts";
import { createServer } from "../../src/server/server.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";

const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};

const USER = "11111111-1111-4111-8111-111111111111";
const SESSION = "33333333-3333-4333-8333-333333333333";
const signer = await createTestSigner();

const seed = vi.fn<(userId: string, version: number) => void>();
const evicted = vi.fn<(userId: string) => void>();

const definition = createSupabase(schema);

const hub = defineReadSet(definition, "hub", {}, (s) => ({
  customers: s.customers.count(),
}));

const other = defineReadSet(definition, "other", {}, (s) => ({
  customers: s.customers.count(),
}));

const server = createServer(definition, {
  env,
  auth: { jwks: signer.jwks },
  versions: {
    get: () => undefined,
    set: () => undefined,
    evict: evicted,
    seed,
  } as never,
});

const signedIn = async (
  claims: Record<string, unknown> = {},
): Promise<Request> =>
  new Request("https://app.test/home", {
    headers: {
      authorization: `Bearer ${await signer.sign({ sub: USER, session_id: SESSION, ...claims })}`,
    },
  });

let calls: { url: string; body: unknown }[] = [];
let row: Record<string, unknown> = {};

beforeEach(() => {
  calls = [];
  seed.mockReset();
  evicted.mockReset();
  row = {
    session_active: true,
    authz_version: 7,
    token_authz_version: 5,
    tenant: null,
    data: { unread: 3 },
  };
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
    const url = String(input instanceof Request ? input.url : input);

    if (url.includes("/rest/v1/rpc/")) {
      calls.push({ url, body: JSON.parse(String(init?.body ?? "null")) });
    }

    return Response.json(row);
  });
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("server.bootstrapFor()", () => {
  it("makes one call per request and seeds the live version", async () => {
    const request = await signedIn({ authz_ver: 5 });

    const [first, second] = await Promise.all([
      server.bootstrapFor<{ unread: number }>(request, { rpc: "home" }),
      server.bootstrapFor<{ unread: number }>(request, { rpc: "home" }),
    ]);

    expect(first).toMatchObject({
      sessionActive: true,
      authzVersion: 7,
      tokenAuthzVersion: 5,
      stale: true,
      data: { unread: 3 },
    });
    expect(second).toEqual(first);
    expect(calls).toEqual([
      { url: `${PROJECT_URL}/rest/v1/rpc/bootstrap_home`, body: { args: {} } },
    ]);
    expect(seed).toHaveBeenCalledWith(USER, 7);

    await server.bootstrapFor(await signedIn(), { rpc: "home" });
    expect(calls).toHaveLength(2);
  });

  it("expands the provider's permissions from the full and the compact form", async () => {
    row = {
      ...row,
      permissions: { apiVersion: 1, tenants: { t1: ["a.read"] }, platform: [] },
    };

    expect(
      (await server.bootstrapFor(await signedIn(), { rpc: "home" }))
        .permissions,
    ).toEqual({ apiVersion: 1, tenants: { t1: ["a.read"] }, platform: [] });

    server.sessions.clear();

    row = {
      ...row,
      permissions: {
        apiVersion: 1,
        form: "compact",
        keys: ["a.read", "b.read"],
        tenants: { t1: "Ag" },
        platform: "AQ",
      },
    };

    expect(
      (await server.bootstrapFor(await signedIn(), { rpc: "home" }))
        .permissions,
    ).toEqual({
      apiVersion: 1,
      tenants: { t1: ["b.read"] },
      platform: ["a.read"],
    });
  });

  it("reports a partial team_ids claim", async () => {
    expect(
      (await server.bootstrapFor(await signedIn(), { rpc: "home" }))
        .teamIdsTruncated,
    ).toBe(false);

    server.sessions.clear();

    expect(
      (
        await server.bootstrapFor(
          await signedIn({ team_ids_truncated: true }),
          { rpc: "home" },
        )
      ).teamIdsTruncated,
    ).toBe(true);
  });

  it("returns no permissions for another apiVersion or a wrapper without them", async () => {
    row = { ...row, permissions: { apiVersion: 2, tenants: {} } };

    expect(
      (await server.bootstrapFor(await signedIn(), { rpc: "home" }))
        .permissions,
    ).toBeNull();

    row = { ...row, permissions: undefined };

    expect(
      (await server.bootstrapFor(await signedIn(), { rpc: "other" }))
        .permissions,
    ).toBeNull();
  });

  it("runs a read set in the wrapper call and decodes its reads", async () => {
    row = { ...row, reads: { customers: { rows: null, count: 4 } } };

    const boot = await server.bootstrapFor(await signedIn(), {
      rpc: "home",
      readSet: hub,
      params: {},
    });

    expect(boot.reads).toEqual({ customers: 4 });
    expect(calls).toEqual([
      {
        url: `${PROJECT_URL}/rest/v1/rpc/bootstrap_home`,
        body: { args: {}, read_set: "hub", read_params: {} },
      },
    ]);
  });

  it("runs only the read set when the request already ran the wrapper", async () => {
    const request = await signedIn();

    await server.bootstrapFor(request, { rpc: "home" });
    expect(calls).toHaveLength(1);

    row = { customers: { rows: null, count: 9 } };

    const boot = await server.bootstrapFor(request, {
      rpc: "home",
      readSet: other,
      params: {},
    });

    expect(boot.reads).toEqual({ customers: 9 });
    expect(boot.data).toEqual({ unread: 3 });
    expect(calls.map((call) => call.url.split("?")[0])).toEqual([
      `${PROJECT_URL}/rest/v1/rpc/bootstrap_home`,
      `${PROJECT_URL}/rest/v1/rpc/rs_other`,
    ]);
  });

  it("makes no call for a signed-out caller", async () => {
    const boot = await server.bootstrapFor(new Request("https://app.test/"), {
      rpc: "home",
    });

    expect(boot).toMatchObject({ sessionActive: false, data: null });
    expect(calls).toEqual([]);
  });

  it("evicts a user whose session ended and returns no data", async () => {
    row = { ...row, session_active: false, end_reason: "session_not_found" };

    const boot = await server.bootstrapFor(await signedIn(), { rpc: "home" });

    expect(boot).toMatchObject({ sessionActive: false, data: null });
    expect(evicted).toHaveBeenCalledWith(USER);
    expect(seed).not.toHaveBeenCalled();
  });

  it("refuses a wrapper from before 0.44 that returns no end_reason", async () => {
    row = { ...row, session_active: false };
    delete row["end_reason"];

    await expect(
      server.bootstrapFor(await signedIn(), { rpc: "home" }),
    ).rejects.toThrow("bsb sql upgrade");
  });
});

describe("server.accessFor()", () => {
  it("reads the token's version from a request", async () => {
    const access = await server.accessFor(await signedIn({ authz_ver: 4 }));

    expect(access).toMatchObject({ authzVersion: 4, tenant: null });
    expect(access.session.kind).toBe("user");
  });

  it("prefers the bootstrap's live version and tenant", async () => {
    const request = await signedIn({ authz_ver: 4 });
    const bootstrap = await server.bootstrapFor(request, { rpc: "home" });
    const snapshot = await server.snapshot(request);

    const access = await server.accessFor(snapshot, {
      bootstrap: { ...bootstrap, tenant: "acme" },
    });

    expect(access).toMatchObject({ authzVersion: 7, tenant: "acme" });
  });

  it("answers false for a signed-out caller", async () => {
    const access = await server.accessFor(null);

    expect(access.session.kind).toBe("none");
    expect(await access.can("posts.read")).toBe(false);
  });
});

describe("accessFor() with a bootstrap subject", () => {
  it("hands the subject to the authorizer as a seed", async () => {
    const seen: unknown[] = [];

    const authorizer = {
      apiVersion: 1 as const,
      name: "probe",
      key: (ref: string) => ref,
      evaluate: (_request: unknown, runtime?: { seed?: unknown }) => {
        seen.push(runtime?.seed);

        return Promise.resolve({ allowed: true as const });
      },
    };

    const seeded = createServer(definition, {
      env,
      auth: { jwks: signer.jwks },
      // SAFETY: the probe implements the members the server calls.
      authorizer: authorizer as never,
    });

    const request = await signedIn({ authz_ver: 4 });
    const bootstrap = await seeded.bootstrapFor(request, { rpc: "home" });
    const snapshot = await seeded.snapshot(request);

    const access = await seeded.accessFor(snapshot, {
      bootstrap: { ...bootstrap, subject: { roles: ["admin"] } },
    });

    await access.can("posts.read");

    expect(seen[0]).toEqual({
      userId: USER,
      version: 7,
      subject: { roles: ["admin"] },
    });
  });
});

describe("bootstrapWith() in a support session", () => {
  const supportCtx = (rpc: (name: string) => unknown) => ({
    auth: {
      kind: "user" as const,
      token: "",
      claims: { sub: USER, role: "authenticated" },
      user: { id: USER, role: "authenticated" },
      source: "support" as const,
      expiresAt: Math.floor(Date.now() / 1000) + 600,
    },
    db: {
      $executor: {
        rpc: (name: string) => Promise.resolve({ ok: true, data: rpc(name) }),
      },
    },
    support: { session: { id: "sup1" } },
  });

  const deps = {
    schema: () => "better_supabase",
    evictSession: async (userId: string) => {
      evicted(userId);
    },
    versions: undefined,
  };

  it("runs the wrapper as the target and reports the session active", async () => {
    const keys: string[] = [];

    const boot = await bootstrapWith(
      deps,
      // SAFETY: the context carries the parts bootstrapWith reads.
      supportCtx(() => row) as never,
      { rpc: "home" },
      undefined,
      (key, run) => {
        keys.push(key);

        return run();
      },
    );

    expect(boot).toMatchObject({ sessionActive: true, data: { unread: 3 } });
    expect(keys).toEqual(["support:sup1|better_supabase|home|{}"]);
  });

  it("does not evict the target when the support session ended", async () => {
    const boot = await bootstrapWith(
      deps,
      // SAFETY: the context carries the parts bootstrapWith reads.
      supportCtx(() => ({
        ...row,
        session_active: false,
        end_reason: "session_not_found",
      })) as never,
      { rpc: "home" },
      undefined,
      (_key, run) => run(),
    );

    expect(boot).toMatchObject({ sessionActive: false, data: null });
    expect(evicted).not.toHaveBeenCalled();
  });
});

describe("bootstrapWith() errors and memoized read sets", () => {
  const ctxOf = (
    executor: Record<string, unknown>,
    extra: Record<string, unknown> = {},
  ) => ({
    auth: {
      kind: "user" as const,
      token: "token",
      claims: { sub: USER, role: "authenticated", session_id: SESSION },
      user: { id: USER, role: "authenticated" },
      source: "support" as const,
      expiresAt: Math.floor(Date.now() / 1000) + 600,
    },
    db: { $executor: executor, ...extra },
    support: { session: { id: "sup2" } },
  });

  const deps = {
    schema: () => "better_supabase",
    evictSession: async () => {},
    versions: undefined,
  };

  const direct = (_key: string, run: () => Promise<never>) => run();
  const call = { rpc: "home" };

  const run = (ctx: unknown) =>
    // SAFETY: the context carries the parts bootstrapWith reads.
    bootstrapWith(deps, ctx as never, call, undefined, direct as never);

  const wrapper = (data: unknown) => ({
    rpc: () => Promise.resolve({ ok: true, data }),
  });

  it("rejects an executor that can't call functions", async () => {
    await expect(run(ctxOf({}))).rejects.toThrow(
      "needs an executor that calls functions",
    );
  });

  it("throws the wrapper's error", async () => {
    await expect(
      run(
        ctxOf({
          rpc: () =>
            Promise.resolve({
              ok: false,
              error: { code: "unexpected", message: "boom" },
            }),
        }),
      ),
    ).rejects.toMatchObject({ error: { message: "boom" } });
  });

  it("rejects a row without session_active", async () => {
    await expect(run(ctxOf(wrapper({ data: 1 })))).rejects.toMatchObject({
      error: { message: "The bootstrap wrapper returned no session_active" },
    });
  });

  it("reads bigint versions and a banned user", async () => {
    const boot = await run(
      ctxOf(
        wrapper({
          session_active: false,
          end_reason: "user_banned",
          authz_version: "12",
          token_authz_version: "x",
        }),
      ),
    );

    expect(boot).toMatchObject({
      sessionActive: false,
      endReason: "user_banned",
      authzVersion: 12,
      tokenAuthzVersion: null,
      stale: false,
    });
  });

  const readSet = { name: "hub" } as never;

  const memoRow = {
    sessionActive: true,
    endReason: null,
    authzVersion: 1,
    tokenAuthzVersion: 1,
    tenant: null,
    data: null,
    reads: { a: 1 },
    subject: null,
  };

  // Runs the fallback the way a memo that holds the key never would.
  const memoOf = (has: (key: string) => boolean) =>
    Object.assign(
      (_key: string, run: () => Promise<unknown>) =>
        run().then(
          (value) => value,
          () => memoRow,
        ),
      { has },
    );

  it("reads a set separately when the shell was memoized without it", async () => {
    const many = vi.fn(async () => ({ ok: true as const, data: { a: 2 } }));

    const boot = await bootstrapWith(
      deps,
      // SAFETY: the context carries the parts bootstrapWith reads.
      ctxOf(wrapper({}), { $many: many, $decodeReadSet: vi.fn() }) as never,
      { rpc: "home", readSet },
      undefined,
      memoOf((key) => !key.includes("|rs:")) as never,
    );

    expect(many).toHaveBeenCalledOnce();
    expect(boot.reads).toEqual({ a: 2 });
  });

  it("decodes the payload of a memoized set and throws a failed decode", async () => {
    const decode = vi.fn(async () => ({ ok: true as const, data: { a: 3 } }));

    const boot = await bootstrapWith(
      deps,
      // SAFETY: the context carries the parts bootstrapWith reads.
      ctxOf(wrapper({}), { $many: vi.fn(), $decodeReadSet: decode }) as never,
      { rpc: "home", readSet },
      undefined,
      memoOf(() => true) as never,
    );

    expect(boot.reads).toEqual({ a: 3 });

    await expect(
      bootstrapWith(
        deps,
        ctxOf(wrapper({}), {
          $many: vi.fn(),
          $decodeReadSet: async () => ({
            ok: false as const,
            error: { code: "unexpected", message: "bad" },
          }),
          // SAFETY: the context carries the parts bootstrapWith reads.
        }) as never,
        { rpc: "home", readSet },
        undefined,
        memoOf(() => true) as never,
      ),
    ).rejects.toMatchObject({ error: { message: "bad" } });
  });
});

describe("mapBootstrapMemo()", () => {
  it("runs a key once and reports the keys it holds", async () => {
    const memo = mapBootstrapMemo(new Map());
    const run = vi.fn(async () => ({}) as never);

    expect(memo.has?.("a")).toBe(false);

    await memo("a", run);
    await memo("a", run);

    expect(run).toHaveBeenCalledOnce();
    expect(memo.has?.("a")).toBe(true);
  });
});
