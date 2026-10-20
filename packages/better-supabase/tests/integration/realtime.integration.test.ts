import type { StandardSchemaV1 } from "@standard-schema/spec";

import { createClient } from "@supabase/supabase-js";
import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import {
  defineTopic,
  rowKeys,
  type TopicMessage,
} from "../../src/realtime/index.ts";
import { signLocalJwt } from "../../src/testing/local-key.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { stackDbUrl, stackEngine, stackUrl } from "./stack-env.ts";

const url = stackUrl();
const dbUrl = stackDbUrl();

const publishableKey =
  process.env["SUPABASE_PUBLISHABLE_KEY"] ??
  "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH";

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

const title: StandardSchemaV1<unknown, { title: string }> = {
  "~standard": {
    version: 1,
    vendor: "test",
    validate: (value) =>
      typeof value === "object" &&
      value !== null &&
      typeof (value as { title?: unknown }).title === "string"
        ? { value: { title: (value as { title: string }).title } }
        : { issues: [{ message: "title is required", path: ["title"] }] },
  },
};

const betterSupabase = defineSupabase(schema);
const customers = defineTopic("organization:{organizationId}:customers");

const notifications = defineTopic(
  "organization:{organizationId}:notifications:{userId}",
  {
    events: { created: title },
    send: true,
  },
);

function waitFor<T>(
  register: (resolve: (value: T) => void) => void,
  ms = 8000,
): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(new Error("timed out waiting for a message"));
    }, ms);

    register((value) => {
      clearTimeout(timer);
      resolve(value);
    });
  });
}

describe.skipIf(!live)("Realtime module", async () => {
  const clientFor = (organizationId: string) =>
    createClient(url, publishableKey, {
      accessToken: () =>
        signLocalJwt({
          sub: USER,
          role: "authenticated",
          tenant_id: organizationId,
        }),
    });

  const acme = clientFor(ACME);
  const other = clientFor(OTHER);
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  const kvk = `rt-${String(Date.now())}`;

  beforeAll(async () => {
    await pool.query(customers.sql());
    await pool.query(notifications.sql());
    await pool.query(
      customers.trigger("customers", {
        betterSupabase,
        values: { organizationId: "organizationId" },
      }),
    );
  });
  afterAll(async () => {
    await pool.query("delete from public.customers where kvk like $1", [
      `${kvk}%`,
    ]);
    acme.removeAllChannels();
    other.removeAllChannels();
    await pool.end();
  });

  it("fills a topic from parent rows and sends a custom event and payload", async () => {
    const client = await pool.connect();

    try {
      await client.query("begin");

      const tagged = defineTopic(
        "org:{organizationSlug}:customer:{customerId}",
      );

      await client.query(
        tagged.trigger("customerTags", {
          betterSupabase,
          values: {
            customerId: "customerId",
            organizationSlug: {
              from: "organizations",
              select: "slug",
              via: {
                from: "customers",
                select: "organizationId",
                via: "customerId",
              },
            },
          },
          event: { insert: "tag_added" },
          payload: {
            tagId: "tagId",
            customerName: {
              from: "customers",
              via: "customerId",
              select: "name",
            },
            operation: { sql: "lower(tg_op)" },
          },
        }),
      );

      const { rows: inserted } = await client.query<{
        customer: string;
        tag: string;
        slug: string;
      }>(
        `with c as (
           insert into public.customers (organization_id, name) values ($1, 'Lookup Co') returning id
         ), t as (
           insert into public.tags (organization_id, name) values ($1, 'lookup') returning id
         )
         select c.id::text as customer, t.id::text as tag,
           (select slug from public.organizations where id = $1) as slug
         from c, t`,
        [ACME],
      );

      const { customer, tag, slug } = inserted[0]!;
      await client.query(
        "insert into public.customer_tags (customer_id, tag_id, organization_id) values ($1, $2, $3)",
        [customer, tag, ACME],
      );

      const { rows } = await client.query<{
        event: string;
        payload: Record<string, unknown>;
        private: boolean;
      }>(
        "select event, payload, private from realtime.messages where topic = $1",
        [`org:${slug}:customer:${customer}`],
      );

      expect(rows).toEqual([
        {
          event: "tag_added",
          payload: {
            id: expect.any(String),
            tagId: tag,
            customerName: "Lookup Co",
            operation: "insert",
          },
          private: true,
        },
      ]);
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("sends row changes through broadcast_topic() from a topic.trigger()", async () => {
    const client = await pool.connect();

    try {
      await client.query("begin");
      const quotes = defineTopic("organization:{organizationId}:quotes");
      const byKvk = defineTopic("kvk:{kvk}", { private: false });
      await client.query(
        quotes.trigger("customers", { event: "customer.changed" }),
      );
      await client.query(byKvk.trigger("customers", { events: ["insert"] }));

      const { rows: created } = await client.query<{ id: string }>(
        "insert into public.customers (organization_id, name) values ($1, 'Trigger Co') returning id::text",
        [ACME],
      );

      const id = created[0]!.id;
      await client.query(
        "update public.customers set name = 'Trigger BV' where id = $1",
        [id],
      );

      const { rows } = await client.query<{
        event: string;
        payload: {
          operation: string;
          id: string;
          values: Record<string, string>;
          record?: unknown;
        };
        private: boolean;
      }>(
        "select event, payload, private from realtime.messages where topic = $1 order by payload->>'operation'",
        [`organization:${ACME}:quotes`],
      );

      expect(rows).toEqual([
        {
          event: "customer.changed",
          payload: expect.objectContaining({
            operation: "INSERT",
            schema: "public",
            table: "customers",
            id,
            values: { organizationId: ACME },
          }),
          private: true,
        },
        {
          event: "customer.changed",
          payload: expect.objectContaining({ operation: "UPDATE", id }),
          private: true,
        },
      ]);
      expect(rows.some((row) => "record" in row.payload)).toBe(false);

      const { rows: kvk } = await client.query(
        "select 1 from realtime.messages where topic like 'kvk:%'",
      );

      expect(kvk).toEqual([]);
      await client.query(
        "insert into public.customers (organization_id, name, kvk) values ($1, 'Kvk Co', $2)",
        [ACME, "012345678"],
      );

      const { rows: sent } = await client.query<{
        event: string;
        private: boolean;
      }>("select event, private from realtime.messages where topic = $1", [
        "kvk:012345678",
      ]);

      expect(sent).toEqual([{ event: "INSERT", private: false }]);

      const warnings: string[] = [];

      const onNotice = (notice: { message?: string | undefined }) => {
        warnings.push(notice.message ?? "");
      };

      client.on("notice", onNotice);
      await client.query(
        "insert into public.customers (organization_id, name, kvk) values ($1, 'Bad Co', 'a b')",
        [ACME],
      );
      client.off("notice", onNotice);
      expect(warnings).toEqual([
        expect.stringContaining("contains characters topics do not allow"),
      ]);

      const rowTopic = defineTopic("rows:{organizationId}");
      await client.query(rowTopic.trigger("customers", { payload: "row" }));
      await client.query(
        "update public.customers set name = 'Row BV' where id = $1",
        [id],
      );

      const { rows: full } = await client.query<{
        payload: { record: { name: string } };
      }>("select payload from realtime.messages where topic = $1", [
        `rows:${ACME}`,
      ]);

      expect(full.map((row) => row.payload.record.name)).toEqual(["Row BV"]);

      await client.query("savepoint before");
      await client.query(
        `create trigger bs_before before insert on public.customers
           for each row execute function better_supabase.broadcast_topic('x:{name}', '')`,
      );
      await expect(
        client.query(
          "insert into public.customers (organization_id, name) values ($1, 'Before Co')",
          [ACME],
        ),
      ).rejects.toThrow("runs after the write");
      await client.query("rollback to savepoint before");
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  it("filters updates with when.changed, and warns when a cascade hides the parent row", async () => {
    const client = await pool.connect();

    try {
      await client.query("begin");
      await client.query(`
        create table public.bs_rt_parents (id int primary key, org text not null);
        create table public.bs_rt_children (
          id int primary key,
          parent_id int not null references public.bs_rt_parents on delete cascade,
          status text not null,
          note text
        );
        insert into public.bs_rt_parents values (1, 'org-a'), (2, 'org-b');
      `);

      const board = defineTopic("rtboard:{org}:{parentId}");
      await client.query(
        board.trigger("public.bs_rt_children", {
          values: {
            org: {
              from: "public.bs_rt_parents",
              via: "parent_id",
              select: "org",
            },
            parentId: "parent_id",
          },
          when: { changed: ["status"] },
        }),
      );

      const sent = async (topic: string) =>
        (
          await client.query<{ event: string }>(
            "select event from realtime.messages where topic = $1 order by inserted_at, id",
            [topic],
          )
        ).rows.map((row) => row.event);

      await client.query(
        "insert into public.bs_rt_children values (10, 1, 'open', null), (20, 2, 'open', null)",
      );
      await client.query(
        "update public.bs_rt_children set note = 'only a note' where id = 10",
      );
      expect(await sent("rtboard:org-a:1")).toEqual(["INSERT"]);

      await client.query(
        "update public.bs_rt_children set status = 'done' where id = 10",
      );
      expect(await sent("rtboard:org-a:1")).toEqual(["INSERT", "UPDATE"]);

      await client.query("delete from public.bs_rt_children where id = 10");
      expect(await sent("rtboard:org-a:1")).toEqual([
        "INSERT",
        "UPDATE",
        "DELETE",
      ]);

      const warnings: string[] = [];

      const onNotice = (notice: { message?: string | undefined }) => {
        warnings.push(notice.message ?? "");
      };

      client.on("notice", onNotice);
      await client.query("delete from public.bs_rt_parents where id = 2");
      client.off("notice", onNotice);

      expect(await sent("rtboard:org-b:2")).toEqual(["INSERT"]);
      expect(warnings).toEqual([
        expect.stringContaining(
          "better-supabase: realtime lookup found no row for a delete on public.bs_rt_children",
        ),
      ]);
    } finally {
      await client.query("rollback");
      client.release();
    }
  });

  // Fails on the stack engine (see stackEngine); CI runs it on the legacy engine.
  it.skipIf(stackEngine)(
    "broadcasts row changes to the tenant topic",
    async () => {
      let retry: ReturnType<typeof setInterval> | undefined;
      let attempt = 0;

      const insert = () =>
        betterSupabase
          .connect(acme, { claims: { tenant_id: ACME } })
          .customers.create({
            organizationId: ACME,
            name: "Realtime Co",
            kvk: `${kvk}-${String((attempt += 1))}`,
          })
          .orThrow();

      const got = waitFor<TopicMessage>((resolve) => {
        const sub = customers.subscribe(
          acme,
          { organizationId: ACME },
          {
            INSERT: (_payload, message) => {
              resolve(message);
            },
          },
        );

        // A cold Realtime server acknowledges the join before it relays database
        // broadcasts, and a message sent in that gap is never delivered.
        void sub.ready.then(async () => {
          await insert();
          retry = setInterval(() => void insert(), 3000);
        });
      }, 15_000).finally(() => {
        clearInterval(retry);
      });

      const received = await got;
      expect(rowKeys(betterSupabase, "customers", received)).toMatchObject({
        operation: "INSERT",
        table: "customers",
        id: expect.any(String),
        values: { organizationId: ACME },
      });
      expect(rowKeys(betterSupabase, "notes", received)).toBeNull();
    },
    20_000,
  );

  it("refuses private topics of another tenant", async () => {
    const sub = customers.subscribe(other, { organizationId: ACME }, {});
    await expect(sub.ready).rejects.toThrow(/./);
    await sub.unsubscribe();
  }, 20_000);

  // Fails on the stack engine (see stackEngine); CI runs it on the legacy engine.
  it.skipIf(stackEngine)(
    "sends validated events over HTTP",
    async () => {
      const values = { organizationId: ACME, userId: USER };

      const invalid = await notifications.send(acme, values, "created", {
        nope: true,
      });

      expect(invalid.error).toMatchObject({
        kind: "validation",
        issues: [{ path: ["title"] }],
      });

      let retry: ReturnType<typeof setInterval> | undefined;

      const send = () =>
        notifications
          .send(acme, values, "created", { title: "Hello" })
          .orThrow();

      const message = await waitFor<{ title: string }>((resolve) => {
        const sub = notifications.subscribe(acme, values, {
          created: (payload) => {
            resolve(payload);
          },
        });

        // Same cold-server gap as the row broadcast above.
        void sub.ready.then(async () => {
          await send();
          retry = setInterval(() => void send(), 3000);
        });
      }, 15_000).finally(() => {
        clearInterval(retry);
      });

      expect(message).toEqual({ title: "Hello" });

      const denied = await notifications.send(other, values, "created", {
        title: "Hi",
      });

      expect(denied.ok).toBe(false);
    },
    20_000,
  );
});
