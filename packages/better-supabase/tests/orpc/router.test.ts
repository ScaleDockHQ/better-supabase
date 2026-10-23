import { openapi } from "@orpc/openapi";
import { OpenAPIHandler } from "@orpc/openapi/fetch";
import { os } from "@orpc/server";
import { describe, expect, it } from "vitest";

import type { BlockContext } from "../../src/blocks/index.ts";
import type { Result } from "../../src/core/result.ts";
import type { OrpcRequestContext } from "../../src/orpc/index.ts";

import { defineBlock, defineBlocks } from "../../src/blocks/index.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { dbError } from "../../src/core/errors.ts";
import { err, ok } from "../../src/core/result.ts";
import { createOrpc } from "../../src/orpc/index.ts";
import { defineApi } from "../../src/spec/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";

const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};

const signer = await createTestSigner();

interface Invoice {
  readonly id: string;
  readonly total: number;
  readonly issuedAt?: string;
}

const invoicing = defineBlock({
  name: "invoicing",
  category: "work",
  create: (_context: BlockContext) => ({
    async create(input: { readonly total: number }): Promise<Result<Invoice>> {
      return input.total < 0
        ? err(dbError("forbidden", "total must be positive"))
        : ok({ id: "inv_1", total: input.total });
    },
    async issue(id: string, when: string): Promise<Result<Invoice>> {
      return ok({ id, total: 10, issuedAt: when });
    },
    relayRoute: () => () => new Response(null),
    drafts: {
      async list(): Promise<Result<readonly Invoice[]>> {
        return ok([{ id: "draft_1", total: 1 }]);
      },
    },
  }),
});

const blockSet = defineBlocks(
  { invoicing: { schema: "better_supabase", options: {} } },
  { invoicing },
);

const betterSupabase = defineSupabase(schema).blocks(blockSet);

/** PostgREST: one customer for reads, a total of 3 for counts. */
const postgrest = async (
  input: RequestInfo | URL,
  init?: RequestInit,
): Promise<Response> => {
  const request = new Request(input, init);
  const { pathname } = new URL(request.url);

  if (!pathname.startsWith("/rest/v1/customers")) {
    return Response.json([], { status: 404 });
  }

  if (request.method === "HEAD") {
    return new Response(null, { headers: { "content-range": "*/3" } });
  }

  return Response.json([{ id: "c1", name: "Acme" }], {
    headers: { "content-range": "0-0/1" },
  });
};

describe("bsb.router", () => {
  const bsb = createOrpc(betterSupabase, {
    env,
    auth: { jwks: signer.jwks },
    fetch: postgrest,
  });

  const api = defineApi(betterSupabase, {
    info: { title: "Test", version: "1.0.0" },
    basePath: "/api",
  });

  const { procedures, routes } = bsb.router(api, {
    guard: { allow: ["user"] },
    meta: openapi,
  });

  const handle = bsb.fetchHandler(
    new OpenAPIHandler(os.$context<OrpcRequestContext>().router(procedures)),
  );

  const send = async (
    method: string,
    path: string,
    body?: unknown,
    token?: string,
  ) =>
    handle(
      new Request(`https://app.test/api${path}`, {
        method,
        headers: {
          "content-type": "application/json",
          ...(token ? { authorization: `Bearer ${token}` } : {}),
        },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      }),
    );

  it("routes every table and block instance from the API model", () => {
    const paths = routes.map((route) => `${route.method} ${route.path}`);

    expect(paths).toContain("GET /api/customers");
    expect(paths).toContain("GET /api/customers/{id}");
    expect(paths).toContain("POST /api/customers/count");
    expect(paths).toContain("POST /api/customers/upsert");
    expect(paths).toContain("POST /api/invoicing/create");
    expect(paths).toContain("POST /api/invoicing/issue");
    expect(paths).toContain("POST /api/invoicing/drafts/list");
    expect(paths).not.toContain("POST /api/invoicing/relayRoute");

    expect(
      routes.find((route) => route.operationId === "invoicing.issue"),
    ).toMatchObject({ inputStructure: "compact", successStatus: 200 });
    expect(
      routes.find((route) => route.operationId === "createCustomers"),
    ).toMatchObject({ inputStructure: "detailed", successStatus: 201 });
  });

  it("serves table operations and verbs through the repository", async () => {
    const token = await signer.sign({ sub: "u1" });

    const list = await send("GET", "/customers?limit=1", undefined, token);
    expect(list.status).toBe(200);
    expect(await list.json()).toMatchObject({
      items: [{ id: "c1", name: "Acme" }],
    });

    const count = await send("POST", "/customers/count", {}, token);
    expect(count.status).toBe(200);
    expect(await count.json()).toBe(3);
  });

  it("serves block verbs, spreading a tuple and reaching sub-clients", async () => {
    const token = await signer.sign({ sub: "u1" });

    const created = await send(
      "POST",
      "/invoicing/create",
      { total: 5 },
      token,
    );

    expect(await created.json()).toEqual({ id: "inv_1", total: 5 });

    const issued = await send(
      "POST",
      "/invoicing/issue",
      ["inv_1", "2026-10-21"],
      token,
    );

    expect(await issued.json()).toEqual({
      id: "inv_1",
      total: 10,
      issuedAt: "2026-10-21",
    });

    const drafts = await send("POST", "/invoicing/drafts/list", [], token);
    expect(await drafts.json()).toEqual([{ id: "draft_1", total: 1 }]);
  });

  it("guards the caller and maps a DbError", async () => {
    const token = await signer.sign({ sub: "u1" });
    const anonymous = await send("POST", "/invoicing/create", { total: 5 });
    expect(anonymous.status).toBe(401);

    const refused = await send(
      "POST",
      "/invoicing/create",
      { total: -1 },
      token,
    );

    expect(refused.status).toBe(403);
  });

  it("documents the same operations it serves", () => {
    const served = new Set(routes.map((route) => route.operationId));

    expect(
      api.model.operations
        .map((operation) => operation.id)
        .filter((id) => !served.has(id)),
    ).toEqual([]);
  });
});
