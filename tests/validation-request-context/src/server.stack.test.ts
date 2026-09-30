import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";
import { parseEnv } from "better-supabase/env";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { createAppServer, withCron, withUserAuth } from "./supabase.ts";

const stack = {
  url: process.env["SUPABASE_URL"] ?? "http://127.0.0.1:55421",
  publishableKey:
    process.env["SUPABASE_PUBLISHABLE_KEY"] ??
    "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH",
  secretKey:
    process.env["SUPABASE_SECRET_KEY"] ??
    "sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz",
};
const CRON_KEY = "sb_secret_cron_validation";
const ACME = "00000000-0000-4000-8000-000000000001";

const up = await fetch(`${stack.url}/auth/v1/health`, {
  headers: { apikey: stack.publishableKey },
  signal: AbortSignal.timeout(1000),
}).then(
  (response) => response.ok,
  () => false,
);

const env = parseEnv({
  SUPABASE_URL: stack.url,
  SUPABASE_PUBLISHABLE_KEY: stack.publishableKey,
  SUPABASE_SECRET_KEYS: JSON.stringify({
    default: stack.secretKey,
    cron: CRON_KEY,
  }),
}).env!;

interface Session {
  readonly id: string;
  readonly accessToken: string;
  readonly cookies: Map<string, string>;
}

const admin = createClient(stack.url, stack.secretKey, {
  auth: { persistSession: false },
});

async function signIn(): Promise<Session & { remove: () => Promise<void> }> {
  const email = `request-context-${crypto.randomUUID()}@example.com`;
  const password = "correct horse battery staple";
  const { data, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    app_metadata: { tenant_id: ACME },
  });
  if (error) throw error;
  const cookies = new Map<string, string>();
  const client = createServerClient(stack.url, stack.publishableKey, {
    cookies: {
      getAll: () => [...cookies].map(([name, value]) => ({ name, value })),
      setAll: (writes) => {
        for (const write of writes) cookies.set(write.name, write.value);
      },
    },
  });
  const { data: session, error: signInError } =
    await client.auth.signInWithPassword({ email, password });
  if (signInError) throw signInError;
  return {
    id: data.user.id,
    accessToken: session.session.access_token,
    cookies,
    remove: async () => void (await admin.auth.admin.deleteUser(data.user.id)),
  };
}

const cookieHeader = (cookies: Map<string, string>) =>
  [...cookies]
    .map(([name, value]) => `${name}=${encodeURIComponent(value)}`)
    .join("; ");

describe.skipIf(!up)("request context on better-supabase", () => {
  const server = createAppServer(env, "web");
  const whoami = withUserAuth(server, async (_request, ctx) => {
    const customers = await ctx.db.customers
      .findMany({ select: ["organizationId"] })
      .orThrow();
    return {
      userId: ctx.auth.kind === "user" ? ctx.auth.user.id : null,
      source: ctx.auth.kind === "user" ? ctx.auth.source : null,
      orgs: [...new Set(customers.map((row) => row.organizationId))],
    };
  });
  const cron = withCron(server, (_request, ctx) => ({ auth: ctx.auth }));
  let a: Awaited<ReturnType<typeof signIn>>;
  let b: Awaited<ReturnType<typeof signIn>>;

  beforeAll(async () => {
    [a, b] = await Promise.all([signIn(), signIn()]);
  });
  afterAll(async () => {
    await Promise.all([a.remove(), b.remove()]);
  });

  const call = (
    handler: (request: Request) => Promise<Response>,
    headers: Record<string, string>,
  ) => handler(new Request("https://app.test/api", { headers }));

  it("verifies a bearer token and builds an RLS-scoped context", async () => {
    const response = await call(whoami, {
      authorization: `Bearer ${a.accessToken}`,
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      userId: a.id,
      source: "bearer",
      orgs: [ACME],
    });
  });

  it("prefers the bearer token over a cookie session", async () => {
    const response = await call(whoami, {
      authorization: `Bearer ${a.accessToken}`,
      cookie: cookieHeader(b.cookies),
    });
    expect(await response.json()).toMatchObject({
      userId: a.id,
      source: "bearer",
    });
  });

  it("falls back to the cookie session and verifies it the same way", async () => {
    const response = await call(whoami, { cookie: cookieHeader(b.cookies) });
    expect(await response.json()).toMatchObject({
      userId: b.id,
      source: "cookie",
    });
  });

  it("rejects a tampered token", async () => {
    const [head, body, signature] = a.accessToken.split(".");
    const claims = JSON.parse(Buffer.from(body!, "base64url").toString());
    const forged = Buffer.from(
      JSON.stringify({ ...claims, app_metadata: { tenant_id: "x" } }),
    ).toString("base64url");
    const response = await call(whoami, {
      authorization: `Bearer ${head}.${forged}.${signature}`,
    });
    expect(response.status).toBe(401);
    expect(response.headers.get("content-type")).toContain(
      "application/problem+json",
    );
  });

  it("answers MISSING_CREDENTIALS on an empty request", async () => {
    const response = await call(whoami, {});
    expect(response.status).toBe(401);
    expect(await response.json()).toMatchObject({
      code: "MISSING_CREDENTIALS",
    });
  });

  it("rejects an API key sent as a bearer token", async () => {
    const response = await call(whoami, {
      authorization: `Bearer ${stack.publishableKey}`,
    });
    expect(response.status).toBe(401);
  });

  it("accepts the cron secret key for cron routes and rejects the default one", async () => {
    const accepted = await call(cron, { apikey: CRON_KEY });
    expect(await accepted.json()).toEqual({
      auth: { kind: "service", keyName: "cron" },
    });
    expect((await call(cron, { apikey: stack.secretKey })).status).toBe(401);
    expect(
      (await call(cron, { authorization: `Bearer ${a.accessToken}` })).status,
    ).toBe(403);
  });

  it("does not need the secret key until the admin client is used", () => {
    const publicOnly = parseEnv({
      SUPABASE_URL: stack.url,
      SUPABASE_PUBLISHABLE_KEY: stack.publishableKey,
    }).env!;
    const lazy = createAppServer(publicOnly, "worker");
    expect(() => lazy.admin()).toThrow(/SUPABASE_SECRET_KEY/);
  });
});
