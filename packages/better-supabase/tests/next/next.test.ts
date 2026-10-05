import { notFound, redirect } from "next/navigation.js";
import { NextRequest, NextResponse } from "next/server.js";
import * as v from "valibot";
import { beforeEach, describe, expect, it, vi } from "vitest";

import type { Executor } from "../../src/core/executor.ts";

import { writeSession } from "../../src/auth/session.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { DbException, dbError } from "../../src/core/errors.ts";
import { defineReadSet } from "../../src/core/read-set.ts";
import { AsyncResult, ok } from "../../src/core/result.ts";
import {
  createNext,
  requireAal,
  shouldRefresh,
  tagFor,
} from "../../src/next/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const mocks = vi.hoisted(() => ({
  headers: new Headers(),
  updateTag: vi.fn<(tag: string) => void>(),
  revalidateTag: vi.fn<(tag: string, profile: string) => void>(),
  cacheTag: vi.fn<(...tags: string[]) => void>(),
  setCookie: vi.fn<(name: string, value: string, options: unknown) => void>(),
  after: vi.fn<(task: () => unknown) => void>(),
}));

vi.mock("next/headers.js", () => ({
  headers: () => Promise.resolve(mocks.headers),
  cookies: () => Promise.resolve({ set: mocks.setCookie }),
}));
vi.mock("next/server.js", async (original) => ({
  ...(await original<Record<string, unknown>>()),
  after: mocks.after,
}));
vi.mock("next/cache.js", () => ({
  updateTag: mocks.updateTag,
  revalidateTag: mocks.revalidateTag,
  cacheTag: mocks.cacheTag,
}));

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};
const NAME = "sb-abcdefghijklmnopqrst-auth-token";
const USER = "11111111-1111-4111-8111-111111111111";

const signer = await createTestSigner();

function page(
  init: {
    cookie?: string;
    headers?: Record<string, string>;
    method?: string;
  } = {},
): NextRequest {
  return new NextRequest("https://app.test/dashboard", {
    method: init.method ?? "GET",
    headers: {
      "sec-fetch-dest": "document",
      ...(init.cookie ? { cookie: init.cookie } : {}),
      ...init.headers,
    },
  });
}

function cookieFor(token: string, refresh: string): string {
  const exp = Math.floor(Date.now() / 1000) + 20;
  return writeSession([], NAME, {
    access_token: token,
    refresh_token: refresh,
    expires_at: exp,
  })
    .map((write) => `${write.name}=${encodeURIComponent(write.value)}`)
    .join("; ");
}

describe("shouldRefresh", () => {
  it("refreshes page loads, navigations and server actions only", () => {
    expect(shouldRefresh(page())).toBe(true);
    expect(
      shouldRefresh(page({ headers: { "sec-fetch-dest": "empty", rsc: "1" } })),
    ).toBe(true);
    expect(
      shouldRefresh(
        page({ method: "POST", headers: { "next-action": "abc" } }),
      ),
    ).toBe(true);
    expect(
      shouldRefresh(
        page({ headers: { rsc: "1", "next-router-prefetch": "1" } }),
      ),
    ).toBe(false);
    expect(shouldRefresh(page({ method: "POST" }))).toBe(false);
    expect(
      shouldRefresh(page({ headers: { "sec-fetch-dest": "image" } })),
    ).toBe(false);
  });
});

describe("createNext", () => {
  const fresh = vi.fn<typeof fetch>();
  const betterSupabase = defineSupabase(schema);
  const bs = createNext(betterSupabase, {
    env,
    auth: { jwks: signer.jwks as never, fetch: fresh },
  });

  beforeEach(() => {
    fresh.mockReset();
    mocks.updateTag.mockReset();
    mocks.revalidateTag.mockReset();
    mocks.headers = new Headers();
  });

  it("passes fresh sessions through untouched", async () => {
    const token = await signer.sign({ sub: USER });
    const exp = Math.floor(Date.now() / 1000) + 3600;
    const cookie = writeSession([], NAME, {
      access_token: token,
      refresh_token: "r",
      expires_at: exp,
    })
      .map((write) => `${write.name}=${encodeURIComponent(write.value)}`)
      .join("; ");
    const response = await bs.proxy(page({ cookie }));
    expect(response.headers.getSetCookie()).toEqual([]);
    expect(response.headers.get("x-middleware-next")).toBe("1");
    expect(fresh).not.toHaveBeenCalled();
  });

  it("refreshes in the proxy and forwards the new cookie to Server Components", async () => {
    const stale = await signer.sign({ sub: USER, expiresIn: 20 });
    const renewed = await signer.sign({ sub: USER });
    fresh.mockResolvedValue(
      Response.json({
        access_token: renewed,
        refresh_token: "next-2",
        expires_in: 3600,
      }),
    );
    const response = await bs.proxy(
      page({ cookie: cookieFor(stale, "next-1") }),
    );
    expect(fresh).toHaveBeenCalledTimes(1);
    expect(response.headers.getSetCookie()[0]).toMatch(
      new RegExp(`^${NAME}=base64-`),
    );
    expect(response.headers.get("cache-control")).toContain("no-store");
    expect(response.headers.get("x-middleware-override-headers")).toContain(
      "cookie",
    );
    expect(response.headers.get("x-middleware-request-cookie")).toContain(NAME);
  });

  it("keeps refreshed cookies on protect() responses", async () => {
    const stale = await signer.sign({ sub: USER, expiresIn: 20 });
    fresh.mockResolvedValue(
      Response.json({ msg: "Invalid Refresh Token" }, { status: 400 }),
    );
    const response = await bs.proxy(
      page({ cookie: cookieFor(stale, "next-dead") }),
      {
        protect: (auth, request) =>
          auth.kind === "user"
            ? undefined
            : NextResponse.redirect(new URL("/login", request.url)),
      },
    );
    expect(response.status).toBe(307);
    expect(response.headers.get("location")).toBe("https://app.test/login");
    expect(
      response.headers
        .getSetCookie()
        .every((cookie) => cookie.includes("Max-Age=0")),
    ).toBe(true);
  });

  describe("proxy composition", () => {
    const stale = () => signer.sign({ sub: USER, expiresIn: 20 });
    const renew = async () => {
      fresh.mockResolvedValue(
        Response.json({
          access_token: await signer.sign({ sub: USER }),
          refresh_token: "next-3",
          expires_in: 3600,
        }),
      );
    };

    it("merges refreshed cookies into a before() rewrite, keeping its request headers", async () => {
      await renew();
      const before = vi.fn((request: NextRequest) => {
        const headers = new Headers(request.headers);
        headers.set("x-next-intl-locale", "nl");
        return NextResponse.rewrite(new URL("/nl/dashboard", request.url), {
          request: { headers },
        });
      });
      const request = page({
        cookie: cookieFor(await stale(), "compose-1"),
        headers: { "accept-language": "nl" },
      });
      const response = await bs.proxy(request, { before });
      expect(before).toHaveBeenCalledWith(request);
      expect(response.headers.get("x-middleware-rewrite")).toBe(
        "https://app.test/nl/dashboard",
      );
      expect(response.headers.getSetCookie()[0]).toMatch(
        new RegExp(`^${NAME}=base64-`),
      );
      const listed = response.headers
        .get("x-middleware-override-headers")!
        .split(",");
      expect(listed).toEqual(
        expect.arrayContaining([
          "cookie",
          "x-next-intl-locale",
          "accept-language",
        ]),
      );
      expect(
        response.headers.get("x-middleware-request-x-next-intl-locale"),
      ).toBe("nl");
      expect(response.headers.get("x-middleware-request-cookie")).toContain(
        NAME,
      );
    });

    it("keeps before() redirects and adds cookies to them", async () => {
      await renew();
      const response = await bs.proxy(
        page({ cookie: cookieFor(await stale(), "compose-2") }),
        {
          before: (request) =>
            Response.redirect(new URL("/nl", request.url), 307),
        },
      );
      expect(response.status).toBe(307);
      expect(response.headers.get("location")).toBe("https://app.test/nl");
      expect(response.headers.getSetCookie()).toHaveLength(1);
      expect(response.headers.has("x-middleware-override-headers")).toBe(false);
    });

    it("never refreshes a prefetch, whatever before() does", async () => {
      const response = await bs.proxy(
        page({
          cookie: cookieFor(await stale(), "compose-3"),
          headers: { "next-router-prefetch": "1", rsc: "1" },
        }),
        {
          before: (request) =>
            NextResponse.rewrite(new URL("/nl", request.url)),
        },
      );
      expect(fresh).not.toHaveBeenCalled();
      expect(response.headers.getSetCookie()).toEqual([]);
      expect(response.headers.get("x-middleware-rewrite")).toBe(
        "https://app.test/nl",
      );
    });

    it("lets after() edit or replace the response and adds Server-Timing", async () => {
      const token = await signer.sign({ sub: USER });
      const cookie = writeSession([], NAME, {
        access_token: token,
        refresh_token: "r",
        expires_at: Math.floor(Date.now() / 1000) + 3600,
      })
        .map((write) => `${write.name}=${encodeURIComponent(write.value)}`)
        .join("; ");
      const edited = await bs.proxy(page({ cookie }), {
        after: (response, auth) => {
          response.headers.set(
            "x-user",
            auth.kind === "user" ? auth.user.id : "",
          );
        },
        serverTiming: true,
      });
      expect(edited.headers.get("x-user")).toBe(USER);
      expect(edited.headers.get("x-middleware-next")).toBe("1");
      expect(edited.headers.get("server-timing")).toMatch(
        /^bs-proxy;dur=\d+\.\d, bs-verify;dur=\d+\.\d$/,
      );
      const replaced = await bs.proxy(page(), {
        after: () => new Response("maintenance", { status: 503 }),
      });
      expect(replaced.status).toBe(503);
    });
  });

  it("forwards the client IP on refresh with a secret key", async () => {
    const withSecret = createNext(defineSupabase(schema), {
      env: { ...env, secretKey: "sb_secret_test" },
      auth: { jwks: signer.jwks as never, fetch: fresh },
    });
    fresh.mockResolvedValue(
      Response.json({
        access_token: await signer.sign({ sub: USER }),
        refresh_token: "ip-2",
        expires_in: 3600,
      }),
    );
    await withSecret.proxy(
      page({
        cookie: cookieFor(
          await signer.sign({ sub: USER, expiresIn: 20 }),
          "ip-1",
        ),
        headers: { "x-forwarded-for": "203.0.113.7, 10.0.0.1" },
      }),
    );
    const init = fresh.mock.calls[0]![1]!;
    expect(init.headers).toMatchObject({
      apikey: "sb_secret_test",
      "sb-forwarded-for": "203.0.113.7",
    });

    fresh.mockClear();
    await bs.proxy(
      page({
        cookie: cookieFor(
          await signer.sign({ sub: USER, expiresIn: 20 }),
          "ip-3",
        ),
        headers: { "x-forwarded-for": "203.0.113.7" },
      }),
    );
    expect(fresh.mock.calls[0]![1]!.headers).toMatchObject({
      apikey: "sb_publishable_test",
    });
    expect(fresh.mock.calls[0]![1]!.headers).not.toHaveProperty(
      "sb-forwarded-for",
    );
  });

  it("guards route handlers and answers with Problem Details", async () => {
    const handler = bs.route<{ id: string }>(async (_request, ctx) => {
      if (ctx.params.id === "missing")
        throw new DbException(dbError("not_found", "No customer"));
      if (ctx.params.id === "result")
        return { ok: false, data: null, error: dbError("conflict", "Taken") };
      if (ctx.params.id === "crash") throw new Error("secret detail");
      if (ctx.params.id === "redirect") redirect("/login");
      if (ctx.params.id === "gone") notFound();
      if (ctx.params.id === "wrapped") {
        try {
          redirect("/login");
        } catch (cause) {
          throw new Error("wrapped", { cause });
        }
      }
      return {
        id: ctx.params.id,
        user: ctx.auth.kind === "user" ? ctx.auth.user.id : null,
      };
    });
    const call = async (id: string, token?: string) =>
      handler(
        new NextRequest(
          `https://app.test/api/customers/${id}`,
          token ? { headers: { authorization: `Bearer ${token}` } } : {},
        ),
        {
          params: Promise.resolve({ id }),
        },
      );

    const anonymous = await call("1");
    expect(anonymous.status).toBe(401);
    expect(anonymous.headers.get("www-authenticate")).toBe(
      'Bearer realm="supabase"',
    );

    const token = await signer.sign({ sub: USER });
    expect(await (await call("1", token)).json()).toEqual({
      id: "1",
      user: USER,
    });
    const missing = await call("missing", token);
    expect(missing.status).toBe(404);
    expect(await missing.json()).toMatchObject({
      kind: "not_found",
      instance: "/api/customers/missing",
    });
    expect((await call("result", token)).status).toBe(409);
    const crash = await call("crash", token);
    expect(crash.status).toBe(500);
    expect(crash.headers.get("content-type")).toBe("application/problem+json");
    expect(JSON.stringify(await crash.json())).not.toContain("secret detail");
    await expect(call("redirect", token)).rejects.toMatchObject({
      digest: expect.stringContaining("NEXT_REDIRECT"),
    });
    await expect(call("gone", token)).rejects.toMatchObject({
      digest: expect.stringContaining("NEXT_HTTP_ERROR_FALLBACK;404"),
    });
    await expect(call("wrapped", token)).rejects.toMatchObject({
      digest: expect.stringContaining("NEXT_REDIRECT"),
    });
  });

  it("unwraps AsyncResults returned without await", async () => {
    const handler = bs.route<{ id: string }>((_request, ctx) =>
      ctx.params.id === "gone"
        ? AsyncResult.err(dbError("not_found", "Gone"))
        : AsyncResult.ok({ id: ctx.params.id }),
    );
    const token = await signer.sign({ sub: USER });
    const call = (id: string) =>
      handler(
        new NextRequest(`https://app.test/api/customers/${id}`, {
          headers: { authorization: `Bearer ${token}` },
        }),
        { params: Promise.resolve({ id }) },
      );
    expect(await (await call("c1")).json()).toEqual({ id: "c1" });
    expect((await call("gone")).status).toBe(404);
  });

  it("hands event sends a route or action started to after()", async () => {
    mocks.after.mockReset();
    mocks.headers = new Headers({
      authorization: `Bearer ${await signer.sign({ sub: USER })}`,
    });
    let release: () => void = () => undefined;
    const sending = (): void => {
      betterSupabase.events.track(
        new Promise<void>((resolve) => {
          release = resolve;
        }),
      );
    };
    const route = bs.route(() => {
      sending();
      return { ok: true };
    });
    await route(
      new NextRequest("https://app.test/api/x", { headers: mocks.headers }),
      {
        params: Promise.resolve({}),
      },
    );
    expect(mocks.after).toHaveBeenCalledTimes(1);
    let flushed = false;
    void Promise.resolve(mocks.after.mock.calls[0]![0]()).then(() => {
      flushed = true;
    });
    await Promise.resolve();
    expect(flushed).toBe(false);
    release();
    await betterSupabase.events.settled();
    await Promise.resolve();
    expect(flushed).toBe(true);

    const action = bs.action({}, () => {
      sending();
      return "done";
    });
    expect(await action(undefined)).toMatchObject({ ok: true });
    expect(mocks.after).toHaveBeenCalledTimes(2);
    release();
    await bs.route(() => ({ ok: true }))(
      new NextRequest("https://app.test/api/x", { headers: mocks.headers }),
      { params: Promise.resolve({}) },
    );
    expect(mocks.after).toHaveBeenCalledTimes(2);
  });

  it("runs actions with validation, FormData and serializable results", async () => {
    const save = bs.action(
      {
        input: v.object({
          name: v.pipe(v.string(), v.minLength(2)),
          tags: v.optional(v.array(v.string())),
        }),
      },
      async (input, ctx) => {
        if (input.name === "boom")
          throw new DbException(dbError("conflict", "Taken"));
        return {
          ...input,
          by: ctx.auth.kind === "user" ? ctx.auth.user.id : null,
        };
      },
    );

    expect(await save({ name: "Acme" })).toMatchObject({
      ok: false,
      error: { kind: "unauthorized" },
    });

    mocks.headers = new Headers({
      authorization: `Bearer ${await signer.sign({ sub: USER })}`,
    });
    expect(await save({ name: "Acme" })).toEqual({
      ok: true,
      data: { name: "Acme", by: USER },
      error: null,
    });

    const form = new FormData();
    form.append("name", "Form Co");
    form.append("tags", "a");
    form.append("tags", "b");
    expect(await save(form)).toMatchObject({
      ok: true,
      data: { name: "Form Co", tags: ["a", "b"] },
    });

    expect(await save({ name: "x" })).toMatchObject({
      ok: false,
      error: { kind: "validation", issues: [{ path: ["name"] }] },
    });
    expect(await save({ name: "boom" })).toMatchObject({
      ok: false,
      error: { kind: "conflict" },
    });
  });

  it("reads the session as serializable data without the token", async () => {
    expect(await bs.session()).toEqual({ kind: "anon", reason: "none" });

    const token = await signer.sign({
      sub: USER,
      email: "ada@example.com",
      user_role: "admin",
    });
    mocks.headers = new Headers({ authorization: `Bearer ${token}` });
    const session = await bs.session();
    expect(session).toMatchObject({
      kind: "user",
      user: { id: USER, email: "ada@example.com" },
      claims: { sub: USER, user_role: "admin" },
    });
    expect(JSON.stringify(session)).not.toContain(token);
    expect(structuredClone(session)).toEqual(session);

    mocks.headers = new Headers({ authorization: "Bearer not-a-jwt" });
    expect(await bs.session()).toMatchObject({
      kind: "invalid",
      error: { kind: "unauthorized" },
    });
  });

  it("requires a second factor on routes, actions and proxied pages", async () => {
    const aal1 = await signer.sign({
      sub: USER,
      aal: "aal1",
      amr: [{ method: "password", timestamp: 1 }],
    });
    const aal2 = await signer.sign({
      sub: USER,
      aal: "aal2",
      amr: [
        { method: "totp", timestamp: 2 },
        { method: "password", timestamp: 1 },
      ],
    });

    mocks.headers = new Headers({ authorization: `Bearer ${aal2}` });
    expect(await bs.session()).toMatchObject({
      aal: "aal2",
      amr: [{ method: "totp" }, { method: "password" }],
    });

    const handler = bs.route(() => ({ ok: true }), { aal: "aal2" });
    const call = (token: string) =>
      handler(
        new NextRequest("https://app.test/api/billing", {
          headers: { authorization: `Bearer ${token}` },
        }),
        { params: Promise.resolve({}) },
      );
    const denied = await call(aal1);
    expect(denied.status).toBe(403);
    expect(await denied.json()).toMatchObject({
      kind: "forbidden",
      code: "INSUFFICIENT_AAL",
      required: "aal2",
    });
    expect((await call(aal2)).status).toBe(200);

    const rotate = bs.action({ aal: "aal2" }, () => "rotated");
    mocks.headers = new Headers({ authorization: `Bearer ${aal1}` });
    expect(await rotate(undefined)).toMatchObject({
      ok: false,
      error: { kind: "forbidden", required: "aal2" },
    });
    mocks.headers = new Headers({ authorization: `Bearer ${aal2}` });
    expect(await rotate(undefined)).toEqual({
      ok: true,
      data: "rotated",
      error: null,
    });

    const exp = Math.floor(Date.now() / 1000) + 3600;
    const cookie = (token: string) =>
      writeSession([], NAME, {
        access_token: token,
        refresh_token: "r",
        expires_at: exp,
      })
        .map((write) => `${write.name}=${encodeURIComponent(write.value)}`)
        .join("; ");
    const protect = requireAal("aal2", {
      redirect: "/mfa",
      match: (path) => path.startsWith("/dashboard"),
    });
    const redirected = await bs.proxy(page({ cookie: cookie(aal1) }), {
      protect,
    });
    expect(redirected.status).toBe(307);
    expect(redirected.headers.get("location")).toBe(
      "https://app.test/mfa?next=%2Fdashboard",
    );
    const passed = await bs.proxy(page({ cookie: cookie(aal2) }), {
      protect,
    });
    expect(passed.headers.get("x-middleware-next")).toBe("1");
  });

  it("never refreshes an expiring cookie session, and keeps it valid until exp", async () => {
    const token = await signer.sign({ sub: USER });
    mocks.headers = new Headers({ cookie: cookieFor(token, "refresh-1") });
    expect(await bs.session()).toMatchObject({ kind: "user" });
    expect(fresh).not.toHaveBeenCalled();
  });

  it("collects database calls per request id when debug is on", async () => {
    const rest = vi
      .spyOn(globalThis, "fetch")
      .mockImplementation(() => Promise.resolve(Response.json([])));
    try {
      const debugged = createNext(defineSupabase(schema), {
        env,
        cacheTags: false,
        auth: { jwks: signer.jwks as never, fetch: fresh },
        debug: { enabled: true },
      });
      const proxied = await debugged.proxy(page());
      const id = proxied.headers.get("x-bs-request-id")!;
      expect(id).toMatch(/^[0-9a-f-]{36}$/);
      expect(proxied.headers.get("x-bs-stats")).toBe(`/api/bs-stats?id=${id}`);
      expect(proxied.headers.get("x-middleware-request-x-bs-request-id")).toBe(
        id,
      );

      mocks.headers = new Headers({ "x-bs-request-id": id });
      const ctx = await debugged.context();
      await Promise.all([ctx.db.customers.findMany(), ctx.db.notes.findMany()]);
      await ctx.db.tags.findMany();

      const stats = await debugged.debugRoute()(
        new Request(`https://app.test/api/bs-stats?id=${id}`),
      );
      expect(stats.headers.get("x-bs-db-calls")).toMatch(/^3;2;/);
      expect(await stats.json()).toMatchObject({
        calls: 3,
        waves: 2,
        tables: ["customers", "notes", "tags"],
      });
      const cached = await debugged.debugRoute()(
        new Request("https://app.test/api/bs-stats?id=nope"),
      );
      expect(await cached.json()).toMatchObject({ calls: 0, waves: 0 });

      const handler = debugged.route(async (_request, routeCtx) => {
        await routeCtx.db.customers.findMany();
        return { ok: true };
      });
      const routed = await handler(
        new NextRequest("https://app.test/api/x", {
          headers: {
            authorization: `Bearer ${await signer.sign({ sub: USER })}`,
          },
        }),
        { params: Promise.resolve({}) },
      );
      expect(routed.headers.get("x-bs-db-calls")).toMatch(/^1;1;/);
    } finally {
      rest.mockRestore();
    }
  });

  it("collects nothing without debug", async () => {
    const proxied = await bs.proxy(page());
    expect(proxied.headers.get("x-bs-request-id")).toBeNull();
    const reply = await bs.debugRoute()(
      new Request("https://app.test/api/bs-stats?id=x"),
    );
    expect(reply.status).toBe(404);
  });

  it("invalidates table and row tags after mutations", async () => {
    const executor: Executor = {
      name: "fake",
      execute: () =>
        Promise.resolve(ok({ rows: [{ id: "c1", name: "Acme" }], count: 1 })),
    };
    mocks.updateTag.mockImplementation(() => {
      throw new Error("updateTag can only be called from a Server Action");
    });
    await betterSupabase
      .connect(executor)
      .customers.update("c1", { name: "Acme" })
      .orThrow();
    expect(mocks.revalidateTag.mock.calls).toEqual([
      [tagFor("customers"), "max"],
      [tagFor("customers", "c1"), "max"],
    ]);

    bs.cacheTag("customers", "c1");
    expect(mocks.cacheTag).toHaveBeenCalledWith(
      "bs:customers",
      "bs:customers:c1",
    );

    bs.cacheTags(
      betterSupabase.spec.customers.findById("c1", {
        include: { notes: true },
      }),
    );
    expect(mocks.cacheTag).toHaveBeenLastCalledWith(
      "bs:customers",
      "bs:notes",
      "bs:customers:c1",
    );

    bs.cacheTags([
      betterSupabase.spec.tags.count(),
      betterSupabase.spec.notes.count(),
    ]);
    expect(mocks.cacheTag).toHaveBeenLastCalledWith("bs:tags", "bs:notes");

    bs.cacheTags(
      defineReadSet(betterSupabase, "chrome", {}, (s) => ({
        customers: s.customers.count(),
        notes: s.notes.findMany({ include: { customer: true } }),
      })),
    );
    expect(mocks.cacheTag).toHaveBeenLastCalledWith("bs:customers", "bs:notes");
  });

  it("invalidates each tag once when createNext runs again for a definition", async () => {
    createNext(betterSupabase, { env, auth: { jwks: signer.jwks as never } });
    const executor: Executor = {
      name: "fake",
      execute: () => Promise.resolve(ok({ rows: [{ id: "c1" }], count: 1 })),
    };
    await betterSupabase
      .connect(executor)
      .customers.update("c1", { name: "Acme" })
      .orThrow();
    expect(mocks.updateTag.mock.calls).toEqual([
      [tagFor("customers")],
      [tagFor("customers", "c1")],
    ]);
  });
});

describe("next.liveCount", () => {
  const betterSupabase = defineSupabase(schema);
  const bs = createNext(betterSupabase, {
    env,
    auth: { jwks: signer.jwks as never },
  });
  const spec = betterSupabase.spec.notes.count({
    where: { body: { contains: "x" } },
  });

  it("returns a serializable seed from the db passed in", async () => {
    const run = vi.fn(() => AsyncResult.ok(4));
    const seed = await bs.liveCount(spec, { $run: run });
    expect(seed).toEqual({ spec, count: 4 });
    expect(JSON.parse(JSON.stringify(seed))).toEqual(seed);
    expect(run).toHaveBeenCalledWith(spec);
  });

  it("gives count null instead of throwing", async () => {
    const seed = await bs.liveCount(spec, {
      $run: () => AsyncResult.err(dbError("forbidden", "no")),
    });
    expect(seed.count).toBeNull();
  });
});

describe("read replicas", () => {
  const READ_URL = "https://abcdefghijklmnopqrst-all.supabase.co";

  it("keeps the next requests on the primary after a write", async () => {
    const seen: string[] = [];
    const fetch = vi
      .spyOn(globalThis, "fetch")
      .mockImplementation((input, init) => {
        seen.push(`${init?.method ?? "GET"} ${new URL(String(input)).host}`);
        return Promise.resolve(
          Response.json(init?.method === "POST" ? [{ id: "c1" }] : []),
        );
      });
    const token = await signer.sign({ sub: USER });
    const bs = createNext(defineSupabase(schema), {
      env: { ...env, readUrl: READ_URL },
      auth: { jwks: signer.jwks as never },
      cacheTags: false,
      replicas: { pinMs: 2000 },
    });
    const request = (method: string) =>
      new NextRequest("https://app.test/api/customers", {
        method,
        headers: { authorization: `Bearer ${token}` },
      });
    const segment = { params: Promise.resolve({}) };
    try {
      const read = bs.route((_request, { db }) =>
        db.customers.findMany({ select: ["id"] }),
      );
      const write = bs.route((_request, { db }) =>
        db.customers.create(
          { name: "Acme", organizationId: "o1" },
          { select: ["id"] },
        ),
      );
      expect(
        (await read(request("GET"), segment)).headers.get("set-cookie"),
      ).toBeNull();
      const cookie = (await write(request("POST"), segment)).headers.get(
        "set-cookie",
      );
      expect(cookie).toMatch(
        /^bs-primary-until=\d+; Max-Age=2; Path=\/; HttpOnly; SameSite=Lax$/,
      );

      mocks.headers = new Headers({ authorization: `Bearer ${token}` });
      mocks.setCookie.mockReset();
      const action = bs.action({}, (_input, { db }) =>
        db.customers.create(
          { name: "Acme", organizationId: "o1" },
          { select: ["id"] },
        ),
      );
      expect(await action(undefined)).toMatchObject({ ok: true });
      expect(mocks.setCookie).toHaveBeenCalledWith(
        "bs-primary-until",
        expect.stringMatching(/^\d+$/),
        { path: "/", maxAge: 2, httpOnly: true, sameSite: "lax" },
      );
      expect(seen).toEqual([
        "GET abcdefghijklmnopqrst-all.supabase.co",
        "POST abcdefghijklmnopqrst.supabase.co",
        "POST abcdefghijklmnopqrst.supabase.co",
      ]);
    } finally {
      fetch.mockRestore();
    }
  });
});
