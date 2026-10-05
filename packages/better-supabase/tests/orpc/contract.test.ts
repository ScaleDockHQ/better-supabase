import { oc } from "@orpc/contract";
import { openapi } from "@orpc/openapi";
import { OpenAPIHandler } from "@orpc/openapi/fetch";
import { implement } from "@orpc/server";
import { Hono } from "hono";
import * as v from "valibot";
import { describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { dbError } from "../../src/core/errors.ts";
import { err, ok, type Result } from "../../src/core/result.ts";
import { createOrpc, type OrpcRequestContext } from "../../src/orpc/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const env = {
  url: PROJECT_URL,
  publishableKey: "sb_publishable_test",
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};
const USER = "11111111-1111-4111-8111-111111111111";
const signer = await createTestSigner();

const customer = v.object({ id: v.string(), name: v.string() });

/** The contract a client package shares with the server, without its implementation. */
const contract = {
  me: oc
    .meta(openapi({ method: "GET", path: "/me" }))
    .output(v.object({ id: v.nullable(v.string()) })),
  customers: {
    get: oc
      .meta(openapi({ method: "GET", path: "/customers/{id}" }))
      .input(v.object({ id: v.string() }))
      .output(customer),
    rename: oc
      .meta(openapi({ method: "PATCH", path: "/customers/{id}" }))
      .input(v.object({ id: v.string(), name: v.string() }))
      .output(customer),
  },
};

type Customer = { id: string; name: string };
const failed = (
  kind: "not_found" | "forbidden",
  message: string,
): Result<Customer> => err(dbError(kind, message));

describe("a contract-first router under Hono", () => {
  const bs = createOrpc(defineSupabase(schema), {
    env,
    auth: { jwks: signer.jwks as never },
  });
  const os = implement(contract)
    .$context<OrpcRequestContext>()
    .use(bs.middleware());
  const router = os.router({
    me: os.me.handler(({ context }) => ({
      id: context.auth.kind === "user" ? context.auth.user.id : null,
    })),
    customers: {
      get: os.customers.get.handler(({ input }) =>
        input.id === "missing"
          ? bs.unwrap(failed("not_found", "No such customer"))
          : bs.unwrap(ok({ id: input.id, name: "Acme" })),
      ),
      rename: os.customers.rename.handler(() =>
        bs.unwrap(
          failed("forbidden", "new row violates row-level security policy"),
        ),
      ),
    },
  });
  const handle = bs.fetchHandler(new OpenAPIHandler(router), {
    prefix: "/api",
  });
  const app = new Hono().all("/api/*", (c) => handle(c.req.raw));

  const call = async (path: string, init: RequestInit = {}, token?: string) =>
    app.request(path, {
      ...init,
      headers: {
        ...(token ? { authorization: `Bearer ${token}` } : {}),
        ...(init.body ? { "content-type": "application/json" } : {}),
      },
    });

  it("serves the contract's routes with the caller in context", async () => {
    const token = await signer.sign({ sub: USER });
    const me = await call("/api/me", {}, token);
    expect(me.status).toBe(200);
    expect(await me.json()).toEqual({ id: USER });
    const found = await call("/api/customers/c1", {}, token);
    expect(await found.json()).toEqual({ id: "c1", name: "Acme" });
  });

  it("rejects an anonymous caller before the handler runs", async () => {
    const response = await call("/api/me");
    expect(response.status).toBe(401);
    expect(await response.json()).toMatchObject({
      code: "UNAUTHORIZED",
      data: { kind: "unauthorized" },
    });
  });

  it("answers DbErrors with their status and Problem Details", async () => {
    const token = await signer.sign({ sub: USER });
    const missing = await call("/api/customers/missing", {}, token);
    expect(missing.status).toBe(404);
    expect(await missing.json()).toMatchObject({
      code: "NOT_FOUND",
      data: { kind: "not_found", detail: "No such customer" },
    });
    const denied = await call(
      "/api/customers/c1",
      { method: "PATCH", body: JSON.stringify({ name: "B" }) },
      token,
    );
    expect(denied.status).toBe(403);
    expect(await denied.json()).toMatchObject({
      code: "FORBIDDEN",
      data: { kind: "forbidden", status: 403 },
    });
  });
});
