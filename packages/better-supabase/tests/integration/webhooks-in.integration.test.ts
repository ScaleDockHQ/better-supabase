import { Pool, type PoolClient } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { SqlClient } from "../../src/postgres/executor.ts";

import { createInbox } from "../../src/blocks/jobs/index.ts";
import {
  createIncomingWebhooks,
  INCOMING_ENDPOINT_HEADER,
  signWebhook,
} from "../../src/blocks/webhooks/index.ts";
import { renderModules, upgradePlan } from "../../src/sql/registry.ts";
import { BlockSession } from "./block-session.ts";

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
      const stored = async (id: string) =>
        (
          await client.query<{ secret: string | null; vaulted: string | null }>(
            `select e.secret, ds.decrypted_secret as vaulted
             from better_supabase.incoming_webhooks e
             left join vault.decrypted_secrets ds on ds.id = e.secret_id
             where e.id = $1`,
            [id],
          )
        ).rows[0];
      expect(await stored(signed.id)).toEqual({
        secret: null,
        vaulted: signed.secret,
      });
      expect(await stored(plain.id)).toEqual({ secret: null, vaulted: null });
      const vaultCount = async () =>
        (
          await client.query<{ n: number }>(
            "select count(*)::int as n from vault.secrets where name like 'webhook-in:%'",
          )
        ).rows[0]!.n;
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
      const before = await vaultCount();
      const resigned = await hooks
        .rotate(signed.id, { rotateSecret: true })
        .orThrow();
      expect(resigned.secret).toMatch(/^whsec_/);
      expect(resigned.secret).not.toBe(signed.secret);
      expect(await stored(signed.id)).toEqual({
        secret: null,
        vaulted: resigned.secret,
      });
      expect(await vaultCount()).toBe(before);
      expect(await hooks.setEnabled(signed.id, false).orThrow()).toBe(true);
      claims = { role: "service_role" };
      expect((await post(plain.token, "{}")).status).toBe(404);
      expect((await post(signed.token, body, headers)).status).toBe(404);
      claims = { sub: owner, role: "authenticated" };
      expect(await hooks.remove(hmac.id).orThrow()).toBe(true);
      expect(await hooks.remove(hmac.id).orThrow()).toBe(false);
      expect(await vaultCount()).toBe(before - 1);
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("updates endpoints and checks the split create, update and delete keys", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "webhooks-in"], {
        modules: {
          "webhooks-in": { permissions: { delete: "organization.delete" } },
        },
      });
      const owner = await s.user("owner");
      const admin = await s.user("admin");
      const member = await s.user("member");
      const organization = await s.organization(owner, { admin, member });
      const hooks = createIncomingWebhooks(s.sql);
      const vaulted = (id: string) =>
        s.value<string | null>(
          `(select ds.decrypted_secret from better_supabase.incoming_webhooks e
            left join vault.decrypted_secrets ds on ds.id = e.secret_id where e.id = $1)`,
          [id],
        );
      const vaultCount = () =>
        s.value<number>(
          "(select count(*)::int from vault.secrets where name like 'webhook-in:%')",
        );

      await s.as(admin);
      const created = await hooks
        .create({
          tenant: organization,
          name: "Form",
          verify: "standard-webhooks",
          metadata: { workflow: "w1" },
        })
        .orThrow();
      const count = await vaultCount();
      expect(
        await hooks
          .update(created.id, {
            name: "Signup form",
            metadata: { workflow: "w2" },
          })
          .orThrow(),
      ).toEqual({
        id: created.id,
        tenant: organization,
        name: "Signup form",
        verify: "standard-webhooks",
        secret: null,
        signatureHeader: null,
        metadata: { workflow: "w2" },
      });
      expect(await vaulted(created.id)).toBe(created.secret);

      const hmac = await hooks
        .update(created.id, { verify: "hmac-sha256", signatureHeader: "x-hub" })
        .orThrow();
      expect(hmac).toMatchObject({
        verify: "hmac-sha256",
        signatureHeader: "x-hub",
        name: "Signup form",
      });
      expect(hmac.secret).toMatch(/^[0-9a-f]{64}$/);
      expect(await vaulted(created.id)).toBe(hmac.secret);
      expect(await vaultCount()).toBe(count);

      const none = await hooks.update(created.id, { verify: "none" }).orThrow();
      expect(none).toMatchObject({
        verify: "none",
        secret: null,
        signatureHeader: null,
      });
      expect(await vaulted(created.id)).toBeNull();
      expect(await vaultCount()).toBe(count - 1);

      expect(await hooks.update(created.id, { name: " " })).toMatchObject({
        ok: false,
        error: { hint: "WEBHOOK_IN_NAME_REQUIRED" },
      });
      expect(
        await s.hint(
          "better_supabase.update_incoming_webhook($1, metadata => '[]'::jsonb)",
          [created.id],
        ),
      ).toBe("WEBHOOK_IN_METADATA_INVALID");
      expect(
        await s.hint(
          "better_supabase.update_incoming_webhook($1, verify => 'magic')",
          [created.id],
        ),
      ).toBe("WEBHOOK_IN_VERIFY_UNKNOWN");

      await s.as(member);
      expect(await hooks.update(created.id, { name: "Mine" })).toMatchObject({
        ok: false,
        error: { hint: "WEBHOOK_IN_NOT_FOUND" },
      });
      expect(
        await hooks.create({ tenant: organization, name: "x" }),
      ).toMatchObject({
        ok: false,
        error: { hint: "WEBHOOK_IN_FORBIDDEN" },
      });

      await s.as(admin);
      expect(await hooks.setEnabled(created.id, false).orThrow()).toBe(true);
      expect(await hooks.remove(created.id).orThrow()).toBe(false);
      await s.as(owner);
      expect(await hooks.remove(created.id).orThrow()).toBe(true);
    } finally {
      await s.close();
    }
  });

  it("rotates a signing secret and verifies the old one during the grace", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "webhooks-in"]);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const organization = await s.organization(owner, { member });
      const hooks = createIncomingWebhooks(s.sql, {
        source: `rotate-${organization.slice(0, 8)}`,
      });
      const vaultCount = () =>
        s.value<number>(
          "(select count(*)::int from vault.secrets where name like 'webhook-in:%')",
        );
      await s.as(owner);
      const created = await hooks
        .create({
          tenant: organization,
          name: "Signed",
          verify: "standard-webhooks",
        })
        .orThrow();
      const plain = await hooks
        .create({ tenant: organization, name: "Plain" })
        .orThrow();
      const count = await vaultCount();
      const rotated = await hooks
        .rotateSecret(created.id, { grace: "1 hour" })
        .orThrow();
      expect(rotated.secret).toMatch(/^whsec_/);
      expect(rotated.secret).not.toBe(created.secret);
      expect(rotated.previousSecretExpiresAt).not.toBeNull();
      expect(await vaultCount()).toBe(count + 1);

      const body = '{"type":"x"}';
      const post = async (secret: string, id: string) =>
        (
          await hooks.receive(
            new Request(`https://api.test/hooks/${created.token}`, {
              method: "POST",
              headers: await signWebhook(secret, { id, body }),
              body,
            }),
            created.token,
          )
        ).status;
      await s.service();
      expect(await post(created.secret!, "a1")).toBe(202);
      expect(await post(rotated.secret, "a2")).toBe(202);

      await s.client.query(
        "update better_supabase.incoming_webhooks set previous_secret_expires_at = now() - interval '1 second' where id = $1",
        [created.id],
      );
      expect(await post(created.secret!, "a3")).toBe(401);
      expect(await post(rotated.secret, "a4")).toBe(202);

      await s.as(owner);
      const again = await hooks.rotateSecret(created.id).orThrow();
      expect(again.previousSecretExpiresAt).toBeNull();
      expect(await vaultCount()).toBe(count);
      await s.service();
      expect(await post(rotated.secret, "a5")).toBe(401);
      expect(await post(again.secret, "a6")).toBe(202);

      await s.as(owner);
      expect(await hooks.rotateSecret(plain.id)).toMatchObject({
        ok: false,
        error: { hint: "WEBHOOK_IN_NO_SECRET" },
      });
      await s.as(member);
      expect(await hooks.rotateSecret(created.id)).toMatchObject({
        ok: false,
        error: { hint: "WEBHOOK_IN_NOT_FOUND" },
      });
      await s.as(owner);
      await hooks.rotateSecret(created.id, { grace: "1 day" }).orThrow();
      expect(await vaultCount()).toBe(count + 1);
      expect(await hooks.remove(created.id).orThrow()).toBe(true);
      expect(await vaultCount()).toBe(count - 1);
    } finally {
      await s.close();
    }
  });

  it("ties endpoints to readable subjects and cascades their deletes", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.rows(
        `create table public.bs_test_flows (
           id uuid primary key default gen_random_uuid(),
           organization_id uuid not null,
           private boolean not null default false
         );
         alter table public.bs_test_flows enable row level security;
         grant select on public.bs_test_flows to authenticated;
         create policy "read" on public.bs_test_flows for select to authenticated
           using (better_supabase.has_organization_role(organization_id) and not private);`,
      );
      await s.install(["organizations", "webhooks-in"], {
        modules: {
          "webhooks-in": {
            options: {
              subjects: { flow: { table: "bs_test_flows", cascade: true } },
            },
          },
        },
      });
      const owner = await s.user("owner");
      const organization = await s.organization(owner);
      const [open, hidden] = await s.rows<{ id: string }>(
        "insert into public.bs_test_flows (organization_id, private) values ($1, false), ($1, true) returning id",
        [organization],
      );
      const hooks = createIncomingWebhooks(s.sql);
      await s.asRole(owner);
      for (const flow of [open!, hidden!]) {
        await hooks
          .create({
            tenant: organization,
            name: `Flow ${flow.id.slice(0, 4)}`,
            subject: { type: "flow", id: flow.id },
          })
          .orThrow();
      }
      expect(
        await hooks.create({
          tenant: organization,
          name: "Elsewhere",
          subject: { type: "flow", id: crypto.randomUUID() },
        }),
      ).toMatchObject({
        ok: false,
        error: { hint: "WEBHOOK_IN_SUBJECT_INVALID" },
      });
      const listed = await hooks.list(organization).orThrow();
      expect(listed.map((hook) => hook.subject?.id)).toEqual([open!.id]);
      expect(
        await hooks
          .list(organization, { type: "flow", id: open!.id })
          .orThrow(),
      ).toHaveLength(1);

      await s.service();
      await s.rows("delete from public.bs_test_flows where id = $1", [
        open!.id,
      ]);
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.incoming_webhooks where tenant = $1)",
          [organization],
        ),
      ).toBe(1);
    } finally {
      await s.close();
    }
  });

  it("moves plaintext secrets of an older install to Vault on upgrade", async () => {
    const client = await pool.connect();
    try {
      await client.query("begin");
      for (const file of renderModules(["webhooks-in"]))
        if (file.kind === "schema") await client.query(file.contents);
      const { rows } = await client.query<{ id: string }>(
        `insert into better_supabase.incoming_webhooks (tenant, name, token_hash, verify, secret)
         values ($1, 'Legacy', $2, 'hmac-sha256', 'legacy-secret-0123456789') returning id`,
        [crypto.randomUUID(), crypto.randomUUID()],
      );
      const [plan] = upgradePlan([{ module: "webhooks-in", version: 1 }]);
      for (const step of plan!.steps) await client.query(step.sql);
      for (const step of plan!.steps) await client.query(step.sql);
      const { rows: after } = await client.query(
        `select e.secret, ds.decrypted_secret as vaulted
         from better_supabase.incoming_webhooks e
         left join vault.decrypted_secrets ds on ds.id = e.secret_id
         where e.id = $1`,
        [rows[0]!.id],
      );
      expect(after).toEqual([
        { secret: null, vaulted: "legacy-secret-0123456789" },
      ]);
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("dedupes message ids per source and tenant", async () => {
    const client = await pool.connect();
    const source = `inbox-${crypto.randomUUID().slice(0, 8)}`;
    try {
      await client.query("begin");
      for (const file of renderModules(["webhook-inbox"]))
        if (file.kind === "schema") await client.query(file.contents);
      const receive = async (tenant: string | null) =>
        (
          await client.query<{ duplicate: boolean }>(
            "select duplicate from better_supabase.receive_webhook($1, 'm1', null, '{}', '{}', $2)",
            [source, tenant],
          )
        ).rows[0]!.duplicate;
      expect(await receive("tenant-a")).toBe(false);
      expect(await receive("tenant-b")).toBe(false);
      expect(await receive(null)).toBe(false);
      expect(await receive("tenant-a")).toBe(true);
      expect(await receive(null)).toBe(true);
    } finally {
      await client.query("rollback");
      client.release();
    }
  });
});
