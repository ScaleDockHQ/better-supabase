import { createClient } from "@supabase/supabase-js";
import * as v from "valibot";
import { afterAll, describe, expect, it } from "vitest";

import type { ContractOf } from "../../src/edge/index.ts";

import { functions } from "../../src/client/index.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { createEdge, defineFunction } from "../../src/edge/index.ts";
import { parseEnv } from "../../src/env/index.ts";
import { signLocalJwt } from "../../src/testing/local-key.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { stackUrl } from "./stack-env.ts";

const url = stackUrl();

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

describe.skipIf(!live)("typed Edge Functions against the local stack", () => {
  const betterSupabase = defineSupabase(schema);

  const env = parseEnv({
    SUPABASE_URL: url,
    SUPABASE_PUBLISHABLE_KEY: publishableKey,
  }).env!;

  const bsb = createEdge(betterSupabase, { env });

  // The same function as apps/examples/edge/supabase/functions/create-customer.
  const createCustomer = defineFunction(bsb, {
    input: v.object({
      name: v.pipe(v.string(), v.trim(), v.minLength(1)),
      organizationId: v.pipe(v.string(), v.uuid()),
    }),
    output: v.object({
      id: v.string(),
      name: v.string(),
      organizationId: v.string(),
    }),
    handler: (input, { db }) =>
      db.customers.create(input, { select: ["id", "name", "organizationId"] }),
  });

  // The stack runs without the edge runtime, so supabase-js's calls to
  // /functions/v1/create-customer reach the handler in this process.
  const supabase = createClient(url, publishableKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      fetch: (input, init) => {
        const request = new Request(input, init);

        return new URL(request.url).pathname === "/functions/v1/create-customer"
          ? createCustomer(request)
          : fetch(request);
      },
    },
  });

  const fns = functions<{
    "create-customer": ContractOf<typeof createCustomer>;
  }>(supabase);

  const admin = betterSupabase.connect(
    createClient(url, secretKey, { auth: { persistSession: false } }),
  );

  const created: string[] = [];

  afterAll(async () => {
    if (created.length > 0) {
      await admin.customers.deleteMany({ where: { id: { in: created } } });
    }
  });

  const as = async (organizationId: string) => ({
    headers: {
      authorization: `Bearer ${await signLocalJwt({ sub: USER, tenant_id: organizationId })}`,
    },
  });

  it("creates the row as the caller and returns the typed output", async () => {
    const name = `Function ${String(Date.now())}`;

    const row = await fns
      .invoke(
        "create-customer",
        { name: `  ${name}  `, organizationId: ACME },
        await as(ACME),
      )
      .orThrow();

    created.push(row.id);
    expect(row).toMatchObject({ name, organizationId: ACME });
  });

  it("returns RLS and validation failures as DbErrors", async () => {
    const crossTenant = await fns.invoke(
      "create-customer",
      { name: "Not mine", organizationId: ACME },
      await as(OTHER),
    );

    expect(crossTenant.ok ? undefined : crossTenant.error.kind).toBe(
      "forbidden",
    );

    const invalid = await fns.invoke(
      "create-customer",
      { name: " ", organizationId: ACME },
      await as(ACME),
    );

    expect(invalid.ok ? undefined : invalid.error).toMatchObject({
      kind: "validation",
      status: 422,
    });
  });
});
