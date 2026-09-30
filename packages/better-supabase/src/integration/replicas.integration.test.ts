import { createClient } from "@supabase/supabase-js";
import { afterAll, describe, expect, it, vi } from "vitest";

import { defineSupabase } from "../core/define.ts";
import { parseEnv } from "../env/index.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { PRIMARY_COOKIE } from "../server/replicas.ts";
import { createServer } from "../server/server.ts";
import { signLocalJwt } from "../testing/local-key.ts";

const url = process.env["SUPABASE_URL"] ?? "http://127.0.0.1:55421";
const publishableKey =
  process.env["SUPABASE_PUBLISHABLE_KEY"] ??
  "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH";
const secretKey =
  process.env["SUPABASE_SECRET_KEY"] ??
  "sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz";

const ACME = "00000000-0000-4000-8000-000000000001";
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

// The local stack has no replica: a second host name for it stands in for one.
const readUrl = url.replace("127.0.0.1", "localhost");

describe.skipIf(!(await reachable()) || readUrl === url)(
  "read URL against the local stack",
  () => {
    const sb = defineSupabase(schema);
    const server = createServer(sb, {
      env: parseEnv({
        SUPABASE_URL: url,
        SUPABASE_PUBLISHABLE_KEY: publishableKey,
        SUPABASE_READ_URL: readUrl,
      }).env!,
    });
    const admin = sb.connect(
      createClient(url, secretKey, { auth: { persistSession: false } }),
    );
    const created: string[] = [];
    afterAll(async () => {
      vi.restoreAllMocks();
      if (created.length > 0)
        await admin.customers.deleteMany({ where: { id: { in: created } } });
    });

    it("reads its own write from the primary right after writing", async () => {
      const token = await signLocalJwt({ sub: USER, tenant_id: ACME });
      const real = globalThis.fetch;
      const hosts: string[] = [];
      vi.spyOn(globalThis, "fetch").mockImplementation((input, init) => {
        const target = new URL(
          input instanceof Request ? input.url : String(input),
        );
        if (target.pathname.startsWith("/rest/"))
          hosts.push(`${init?.method ?? "GET"} ${target.hostname}`);
        return real(input, init);
      });
      const request = (cookie?: string) =>
        new Request("https://app.test/", {
          headers: {
            authorization: `Bearer ${token}`,
            ...(cookie ? { cookie } : {}),
          },
        });

      const ctx = await server.context(request());
      const name = `Replica ${crypto.randomUUID()}`;
      const before = await ctx.db.customers
        .findMany({ where: { name }, select: ["id"] })
        .orThrow();
      expect(before).toEqual([]);
      const row = await ctx.db.customers
        .create({ name, organizationId: ACME }, { select: ["id"] })
        .orThrow();
      created.push(row.id);
      const after = await ctx.db.customers
        .findById(row.id, { select: ["id", "name"] })
        .orThrow();
      expect(after).toEqual({ id: row.id, name });

      const next = await server.context(
        request(`${PRIMARY_COOKIE}=${String(Date.now() + 5000)}`),
      );
      await next.db.customers.findById(row.id, { select: ["id"] }).orThrow();
      const later = await server.context(request());
      await later.db.customers.findById(row.id, { select: ["id"] }).orThrow();

      expect(hosts).toEqual([
        "GET localhost",
        "POST 127.0.0.1",
        "GET 127.0.0.1",
        "GET 127.0.0.1",
        "GET localhost",
      ]);
    });
  },
);
