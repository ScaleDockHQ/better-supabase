import { Pool, type PoolClient } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { SqlClient } from "../../src/postgres/executor.ts";

import { createInbox } from "../../src/blocks/jobs/index.ts";
import {
  createIncomingWebhooks,
  INCOMING_ENDPOINT_HEADER,
  signWebhook,
} from "../../src/blocks/webhooks/index.ts";
import { renderModules } from "../../src/sql/registry.ts";

const dbUrl =
  process.env["SUPABASE_DB_URL"] ??
  "postgresql://postgres:postgres@127.0.0.1:55422/postgres";

async function reachable(): Promise<boolean> {
  const pool = new Pool({
    connectionString: dbUrl,
    max: 1,
    connectionTimeoutMillis: 1000,
  });
  try {
    await pool.query("select 1");
    return true;
  } catch {
    return false;
  } finally {
    await pool.end();
  }
}

const live = await reachable();

/** A SqlClient on one transaction's connection, as `who`. */
function clientAs(client: PoolClient, claims: () => object): SqlClient {
  return {
    async queryRaw<T>(text: string, params: unknown[] = []) {
      await client.query("select set_config('request.jwt.claims', $1, true)", [
        JSON.stringify(claims()),
      ]);
      await client.query("savepoint call");
      try {
        const { rows } = await client.query(text, params);
        await client.query("release savepoint call");
        // SAFETY: the block names the row shape of its own queries.
        return rows as T[];
      } catch (error) {
        await client.query("rollback to savepoint call");
        throw error;
      }
    },
  };
}

describe.skipIf(!live)("incoming webhook endpoints", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("creates endpoints and stores verified deliveries per tenant", async () => {
    const client = await pool.connect();
    const owner = crypto.randomUUID();
    const outsider = crypto.randomUUID();
    const organization = crypto.randomUUID();
    let claims: object = { sub: owner, role: "authenticated" };
    const sql = clientAs(client, () => claims);
    const source = `webhook-in-${owner.slice(0, 8)}`;
    try {
      await client.query("begin");
      for (const id of [owner, outsider]) {
        await client.query(
          `insert into auth.users (id, email, aud, role, instance_id)
           values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000')`,
          [id, `${id}@example.test`],
        );
      }
      for (const file of renderModules(["webhooks-in", "rate-limit"]))
        if (file.kind === "schema") await client.query(file.contents);
      if (
        (
          await client.query(
            "select to_regclass('better_supabase.organizations') as t",
          )
        ).rows[0].t
      ) {
        await client.query(
          "insert into better_supabase.organizations (id, name, slug) values ($1, 'Hooks', $2)",
          [organization, `hooks-${organization.slice(0, 8)}`],
        );
      }
      await client.query(
        "insert into better_supabase.memberships (organization_id, user_id, role) values ($1, $2, 'owner')",
        [organization, owner],
      );
      const hooks = createIncomingWebhooks(sql, {
        source,
        rateLimit: { max: 3, period: 60 },
        keepHeaders: ["x-request-id"],
      });

      const plain = await hooks
        .create({ tenant: organization, name: "Form" })
        .orThrow();
      expect(plain).toMatchObject({ verify: "none", secret: null });
      const signed = await hooks
        .create({
          tenant: organization,
          name: "Signed",
          verify: "standard-webhooks",
        })
        .orThrow();
      expect(signed.secret).toMatch(/^whsec_/);
      const hmac = await hooks
        .create({ tenant: organization, name: "HMAC", verify: "hmac-sha256" })
        .orThrow();
      expect(hmac.signatureHeader).toBe("x-signature");
      claims = { sub: outsider, role: "authenticated" };
      expect(
        await hooks.create({ tenant: organization, name: "Nope" }),
      ).toMatchObject({ ok: false, error: { hint: "WEBHOOK_IN_FORBIDDEN" } });
      expect(
        (
          await client.query(
            "select count(*)::int as n from better_supabase.incoming_webhooks",
          )
        ).rows[0].n,
      ).toBeGreaterThanOrEqual(3);

      claims = { role: "service_role" };
      const post = (token: string, body: string, headers = {}) =>
        hooks.receive(
          new Request(`https://api.test/hooks/${token}`, {
            method: "POST",
            headers: { "content-type": "application/json", ...headers },
            body,
          }),
          token,
        );
      const first = await post(plain.token, '{"type":"lead.created"}', {
        "x-request-id": "r1",
        "webhook-id": "m1",
      });
      expect(first.status).toBe(202);
      expect(
        (await post(plain.token, "{}", { "webhook-id": "m1" })).status,
      ).toBe(200);
      expect((await post("unknown", "{}")).status).toBe(404);

      const body = '{"type":"invoice.paid"}';
      const headers = await signWebhook(signed.secret!, { id: "s1", body });
      expect((await post(signed.token, body, headers)).status).toBe(202);
      expect((await post(signed.token, body)).status).toBe(401);

      const mac = await crypto.subtle.sign(
        "HMAC",
        await crypto.subtle.importKey(
          "raw",
          new TextEncoder().encode(hmac.secret!),
          { name: "HMAC", hash: "SHA-256" },
          false,
          ["sign"],
        ),
        new TextEncoder().encode(body),
      );
      const hex = Array.from(new Uint8Array(mac), (byte) =>
        byte.toString(16).padStart(2, "0"),
      ).join("");
      expect(
        (await post(hmac.token, body, { "x-signature": `sha256=${hex}` }))
          .status,
      ).toBe(202);
      expect(
        (await post(hmac.token, body, { "x-signature": "sha256=00" })).status,
      ).toBe(401);

      expect((await post(plain.token, "{}")).status).toBe(202);
      const limited = await post(plain.token, "{}");
      expect(limited.status).toBe(429);
      expect(limited.headers.get("retry-after")).not.toBeNull();

      const { rows: stats } = await client.query<{
        receive_count: string;
        last_status: number;
      }>(
        "select receive_count, last_status from better_supabase.incoming_webhooks where id = $1",
        [plain.id],
      );
      expect(stats[0]).toEqual({ receive_count: "4", last_status: 429 });

      const inbox = createInbox(sql, {
        source,
        verify: () => Promise.reject(new Error("process only")),
      });
      const seen: [string | null, string | undefined][] = [];
      await inbox.process((message) => {
        seen.push([message.tenant, message.headers[INCOMING_ENDPOINT_HEADER]]);
      });
      expect(seen).toHaveLength(4);
      expect(seen.every(([tenant]) => tenant === organization)).toBe(true);

      claims = { sub: owner, role: "authenticated" };
      const rotated = await hooks.rotate(plain.id).orThrow();
      expect(rotated.secret).toBeNull();
      expect(await hooks.setEnabled(signed.id, false).orThrow()).toBe(true);
      claims = { role: "service_role" };
      expect((await post(plain.token, "{}")).status).toBe(404);
      expect((await post(signed.token, body, headers)).status).toBe(404);
      claims = { sub: owner, role: "authenticated" };
      expect(await hooks.remove(hmac.id).orThrow()).toBe(true);
      expect(await hooks.remove(hmac.id).orThrow()).toBe(false);
    } finally {
      await client.query("rollback");
      client.release();
    }
  });
});
