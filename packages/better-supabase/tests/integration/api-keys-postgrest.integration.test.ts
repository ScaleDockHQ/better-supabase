import { describe, expect, it } from "vitest";

import type { ApiKeys } from "../../src/blocks/api-keys/index.ts";

import { apiKeyResolver } from "../../src/blocks/api-keys/index.ts";
import { createSupabase } from "../../src/core/define.ts";
import { AsyncResult } from "../../src/core/result.ts";
import { parseEnv } from "../../src/env/index.ts";
import { apiKeyTokenSigner, createServer } from "../../src/server/index.ts";
import { localSigningKey } from "../../src/testing/local-key.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { stackUrl } from "./stack-env.ts";

const url = stackUrl();

const publishableKey =
  process.env["SUPABASE_PUBLISHABLE_KEY"] ??
  "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH";

const ACME = "00000000-0000-4000-8000-000000000001";
const OWNER = "00000000-0000-4000-8000-0000000000a1";
const STRANGER = "00000000-0000-4000-8000-00000000ffff";
const ROAD_RUNNER = "00000000-0000-4000-8000-00000000a001";

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

/** A key store that answers every token with a personal key of `userId`. */
const personalKey = (userId: string): Pick<ApiKeys, "verify"> => ({
  verify: () =>
    AsyncResult.ok({
      status: "ok",
      key: {
        id: "33333333-3333-4333-8333-333333333333",
        organizationId: ACME,
        userId,
        name: "CI",
        prefix: "bs",
        publicId: "0123456789abcdef",
        scopes: ["customers:read"],
        rateLimit: 60,
        createdAt: Temporal.Instant.from("2026-10-06T09:00:00Z"),
        state: "active",
      },
    } as const),
});

describe.skipIf(!live)("an API key over PostgREST", async () => {
  const env = parseEnv({
    SUPABASE_URL: url,
    SUPABASE_PUBLISHABLE_KEY: publishableKey,
  }).env!;

  const { kty, ...rest } = await localSigningKey();
  const sign = apiKeyTokenSigner({ key: { ...rest, kty: kty ?? "EC" } });

  const customersFor = async (userId: string) => {
    const server = createServer(createSupabase(schema), {
      env,
      apiKeyToken: sign,
      auth: {
        resolvers: [
          apiKeyResolver({
            keys: personalKey(userId),
            tenantClaim: "tenant_id",
          }),
        ],
      },
    });

    const ctx = await server.context(
      new Request(`${url}/api`, {
        headers: { "x-api-key": `bs_0123456789abcdef_${"d".repeat(43)}` },
      }),
    );

    expect(ctx.auth.kind).toBe("apiKey");
    expect(ctx.sql).toBeUndefined();

    return (await ctx.db.customers.list({ select: ["id"] }).orThrow()).map(
      (row) => row.id,
    );
  };

  it("reads the key user's rows under RLS with a minted token", async () => {
    expect(await customersFor(OWNER)).toContain(ROAD_RUNNER);
  });

  it("reads none for a key whose user is not a member", async () => {
    expect(await customersFor(STRANGER)).toEqual([]);
  });
});
