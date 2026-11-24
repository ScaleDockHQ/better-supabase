import { beforeEach, describe, expect, it, vi } from "vitest";

import type { KeptSkip } from "../../src/core/kept-cache.ts";
import type { SchemaMeta } from "../../src/schema/types.ts";
import type { schema } from "../fixtures/generated-camel.ts";

import { permissionsShareKey } from "../../src/blocks/permissions/share-key.ts";
import { defineAuthorizationHooks } from "../../src/core/contracts/authorization-hooks.ts";
import { createSupabase } from "../../src/core/define.ts";
import { memoryKeptStore } from "../../src/core/kept-cache.ts";
import { createNext } from "../../src/next/index.ts";
import { postgresExecutor } from "../../src/postgres/executor.ts";
import { defineSchema } from "../../src/schema/define.ts";
import { shareGuard } from "../../src/server/tenant-share.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { expectTenantShare } from "../../src/testing/tenant-share.ts";
import { fakeSql } from "../fixtures/fake-sql.ts";
import meta from "../fixtures/generated-camel.meta.js";

const mocks = vi.hoisted(() => ({ headers: new Headers() }));

vi.mock(import("next/headers.js"), () => ({
  // SAFETY: the code under test reads only getAll from the cookie jar.
  cookies: () => Promise.resolve({ getAll: () => [] } as never),
  headers: () => Promise.resolve(mocks.headers as never),
}));

vi.mock(import("next/cache.js"), () => ({
  cacheLife: vi.fn(),
  cacheTag: vi.fn(),
  updateTag: vi.fn(),
  revalidateTag: vi.fn(),
  io: () => Promise.resolve(),
}));

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";

const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};

const ORG = "99999999-9999-4999-8999-999999999999";
const ALICE = "11111111-1111-4111-8111-111111111111";
const BOB = "22222222-2222-4222-8222-222222222222";
const CAROL = "33333333-3333-4333-8333-333333333333";
const signer = await createTestSigner();

const GRANTS: Readonly<Record<string, readonly string[]>> = {
  [ALICE]: ["customer.read", "invoice.read"],
  [BOB]: ["customer.read"],
  [CAROL]: ["invoice.read"],
};

const claimsOf = (userId: string) => ({
  permissions: { [ORG]: [...(GRANTS[userId] ?? [])] },
});

async function signIn(userId: string): Promise<void> {
  const token = await signer.sign({ sub: userId, ...claimsOf(userId) });
  mocks.headers = new Headers({ authorization: `Bearer ${token}` });
}

const base: SchemaMeta = meta;

// SAFETY: the same tables as the fixture schema, two of them with share facts.
const shared = defineSchema({
  ...base,
  tables: {
    ...base.tables,
    customers: {
      ...base.tables["customers"]!,
      share: { kind: "tenant", permissions: ["customer.read"] },
    },
    notes: {
      ...base.tables["notes"]!,
      share: { kind: "row", permissions: ["customer.read"] },
    },
  },
  functionShares: {
    customer_payload: {
      schema: "public",
      tables: ["customers"],
      permissions: ["customer.read"],
    },
    note_payload: {
      schema: "public",
      tables: ["notes"],
      permissions: ["customer.read"],
    },
  },
}) as unknown as typeof schema;

const hooks = defineAuthorizationHooks({
  apiVersion: 1,
  name: "test",
  shareKey: permissionsShareKey(),
});

describe('bsb.kept({ share: "tenant" })', () => {
  const store = memoryKeptStore();
  const set = vi.spyOn(store, "set");
  const skips: KeptSkip[] = [];
  const requests: { path: string; key: string | null }[] = [];

  const bsb = createNext(createSupabase(shared), {
    env,
    cacheTags: false,
    auth: { jwks: signer.jwks },
    authorization: hooks,
    kept: { store, onSkip: (skip) => skips.push(skip) },
  });

  const admin = vi.fn<(calls: number) => undefined>();

  const customers = bsb.kept(
    async (ctx) => {
      const rows = await ctx.db.customers.list({ select: ["id", "name"] });
      admin(ctx.stats().adminCalls);

      return rows;
    },
    {
      name: "customers",
      tables: ["customers"],
      share: "tenant",
      tenant: () => ORG,
    },
  );

  beforeEach(() => {
    set.mockClear();
    admin.mockClear();
    skips.length = 0;
    requests.length = 0;

    vi.spyOn(globalThis, "fetch").mockImplementation((input, init) => {
      const url = new URL(input instanceof Request ? input.url : String(input));
      const headers = new Headers(init?.headers);

      requests.push({ path: url.pathname, key: headers.get("authorization") });

      return Promise.resolve(Response.json([{ id: "c1", name: "Acme" }]));
    });
  });

  it("fills once through the first caller's client and serves a second holder", async () => {
    await signIn(ALICE);
    const first = await customers();
    const aliceToken = mocks.headers.get("authorization");

    await signIn(BOB);
    const second = await customers();

    expect(first).toEqual(second);
    expect(requests).toHaveLength(1);
    expect(requests[0]?.key).toBe(aliceToken);
    expect(admin).toHaveBeenCalledWith(0);
    expect(set).toHaveBeenCalledOnce();
  });

  it("keeps a caller without the grant on their own entry", async () => {
    await signIn(CAROL);
    await customers();
    await signIn(CAROL);
    await customers();

    expect(requests).toHaveLength(1);
    expect(set).toHaveBeenCalledOnce();

    await signIn(BOB);
    await customers();

    // Bob reads the tenant entry the first test filled, not Carol's.
    expect(requests).toHaveLength(1);
    expect(set).toHaveBeenCalledOnce();
  });

  it("refuses a row table and keeps the entry per user", async () => {
    const notes = bsb.kept(
      async (ctx) => ctx.db.notes.list({ select: ["id"] }),
      { name: "notes", tables: ["notes"], share: "tenant", tenant: () => ORG },
    );

    await signIn(ALICE);
    await notes();
    await signIn(BOB);
    await notes();

    expect(requests).toHaveLength(2);
    expect(skips[0]).toMatchObject({ name: "notes", reason: "share" });
    expect(skips[0]?.detail).toContain("notes");
  });

  it("refuses a table the provider doesn't list", async () => {
    const tags = bsb.kept(async (ctx) => ctx.db.tags.list({ select: ["id"] }), {
      name: "tags",
      tables: ["tags"],
      share: "tenant",
      tenant: () => ORG,
    });

    await signIn(ALICE);
    await tags();

    expect(skips[0]).toMatchObject({ name: "tags", reason: "share" });
    expect(skips[0]?.detail).toContain("tags");
  });

  it("refuses a read outside the declared tables and stores nothing", async () => {
    const outside = bsb.kept(
      async (ctx) => {
        const read = await ctx.db.contacts.list({ select: ["id"] });

        return { contacts: read.ok ? read.data : read.error.table };
      },
      {
        name: "outside",
        tables: ["customers"],
        share: "tenant",
        tenant: () => ORG,
      },
    );

    await signIn(ALICE);
    const result = await outside();

    expect(result).toEqual({ contacts: "contacts" });
    expect(requests).toHaveLength(0);
    expect(set).not.toHaveBeenCalled();
    expect(skips[0]).toMatchObject({ name: "outside", reason: "share" });
  });

  it("refuses the raw client and function calls inside a shared fill", async () => {
    const raw = bsb.kept(
      async (ctx) => {
        const call = await ctx.db.$rpc("customer_stats" as never, {} as never);

        return call.ok;
      },
      {
        name: "raw",
        tables: ["customers"],
        share: "tenant",
        tenant: () => ORG,
      },
    );

    await signIn(ALICE);

    expect(await raw()).toBe(false);
    expect(requests).toHaveLength(0);
    expect(set).not.toHaveBeenCalled();
  });

  it("shares a function the provider declares and the entry lists", async () => {
    const payload = bsb.kept(
      async (ctx) => {
        const call = await ctx.db.$rpc(
          "customer_payload" as never,
          {} as never,
        );

        return call.ok ? call.data : call.error.code;
      },
      {
        name: "payload",
        functions: ["customer_payload"],
        share: "tenant",
        tenant: () => ORG,
      },
    );

    await signIn(ALICE);
    const first = await payload();
    await signIn(BOB);
    const second = await payload();

    expect(first).toEqual([{ id: "c1", name: "Acme" }]);
    expect(second).toEqual(first);
    expect(requests).toHaveLength(1);
    expect(requests[0]?.path).toBe("/rest/v1/rpc/customer_payload");
    expect(skips).toHaveLength(0);
  });

  it("refuses a listed function the provider doesn't declare", async () => {
    const stats = bsb.kept(
      async (ctx) =>
        (await ctx.db.$rpc("customer_stats" as never, {} as never)).ok,
      {
        name: "stats",
        functions: ["customer_stats"],
        share: "tenant",
        tenant: () => ORG,
      },
    );

    await signIn(ALICE);
    await stats();
    await signIn(BOB);
    await stats();

    expect(requests).toHaveLength(2);
    expect(skips[0]).toMatchObject({ name: "stats", reason: "share" });
    expect(skips[0]?.detail).toContain("sharedFunctions");
  });

  it("refuses a function that reads a row table", async () => {
    const notes = bsb.kept(
      async (ctx) =>
        (await ctx.db.$rpc("note_payload" as never, {} as never)).ok,
      {
        name: "note-payload",
        functions: ["note_payload"],
        share: "tenant",
        tenant: () => ORG,
      },
    );

    await signIn(ALICE);
    await notes();

    expect(skips[0]).toMatchObject({ name: "note-payload", reason: "share" });
    expect(skips[0]?.detail).toContain("notes");
  });

  it("refuses a declared function the entry doesn't list", async () => {
    const unlisted = bsb.kept(
      async (ctx) => {
        const call = await ctx.db.$rpc(
          "customer_payload" as never,
          {} as never,
        );

        return call.ok ? "read" : call.error.message;
      },
      {
        name: "unlisted",
        tables: ["customers"],
        share: "tenant",
        tenant: () => ORG,
      },
    );

    await signIn(ALICE);

    expect(await unlisted()).toContain("$rpc");
    expect(requests).toHaveLength(0);
    expect(set).not.toHaveBeenCalled();
  });

  describe("shareGuard", () => {
    const appDb = (claims: Readonly<Record<string, unknown>>) => {
      const fake = fakeSql();

      return {
        fake,
        db: createSupabase(shared).connect(postgresExecutor(fake.sql), {
          claims,
        }),
      };
    };

    it("gates an app-built db that runs as the caller", async () => {
      const own = appDb({ sub: ALICE, role: "authenticated" });

      const service = bsb.kept(
        async (ctx) => {
          const db = shareGuard(ctx, own.db);
          const rows = await db.customers.list({ select: ["id"] });
          const other = await db.contacts.list({ select: ["id"] });

          return { rows: rows.ok, other: other.ok ? "read" : other.error.code };
        },
        {
          name: "service",
          tables: ["customers"],
          share: "tenant",
          tenant: () => ORG,
        },
      );

      await signIn(ALICE);

      expect(await service()).toEqual({ rows: true, other: "SHARE_REFUSED" });
      expect(own.fake.calls).toHaveLength(1);
      expect(set).not.toHaveBeenCalled();
    });

    it("refuses a db for another user, the service role or no one", async () => {
      for (const claims of [
        { sub: BOB, role: "authenticated" },
        { sub: ALICE, role: "service_role" },
        {},
      ]) {
        const other = appDb(claims);

        const service = bsb.kept(
          async (ctx) => {
            const read = await shareGuard(ctx, other.db).customers.list();

            return read.ok ? "read" : read.error.message;
          },
          {
            name: "service-as-other",
            tables: ["customers"],
            share: "tenant",
            tenant: () => ORG,
          },
        );

        await signIn(ALICE);

        expect(await service()).toContain("doesn't run as the caller");
        expect(other.fake.calls).toHaveLength(0);
      }
    });

    it("returns the db unchanged outside a shared fill", async () => {
      const own = appDb({ sub: ALICE, role: "authenticated" });

      const perUser = bsb.kept(
        async (ctx) => shareGuard(ctx, own.db) === own.db,
        { name: "per-user", tables: ["customers"] },
      );

      await signIn(ALICE);

      expect(await perUser()).toBe(true);
    });
  });
});

describe("permissionsShareKey", () => {
  const hook = permissionsShareKey();

  const request = (
    userId: string,
    claims: Readonly<Record<string, unknown>>,
  ) => ({
    subject: { type: "user", id: userId, properties: { claims } },
    context: { tenant: ORG },
  });

  it("names the held keys of the tables' permissions", async () => {
    expect(
      await hook(undefined, ["customer.read"], request(ALICE, claimsOf(ALICE))),
    ).toBe("customer.read");
  });

  it("answers null for a truncated claim, a stale version and no grant", async () => {
    expect(
      await hook(
        undefined,
        ["customer.read"],
        request(ALICE, { ...claimsOf(ALICE), permissions_truncated: true }),
      ),
    ).toBeNull();

    const versions = { evict: () => undefined, get: () => Promise.resolve(2) };

    expect(
      await hook(undefined, ["customer.read"], {
        ...request(ALICE, { ...claimsOf(ALICE), authz_ver: 1 }),
        runtime: { versions },
      }),
    ).toBeNull();

    expect(
      await hook(undefined, ["customer.read"], request(CAROL, claimsOf(CAROL))),
    ).toBeNull();
  });
});

describe("expectTenantShare", () => {
  const caller = (userId: string) => ({
    userId,
    claims: claimsOf(userId),
    read: () => Promise.resolve([{ id: "c1" }]),
  });

  it("passes for two holders and an outsider", async () => {
    await expect(
      expectTenantShare({
        hooks,
        tenant: ORG,
        permissions: ["customer.read"],
        holders: [caller(ALICE), caller(BOB)],
        outsider: caller(CAROL),
      }),
    ).resolves.toBeUndefined();
  });

  it("fails when the holders read different rows", async () => {
    await expect(
      expectTenantShare({
        hooks,
        tenant: ORG,
        permissions: ["customer.read"],
        holders: [
          caller(ALICE),
          { ...caller(BOB), read: () => Promise.resolve([]) },
        ],
        outsider: caller(CAROL),
      }),
    ).rejects.toThrow(/different rows/);
  });
});
