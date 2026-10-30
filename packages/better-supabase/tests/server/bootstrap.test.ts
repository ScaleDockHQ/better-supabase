import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { bootstrapWith } from "../../src/server/bootstrap.ts";
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

const server = createServer(defineSupabase(schema), {
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

  it("makes no call for a signed-out caller", async () => {
    const boot = await server.bootstrapFor(new Request("https://app.test/"), {
      rpc: "home",
    });

    expect(boot).toMatchObject({ sessionActive: false, data: null });
    expect(calls).toEqual([]);
  });

  it("evicts a user whose session ended and returns no data", async () => {
    row = { ...row, session_active: false };

    const boot = await server.bootstrapFor(await signedIn(), { rpc: "home" });

    expect(boot).toMatchObject({ sessionActive: false, data: null });
    expect(evicted).toHaveBeenCalledWith(USER);
    expect(seed).not.toHaveBeenCalled();
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
      supportCtx(() => ({ ...row, session_active: false })) as never,
      { rpc: "home" },
      undefined,
      (_key, run) => run(),
    );

    expect(boot).toMatchObject({ sessionActive: false, data: null });
    expect(evicted).not.toHaveBeenCalled();
  });
});
