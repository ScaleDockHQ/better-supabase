import { beforeEach, describe, expect, it, vi } from "vitest";

import { defineAuthorizer } from "../../src/core/authorizer.ts";
import { createSupabase } from "../../src/core/define.ts";
import { dbError } from "../../src/core/errors.ts";
import { AsyncResult, ok } from "../../src/core/result.ts";
import { createNext } from "../../src/next/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const mocks = vi.hoisted(() => ({
  headers: new Headers(),
  cacheTag: vi.fn<(...tags: string[]) => void>(),
}));

vi.mock(import("next/headers.js"), () => ({
  headers: () => Promise.resolve(mocks.headers),
  cookies: () => Promise.resolve({ set: vi.fn(), getAll: () => [] } as never),
}));

vi.mock(import("next/cache.js"), () => ({
  updateTag: vi.fn(),
  revalidateTag: vi.fn(),
  cacheTag: mocks.cacheTag,
  cacheLife: () => undefined,
  io: () => Promise.resolve(),
}));

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const USER = "11111111-1111-4111-8111-111111111111";
const signer = await createTestSigner();

const organizations = new Map([
  ["acme", { id: "org-1", slug: "acme" }],
  ["other", { id: "org-2", slug: "other" }],
]);

const resolveSlug = vi.fn((slug: string) => organizations.get(slug) ?? null);

const bsb = createNext(createSupabase(schema), {
  env: {
    url: PROJECT_URL,
    publishableKey: "sb_publishable_test",
    jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
  },
  auth: { jwks: signer.jwks },
  authorizer: defineAuthorizer({
    name: "agenda",
    key: (ref: string) => ref,
    evaluate: (request) =>
      request.context.tenant === "org-1" && request.action === "agenda.read"
        ? { outcome: "granted" }
        : { outcome: "denied" },
  }),
  tenants: { by: "slug", resolve: { slug: resolveSlug } },
});

async function signIn(tenant?: string): Promise<void> {
  mocks.headers = new Headers({
    authorization: `Bearer ${await signer.sign({
      sub: USER,
      ...(tenant === undefined ? {} : { tenant_id: tenant }),
    })}`,
  });
}

async function digest(run: () => Promise<unknown>): Promise<string> {
  try {
    await run();
  } catch (cause) {
    return (cause as { digest?: string }).digest ?? String(cause);
  }

  return "resolved";
}

beforeEach(() => {
  mocks.headers = new Headers();
  mocks.cacheTag.mockReset();
  resolveSlug.mockClear();
});

describe("Result.orNull and Result.or", () => {
  it("turns not_found into null or the fallback and throws other errors", async () => {
    expect(await AsyncResult.ok(1).orNull()).toBe(1);

    expect(
      await AsyncResult.err<number>(dbError("not_found", "x")).orNull(),
    ).toBeNull();

    expect(await AsyncResult.err<number>(dbError("not_found", "x")).or(0)).toBe(
      0,
    );

    await expect(
      AsyncResult.err<number>(dbError("forbidden", "x")).orNull(),
    ).rejects.toMatchObject({ error: { kind: "forbidden" } });
    expect(await AsyncResult.from(() => Promise.resolve(ok(2))).or(0)).toBe(2);
  });
});

describe("bsb.auth()", () => {
  it("refuses a caller without a session with unauthorized", async () => {
    expect(await digest(() => bsb.auth())).toBe("NEXT_HTTP_ERROR_FALLBACK;404");
  });

  it("returns the db, the user and can for a signed-in caller", async () => {
    await signIn();
    const scope = await bsb.auth();

    expect(scope.user.id).toBe(USER);
    expect(scope.db).toBeDefined();
    expect(scope.session.kind).toBe("user");
  });
});

describe("bsb.tenant(ref)", () => {
  it("resolves a slug through the app's resolver and returns the record", async () => {
    await signIn("org-1");

    const scope = await bsb.tenant("acme", "agenda.read", {
      tables: ["customers"],
    });

    expect(scope.tenant).toEqual({ id: "org-1", slug: "acme" });
    expect(scope.granted).toBe(true);
    expect(await scope.can("agenda.read")).toBe(true);
    expect(await scope.can("agenda.delete")).toBe(false);
    expect(mocks.cacheTag).toHaveBeenCalledWith(
      `bsb:session:${USER}`,
      "bsb:customers@org-1",
      "bsb:customers@*",
    );
  });

  it("reads { id } and { slug } refs and gives two refs two cache entries", async () => {
    await signIn("org-1");
    await bsb.tenant({ slug: "acme" }, undefined, { tables: ["customers"] });
    await bsb.tenant({ id: "org-1" }, undefined, { tables: ["customers"] });

    expect(resolveSlug).toHaveBeenCalledOnce();
  });

  it("ends the render with notFound for an unknown tenant", async () => {
    await signIn("org-1");
    expect(await digest(() => bsb.tenant("nope", "agenda.read"))).toBe(
      "NEXT_HTTP_ERROR_FALLBACK;404",
    );
  });

  it("never hands a non-member the db", async () => {
    await signIn("org-1");
    expect(await digest(() => bsb.tenant("other", "agenda.read"))).not.toBe(
      "resolved",
    );
  });

  it("refuses a missing permission", async () => {
    await signIn("org-1");
    expect(await digest(() => bsb.tenant("acme", "agenda.delete"))).not.toBe(
      "resolved",
    );
  });

  it("keeps bsb.tenant() without arguments as the root param getter", async () => {
    expect(await bsb.tenant()).toBeUndefined();
  });
});

describe("bsb.activeTenant()", () => {
  it("ends the render with notFound when the route names no tenant", async () => {
    await signIn("org-1");
    expect(await digest(() => bsb.activeTenant("agenda.read"))).toBe(
      "NEXT_HTTP_ERROR_FALLBACK;404",
    );
  });
});

describe("gate: true", () => {
  const fetchMock = vi.fn(() =>
    Promise.resolve(
      new Response("[]", {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    ),
  );

  beforeEach(() => {
    fetchMock.mockClear();
    vi.stubGlobal("fetch", fetchMock);
  });

  it("returns the scope before the check and lets a member read", async () => {
    await signIn("org-1");

    const scope = await bsb.tenant("acme", "agenda.read", {
      tables: ["customers"],
      gate: true,
    });

    expect(scope.tenant.id).toBe("org-1");
    expect(scope.user).toBeDefined();
    await scope.db.customers.list();
    expect(fetchMock).toHaveBeenCalledOnce();
  });

  it("settles a non-member's read with the refusal, not rows", async () => {
    await signIn("org-1");

    const scope = await bsb.tenant("other", "agenda.read", {
      tables: ["customers"],
      gate: true,
    });

    const result = await scope.db.customers.list();

    expect(result.ok ? "rows" : result.error.kind).toBe("not_found");
  });
});

describe("bsb.shared()", () => {
  it("runs the read once the caller passes the check", async () => {
    await signIn("org-1");

    const read = vi.fn((tenant: { id: string }) => Promise.resolve(tenant.id));

    expect(await bsb.shared("acme", "agenda.read", read)).toBe("org-1");
    expect(read).toHaveBeenCalledOnce();
  });

  it("never runs the read for a non-member", async () => {
    await signIn("org-1");

    const read = vi.fn(() => Promise.resolve("rows"));

    expect(
      await digest(() => bsb.shared("other", "agenda.read", read)),
    ).not.toBe("resolved");
    expect(read).not.toHaveBeenCalled();
  });
});
