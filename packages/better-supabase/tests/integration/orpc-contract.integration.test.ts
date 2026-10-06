import { oc } from "@orpc/contract";
import { openapi } from "@orpc/openapi";
import { OpenAPIHandler } from "@orpc/openapi/fetch";
import { implement } from "@orpc/server";
import { createClient } from "@supabase/supabase-js";
import { Hono } from "hono";
import * as v from "valibot";
import { afterAll, describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { parseEnv } from "../../src/env/index.ts";
import { createOrpc, type OrpcRequestContext } from "../../src/orpc/index.ts";
import { signLocalJwt } from "../../src/testing/local-key.ts";
import { schema } from "../fixtures/generated-camel.ts";

const url = process.env["SUPABASE_URL"] ?? "http://127.0.0.1:55421";
const publishableKey =
  process.env["SUPABASE_PUBLISHABLE_KEY"] ??
  "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH";
const secretKey =
  process.env["SUPABASE_SECRET_KEY"] ??
  "sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz";

const ACME = "00000000-0000-4000-8000-000000000001";
const OTHER = "00000000-0000-4000-8000-000000000002";
const USER = "00000000-0000-4000-8000-0000000000ff";

async function reachable(): Promise<boolean> {
  try {
    const response = await fetch(`${url}/rest/v1/`, {
      headers: { apikey: publishableKey },
      signal: AbortSignal.timeout(1000),
    });
    return response.status < 500;
  } catch {
    return false;
  }
}

const live = await reachable();

const customer = v.object({
  id: v.string(),
  name: v.string(),
  organizationId: v.string(),
});

const contract = {
  customers: {
    get: oc
      .meta(openapi({ method: "GET", path: "/customers/{id}" }))
      .input(v.object({ id: v.string() }))
      .output(customer),
    create: oc
      .meta(openapi({ method: "POST", path: "/customers", successStatus: 201 }))
      .input(v.object({ name: v.string(), organizationId: v.string() }))
      .output(customer),
  },
};

describe.skipIf(!live)(
  "a contract-first oRPC router against the local stack",
  () => {
    const betterSupabase = defineSupabase(schema);
    const env = parseEnv({
      SUPABASE_URL: url,
      SUPABASE_PUBLISHABLE_KEY: publishableKey,
    }).env!;
    const bs = createOrpc(betterSupabase, { env });
    const os = implement(contract)
      .$context<OrpcRequestContext>()
      .use(bs.middleware());
    const select = ["id", "name", "organizationId"] as const;
    const router = os.router({
      customers: {
        get: os.customers.get.handler(({ context, input }) =>
          bs.unwrap(context.db.customers.findById(input.id, { select })),
        ),
        create: os.customers.create.handler(({ context, input }) =>
          bs.unwrap(context.db.customers.create(input, { select })),
        ),
      },
    });
    const handle = bs.fetchHandler(new OpenAPIHandler(router), {
      prefix: "/api",
    });
    const app = new Hono().all("/api/*", (c) => handle(c.req.raw));
    const admin = betterSupabase.connect(
      createClient(url, secretKey, { auth: { persistSession: false } }),
    );
    const created: string[] = [];
    afterAll(async () => {
      if (created.length > 0) {
        await admin.customers.deleteMany({ where: { id: { in: created } } });
      }
    });

    const call = async (
      organizationId: string,
      path: string,
      body?: Record<string, string>,
    ) =>
      app.request(path, {
        method: body ? "POST" : "GET",
        headers: {
          authorization: `Bearer ${await signLocalJwt({ sub: USER, tenant_id: organizationId })}`,
          ...(body ? { "content-type": "application/json" } : {}),
        },
        ...(body ? { body: JSON.stringify(body) } : {}),
      });

    it("creates and reads as the caller, and maps RLS denials", async () => {
      const name = `oRPC contract ${String(Date.now())}`;
      const create = await call(ACME, "/api/customers", {
        name,
        organizationId: ACME,
      });
      expect(create.status).toBe(201);
      const row = (await create.json()) as { id: string };
      created.push(row.id);

      const found = await call(ACME, `/api/customers/${row.id}`);
      expect(await found.json()).toEqual({
        id: row.id,
        name,
        organizationId: ACME,
      });

      const hidden = await call(OTHER, `/api/customers/${row.id}`);
      expect(hidden.status).toBe(404);
      expect(await hidden.json()).toMatchObject({
        code: "NOT_FOUND",
        data: { kind: "not_found" },
      });

      const denied = await call(OTHER, "/api/customers", {
        name,
        organizationId: ACME,
      });
      expect(denied.status).toBe(403);
      expect(await denied.json()).toMatchObject({
        code: "FORBIDDEN",
        data: { kind: "forbidden", status: 403 },
      });
    });
  },
);
