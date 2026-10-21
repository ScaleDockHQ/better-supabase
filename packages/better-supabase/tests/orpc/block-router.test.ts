import { openapi } from "@orpc/openapi";
import { OpenAPIHandler } from "@orpc/openapi/fetch";
import { os } from "@orpc/server";
import * as v from "valibot";
import { describe, expect, expectTypeOf, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { OrpcRequestContext } from "../../src/orpc/index.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { dbError } from "../../src/core/errors.ts";
import { err, ok } from "../../src/core/result.ts";
import { createOrpc } from "../../src/orpc/index.ts";
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

const invoices = {
  async create(input: { readonly total: number }): Promise<Result<Invoice>> {
    return input.total < 0
      ? err(dbError("forbidden", "total must be positive"))
      : ok({ id: "inv_1", total: input.total });
  },
  async issue(id: string, when: string): Promise<Result<Invoice>> {
    return ok({ id, total: 10, issuedAt: when });
  },
};

describe("bs.blockRouter", () => {
  const bs = createOrpc(defineSupabase(schema), {
    env,
    auth: { jwks: signer.jwks },
  });

  const invoicesFor = (_supabase: unknown) => invoices;

  // A callback that reads the context, so TypeScript infers the client late.
  const block = bs.blockRouter(({ supabase }) => invoicesFor(supabase), {
    name: "invoices",
    methods: ["create", "issue"],
    schemas: { create: v.object({ total: v.number() }) },
    guard: { allow: ["user"] },
    tags: ["invoices"],
    meta: openapi,
  });

  const router = os
    .$context<OrpcRequestContext>()
    .router({ invoices: block.procedures });

  const handle = bs.fetchHandler(new OpenAPIHandler(router), {
    prefix: "/api",
  });

  const post = async (path: string, body: unknown, token?: string) =>
    handle(
      new Request(`https://app.test/api${path}`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          ...(token ? { authorization: `Bearer ${token}` } : {}),
        },
        body: JSON.stringify(body),
      }),
    );

  it("serves each method at its route, spreading a tuple input", async () => {
    const token = await signer.sign({ sub: "u1" });
    const created = await post("/invoices/create", { total: 5 }, token);
    expect(await created.json()).toEqual({ id: "inv_1", total: 5 });

    const issued = await post(
      "/invoices/issue",
      ["inv_1", "2026-10-21"],
      token,
    );

    expect(await issued.json()).toEqual({
      id: "inv_1",
      total: 10,
      issuedAt: "2026-10-21",
    });
  });

  it("validates input, guards the caller and maps a DbError", async () => {
    const token = await signer.sign({ sub: "u1" });
    const anonymous = await post("/invoices/create", { total: 5 });
    expect(anonymous.status).toBe(401);
    const invalid = await post("/invoices/create", { total: "5" }, token);
    expect(invalid.status).toBe(400);
    const refused = await post("/invoices/create", { total: -1 }, token);
    expect(refused.status).toBe(403);
  });

  it("documents one POST route per method", () => {
    expect(
      block.routes.map(({ method, path, operationId, tags }) => ({
        method,
        path,
        operationId,
        tags,
      })),
    ).toEqual([
      {
        method: "POST",
        path: "/invoices/create",
        operationId: "invoices.create",
        tags: ["invoices"],
      },
      {
        method: "POST",
        path: "/invoices/issue",
        operationId: "invoices.issue",
        tags: ["invoices"],
      },
    ]);
  });

  it("types each procedure from the block method", () => {
    expectTypeOf(block.procedures).toHaveProperty("create");
    expectTypeOf(block.procedures).toHaveProperty("issue");
    expectTypeOf(block.procedures).not.toHaveProperty("missing");
  });
});
