import { NextRequest } from "next/server.js";
import { describe, expect, it, vi } from "vitest";

import { defineAuthorizer } from "../../src/core/authorizer.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { createNext, defineAction } from "../../src/next/index.ts";
import { resourceRoutes } from "../../src/next/resources.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const mocks = vi.hoisted(() => ({ headers: new Headers() }));

vi.mock("next/headers.js", () => ({
  headers: () => Promise.resolve(mocks.headers),
  cookies: () => Promise.resolve({ set: () => undefined }),
}));
vi.mock("next/server.js", async (original) => ({
  ...(await original<Record<string, unknown>>()),
  after: () => undefined,
}));

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};
const USER = "11111111-1111-4111-8111-111111111111";
const signer = await createTestSigner();

describe("resourceRoutes", () => {
  it("exports one handler for every method", () => {
    const serve = async (): Promise<Response> => new Response(null);
    expect(resourceRoutes(serve)).toEqual({
      GET: serve,
      POST: serve,
      PATCH: serve,
      PUT: serve,
      DELETE: serve,
    });
  });
});

describe("bs.resources()", () => {
  const authorizer = defineAuthorizer<"invite" | "export">({
    name: "test",
    key: (ref) => ref,
    evaluate: (request) =>
      request.action === "export"
        ? { outcome: "granted" }
        : { outcome: "approval-required", approval: { id: "apr_9" } },
  });
  const bs = createNext(defineSupabase(schema), {
    env,
    auth: { jwks: signer.jwks as never },
    authorizer,
  });
  const routes = bs.resources(
    {
      customers: {
        actions: {
          export: defineAction({
            method: "GET",
            path: "/export",
            permission: "export",
            handler: (ctx) => ({ table: ctx.table }),
          }),
          invite: {
            method: "POST",
            path: "/invite",
            permission: "invite",
            handler: () => undefined,
          },
          send: {
            method: "POST",
            path: "/{id}/send",
            status: 202,
            handler: (ctx, { id, data }) => ({
              id,
              data,
              user: ctx.context.actor?.id,
            }),
          },
        },
      },
    },
    { basePath: "/api" },
  );
  const call = async (path: string, method = "GET", body?: unknown) =>
    routes[method === "GET" ? "GET" : "POST"](
      new NextRequest(`https://app.test${path}`, {
        method,
        headers: {
          authorization: `Bearer ${await signer.sign({ sub: USER })}`,
          ...(body === undefined ? {} : { "content-type": "application/json" }),
        },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      }),
    );

  it("serves actions under the base path as the caller", async () => {
    const exported = await call("/api/customers/export");
    expect(exported.status).toBe(200);
    expect(await exported.json()).toEqual({ table: "customers" });
    const sent = await call("/api/customers/c1/send", "POST", { note: "hi" });
    expect(sent.status).toBe(202);
    expect(await sent.json()).toEqual({
      id: "c1",
      data: { note: "hi" },
      user: USER,
    });
    expect((await call("/api/customers/c1/send")).status).toBe(405);
  });

  it("answers 404 for a path outside the map", async () => {
    expect((await call("/api/nothing")).status).toBe(404);
    expect((await call("/elsewhere/customers")).status).toBe(404);
  });

  it("refuses an action whose permission needs an approval", async () => {
    const response = await call("/api/customers/invite", "POST");
    expect(response.status).toBe(403);
    expect(await response.json()).toMatchObject({
      code: "APPROVAL_REQUIRED",
      approval: { id: "apr_9" },
    });
  });

  it("checks roles and permissions on routes", async () => {
    mocks.headers = new Headers({
      authorization: `Bearer ${await signer.sign({ sub: USER })}`,
    });
    const request = () =>
      new NextRequest("https://app.test/api/x", { headers: mocks.headers });
    const segment = { params: Promise.resolve({}) };
    const byRole = bs.route(() => ({ ok: true }), { roles: ["admin"] });
    expect((await byRole(request(), segment)).status).toBe(403);
    const exporting = bs.route(() => ({ ok: true }), { permission: "export" });
    expect(await (await exporting(request(), segment)).json()).toEqual({
      ok: true,
    });
    const inviting = bs.route(() => ({ ok: true }), { permission: "invite" });
    expect(await (await inviting(request(), segment)).json()).toMatchObject({
      code: "APPROVAL_REQUIRED",
    });
  });

  it("types permissions from the authorizer", () => {
    // @ts-expect-error "delete" is not a permission of this authorizer
    bs.route(() => null, { permission: "delete" });
    // @ts-expect-error "delete" is not a permission of this authorizer
    bs.resources({ customers: { permissions: { list: "delete" } } });
  });
});
