import { Pool, type PoolClient } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { SqlClient } from "../../src/postgres/executor.ts";
import type { KitLayout } from "../../src/sql/kit.ts";
import type {
  WebhookRequest,
  WebhookTransport,
} from "../../src/webhooks/index.ts";

import { renderKit } from "../../src/sql/kit.ts";
import {
  createWebhooks,
  sqlTransport,
  verifyWebhook,
} from "../../src/webhooks/index.ts";

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

const USERS = {
  owner: crypto.randomUUID(),
  member: crypto.randomUUID(),
} as const;
type Who = keyof typeof USERS;

const LAYOUT: KitLayout = {
  kits: { "webhooks-out": { options: { disableAfter: 2 } } },
};

class Session {
  private readonly client: PoolClient;

  constructor(client: PoolClient) {
    this.client = client;
  }

  async as(who: Who | "service"): Promise<void> {
    const claims =
      who === "service"
        ? { role: "service_role" }
        : { sub: USERS[who], role: "authenticated" };
    await this.client.query(
      "select set_config('request.jwt.claims', $1, true)",
      [JSON.stringify(claims)],
    );
  }

  async value<T>(sql: string, params: unknown[] = []): Promise<T> {
    const { rows } = await this.client.query<{ value: T }>(
      `select ${sql} as value`,
      params,
    );
    return rows[0]!.value;
  }

  async hint(sql: string, params: unknown[] = []): Promise<string> {
    await this.client.query("savepoint attempt");
    try {
      await this.client.query(sql, params);
    } catch (error) {
      await this.client.query("rollback to savepoint attempt");
      const failure = error as {
        code?: string;
        hint?: string;
        message: string;
      };
      return failure.hint ?? failure.code ?? failure.message;
    }
    await this.client.query("release savepoint attempt");
    return "no error";
  }
}

/** Answers each URL with the statuses queued for it, then 200. */
function fakeHttp(script: Record<string, number[]>) {
  const sent: WebhookRequest[] = [];
  const http: WebhookTransport = {
    apiVersion: 1,
    name: "fake",
    async send(request) {
      sent.push(request);
      const status = script[request.url]?.shift() ?? 200;
      return { status, body: `status ${String(status)}` };
    },
  };
  return { http, sent };
}

describe.skipIf(!live)("webhooks-out", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("fans out, signs, retries, dead-letters, disables and redelivers", async () => {
    const client = await pool.connect();
    const s = new Session(client);
    const sql: SqlClient = {
      async queryRaw<T>(text: string, params: unknown[] = []) {
        const { rows } = await client.query(text, params);
        // SAFETY: the test reads only the `value` column sqlTransport selects.
        return rows as T[];
      },
    };
    try {
      await client.query("begin");
      for (const who of Object.keys(USERS) as Who[]) {
        await client.query(
          `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at)
           values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now())`,
          [USERS[who], `${who}-${USERS[who]}@example.test`],
        );
      }
      for (const file of renderKit(
        ["organizations", "outbox", "webhooks-out"],
        LAYOUT,
      ))
        await client.query(file.contents);

      await s.as("owner");
      const org = await s.value<string>(
        "better_supabase.create_organization($1)",
        [{ name: "Acme", slug: `acme-wh-${USERS.owner.slice(0, 8)}` }],
      );
      await client.query(
        "insert into better_supabase.memberships (org_id, user_id, role) values ($1, $2, 'member')",
        [org, USERS.member],
      );
      const destination = async (url: string, types: string[]) => {
        const { rows } = await client.query<{ id: string }>(
          `insert into better_supabase.webhook_destinations (organization_id, name, url, event_kinds)
           values ($1, 'Hook', $2, $3) returning id`,
          [org, url, types],
        );
        return rows[0]!.id;
      };
      const billing = await destination("https://billing.example.com/hook", [
        "invoice.*",
      ]);
      const all = await destination("https://all.example.com/hook", ["*"]);
      const orgs = await destination("https://orgs.example.com/hook", [
        "org.created",
      ]);
      const billingSecret = await s.value<string>(
        "better_supabase.rotate_webhook_secret($1)",
        [billing],
      );
      expect(billingSecret).toMatch(/^whsec_/);
      for (const id of [all, orgs])
        await client.query("select better_supabase.rotate_webhook_secret($1)", [
          id,
        ]);

      // A member can neither see nor manage destinations.
      await client.query("set local role authenticated");
      await s.as("member");
      expect(
        await s.value(
          "(select count(*)::int from better_supabase.webhook_destinations)",
        ),
      ).toBe(0);
      expect(
        await s.hint("select better_supabase.dispatch_webhook($1, 'x', '{}')", [
          billing,
        ]),
      ).toBe("WEBHOOK_FORBIDDEN");
      expect(
        await s.hint("select better_supabase.webhook_secrets($1)", [billing]),
      ).toBe("42501");
      await s.as("owner");
      expect(
        await s.value(
          "(select count(*)::int from better_supabase.webhook_destinations)",
        ),
      ).toBe(3);
      await client.query("reset role");

      // Rotating keeps the old secret signing during the overlap.
      await s.as("service");
      const rotated = await s.value<string>(
        "better_supabase.rotate_webhook_secret($1, '1 hour')",
        [billing],
      );
      expect(
        await s.value<string[]>("better_supabase.webhook_secrets($1)", [
          billing,
        ]),
      ).toEqual([rotated, billingSecret]);
      expect(Buffer.from(rotated.slice(6), "base64")).toHaveLength(32);

      // Deleting a destination deletes its Vault secrets.
      const doomed = await destination("https://gone.example.com/hook", ["*"]);
      await client.query("select better_supabase.rotate_webhook_secret($1)", [
        doomed,
      ]);
      const vaultIds = async () =>
        (
          await client.query<{ n: number }>(
            `select count(*)::int as n from vault.secrets
             where name like 'webhook:' || $1::text || ':%'`,
            [doomed],
          )
        ).rows[0]!.n;
      expect(await vaultIds()).toBe(1);
      await client.query(
        "delete from better_supabase.webhook_destinations where id = $1",
        [doomed],
      );
      expect(await vaultIds()).toBe(0);

      const { http, sent } = fakeHttp({
        "https://billing.example.com/hook": [500],
        "https://all.example.com/hook": [400, 400],
      });
      const webhooks = createWebhooks({ transport: sqlTransport(sql), http });

      expect(
        await webhooks
          .publish({
            type: "invoice.paid",
            data: { id: 7 },
            tenant: org,
            id: "evt-1",
          })
          .orThrow(),
      ).toBe(2);
      expect(
        await webhooks
          .publish({
            type: "invoice.paid",
            data: { id: 7 },
            tenant: org,
            id: "evt-1",
          })
          .orThrow(),
      ).toBe(0);
      expect(
        await webhooks
          .publish({
            type: "invoice.paid",
            data: {},
            tenant: crypto.randomUUID(),
          })
          .orThrow(),
      ).toBe(0);
      const direct = await webhooks
        .dispatch({
          destinationId: orgs,
          type: "run.finished",
          data: { ok: true },
          runId: "run-1",
          eventId: "evt-2",
        })
        .orThrow();
      expect(
        await webhooks
          .dispatch({
            destinationId: orgs,
            type: "run.finished",
            data: {},
            eventId: "evt-2",
          })
          .orThrow(),
      ).toBe(direct);

      expect(await webhooks.deliver()).toEqual({
        completed: 1,
        failed: 1,
        deadLettered: 1,
        canceled: 0,
        disabled: 0,
      });
      const billingRequest = sent.find((request) =>
        request.url.includes("billing"),
      )!;
      const verified = await verifyWebhook(
        { headers: billingRequest.headers, body: billingRequest.body },
        billingSecret,
      );
      expect(verified.ok && verified.data.payload).toMatchObject({
        type: "invoice.paid",
        data: { id: 7 },
      });
      const log = await s.value<
        { status: string; attempt: number; response_status: number }[]
      >(
        `(select jsonb_agg(jsonb_build_object('status', status, 'attempt', attempt, 'response_status', response_status) order by status)
          from better_supabase.webhook_deliveries)`,
      );
      expect(log).toEqual([
        { status: "completed", attempt: 1, response_status: 200 },
        { status: "dead_lettered", attempt: 1, response_status: 400 },
        { status: "failed", attempt: 1, response_status: 500 },
      ]);

      // A second dead letter in a row disables the destination.
      await webhooks
        .publish({ type: "invoice.void", data: {}, tenant: org, id: "evt-3" })
        .orThrow();
      await client.query(
        "update better_supabase.webhook_deliveries set available_at = now() where status = 'failed'",
      );
      const second = await webhooks.deliver();
      expect(second).toMatchObject({
        completed: 2,
        deadLettered: 1,
        disabled: 1,
      });
      expect(
        await s.value(
          "(select enabled from better_supabase.webhook_destinations where id = $1)",
          [all],
        ),
      ).toBe(false);

      // Deliveries to a disabled destination are canceled; enabling it again clears the streak.
      await webhooks
        .publish({ type: "org.renamed", data: {}, tenant: org })
        .orThrow();
      await client.query(
        "insert into better_supabase.webhook_deliveries (organization_id, destination_id, event_kind) values ($1, $2, 'late')",
        [org, all],
      );
      expect(await webhooks.deliver()).toMatchObject({ completed: 0 });
      expect(
        await s.value(
          "(select status from better_supabase.webhook_deliveries where event_kind = 'late')",
        ),
      ).toBe("canceled");
      await client.query(
        "update better_supabase.webhook_destinations set enabled = true where id = $1",
        [all],
      );
      expect(
        await s.value(
          "(select consecutive_failures || '/' || coalesce(disabled_at::text, 'null') from better_supabase.webhook_destinations where id = $1)",
          [all],
        ),
      ).toBe("0/null");

      // Redelivering a dead letter queues it again from the first attempt.
      const dead = await s.value<string>(
        "(select id from better_supabase.webhook_deliveries where status = 'dead_lettered' limit 1)",
      );
      await s.as("owner");
      expect(
        await s.value("better_supabase.redeliver_webhook($1)", [dead]),
      ).toBe(dead);
      expect(
        await s.hint("select better_supabase.redeliver_webhook($1)", [dead]),
      ).toBe("WEBHOOK_DELIVERY_IN_PROGRESS");
      await s.as("service");
      expect(await webhooks.deliver()).toMatchObject({ completed: 1 });

      expect(
        await s.value(
          "(select count(*)::int from better_supabase.outbox_events where type = 'webhook.disabled')",
        ),
      ).toBe(1);
    } finally {
      await client.query("rollback");
      client.release();
    }
  });
});
