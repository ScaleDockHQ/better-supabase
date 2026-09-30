import { createClient } from "@supabase/supabase-js";
import { afterAll, describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { parseEnv } from "../../src/env/index.ts";
import { createMcp } from "../../src/mcp/index.ts";
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

interface ToolResult {
  isError?: boolean;
  structuredContent?: Record<string, unknown>;
}

describe.skipIf(!live)("MCP tools against the local stack", () => {
  const sb = defineSupabase(schema);
  const mcp = createMcp(sb, {
    env: parseEnv({
      SUPABASE_URL: url,
      SUPABASE_PUBLISHABLE_KEY: publishableKey,
    }).env!,
    name: "crm",
    version: "1.0.0",
    resources: { customers: { select: ["id", "name", "organizationId"] } },
  });
  const admin = sb.connect(
    createClient(url, secretKey, { auth: { persistSession: false } }),
  );
  const created: string[] = [];
  afterAll(async () => {
    if (created.length > 0) {
      await admin.customers.deleteMany({ where: { id: { in: created } } });
    }
  });

  const call = async (orgId: string, name: string, args: unknown) => {
    const token = await signLocalJwt({ sub: USER, tenant_id: orgId });
    const response = await mcp.fetch(
      new Request("http://127.0.0.1/mcp", {
        method: "POST",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          jsonrpc: "2.0",
          id: 1,
          method: "tools/call",
          params: { name, arguments: args },
        }),
      }),
    );
    return ((await response.json()) as { result: ToolResult }).result;
  };

  it("creates, reads, updates and deletes as the caller under RLS", async () => {
    const name = `MCP ${String(Date.now())}`;
    const createdRow = await call(ACME, "customers_create", {
      name,
      organizationId: ACME,
    });
    expect(createdRow.isError).toBeUndefined();
    const id = createdRow.structuredContent!["id"] as string;
    created.push(id);

    expect(await call(ACME, "customers_get", { id })).toMatchObject({
      structuredContent: { id, name },
    });
    expect(await call(OTHER, "customers_get", { id })).toMatchObject({
      isError: true,
      structuredContent: { kind: "not_found" },
    });
    expect(
      await call(OTHER, "customers_create", { name, organizationId: ACME }),
    ).toMatchObject({
      isError: true,
      structuredContent: { kind: "forbidden" },
    });

    expect(
      await call(ACME, "customers_update", { id, patch: { name: `${name}!` } }),
    ).toMatchObject({ structuredContent: { name: `${name}!` } });
    const page = await call(ACME, "customers_list", { size: 200 });
    expect(
      (page.structuredContent!["items"] as { id: string }[]).some(
        (row) => row.id === id,
      ),
    ).toBe(true);

    expect(await call(ACME, "customers_delete", { id })).toMatchObject({
      structuredContent: { deleted: true },
    });
    expect(await call(ACME, "customers_get", { id })).toMatchObject({
      isError: true,
    });
  });
});
