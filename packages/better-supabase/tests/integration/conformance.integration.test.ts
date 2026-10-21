import { createClient } from "@supabase/supabase-js";
import { afterAll, describe, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { postgrestExecutor } from "../../src/core/postgrest-executor.ts";
import { createPostgres, postgresExecutor } from "../../src/postgres/index.ts";
import { testExecutor } from "../../src/testing/kits/executor.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { stackDbUrl, stackUrl } from "./stack-env.ts";

const url = stackUrl();
const dbUrl = stackDbUrl();

const publishableKey =
  process.env["SUPABASE_PUBLISHABLE_KEY"] ??
  "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH";

const secretKey =
  process.env["SUPABASE_SECRET_KEY"] ??
  "sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz";

const ACME = "00000000-0000-4000-8000-000000000001";

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

describe.skipIf(!live)("built-in executors conform", () => {
  const betterSupabase = defineSupabase(schema);
  const postgres = createPostgres({ connectionString: dbUrl, max: 2 });

  afterAll(() => postgres.end());

  const create = (name: string) => ({
    organizationId: ACME,
    name: `conformance-${name}-${Date.now()}`,
    color: "gray",
  });

  it("postgrest", () =>
    testExecutor(
      postgrestExecutor(
        createClient(url, secretKey, { auth: { persistSession: false } }),
      ),
      { betterSupabase, table: "tags", create: create("postgrest") },
    ));

  it("postgres", () =>
    testExecutor(postgresExecutor(postgres.admin), {
      betterSupabase,
      table: "tags",
      create: create("postgres"),
    }));
});
