import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { CloudEvent } from "../../src/events/index.ts";
import type { SqlClient } from "../../src/postgres/executor.ts";

import { createOutbox } from "../../src/blocks/outbox/index.ts";
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
const SCHEMA = `bs_outbox_${crypto.randomUUID().slice(0, 8)}`;

describe.skipIf(!live)("outbox", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 3 });
  const sql: SqlClient = {
    queryRaw: async <T>(text: string, params?: unknown[]) =>
      // SAFETY: the caller names the row shape of its own query.
      (await pool.query(text, params)).rows as T[],
  };
  const outbox = createOutbox(sql, {
    schema: SCHEMA,
    source: "https://crm.example.com",
  });
  let registered = true;

  beforeAll(async () => {
    const { rows } = await pool.query(
      "select to_regclass('better_supabase.modules') is not null and exists (select 1 from better_supabase.modules where name = 'outbox') as present",
    );
    registered = Boolean(rows[0]?.present);
    const layout = {
      modules: { outbox: { schema: SCHEMA, idType: "text" as const } },
    };
    const client = await pool.connect();
    try {
      await client.query("begin");
      for (const file of renderModules(["outbox"], layout))
        await client.query(file.contents);
      await client.query(
        `create table ${SCHEMA}.widgets (id bigint primary key, organization text, name text)`,
      );
      await client.query(
        `select ${SCHEMA}.track_events('${SCHEMA}.widgets', 'widget', 'organization')`,
      );
      await client.query("commit");
    } catch (error) {
      await client.query("rollback");
      throw error;
    } finally {
      client.release();
    }
  });

  afterAll(async () => {
    await pool.query(`drop schema if exists ${SCHEMA} cascade`);
    if (!registered) {
      await pool.query(
        "delete from better_supabase.modules where name = 'outbox'",
      );
    }
    await pool.end();
  });

  it("holds back events of open transactions so none is skipped", async () => {
    expect(
      (await outbox.register("crm", { types: ["organization.*", "widget.*"] }))
        .ok,
    ).toBe(true);
    const slow = await pool.connect();
    const sent: CloudEvent[] = [];
    const sink = {
      send: (events: readonly CloudEvent[]) => void sent.push(...events),
    };
    try {
      await slow.query("begin");
      await slow.query(
        `select ${SCHEMA}.emit_event('organization.slow', '{}'::jsonb, 'organizations/1')`,
      );
      const fast = await outbox.emit(
        "organization.fast",
        { n: 1 },
        { tenant: "t1" },
      );
      expect(fast.ok).toBe(true);
      expect((await outbox.emit("other.type")).ok).toBe(true);

      expect(await outbox.relay("crm", sink)).toEqual({ delivered: 0 });
      await slow.query("commit");
    } finally {
      slow.release();
    }
    expect(await outbox.relay("crm", sink)).toEqual({ delivered: 2 });
    expect(sent.map((event) => event.type)).toEqual([
      "dev.better-supabase.organization.slow",
      "dev.better-supabase.organization.fast",
    ]);
    expect(sent[1]).toMatchObject({ partitionkey: "t1", data: { n: 1 } });
    expect(await outbox.relay("crm", sink)).toEqual({ delivered: 0 });
  });

  it("delivers an event whose transaction commits after a later one", async () => {
    expect((await outbox.register("late", { types: ["late.*"] })).ok).toBe(
      true,
    );
    const sent: CloudEvent[] = [];
    const sink = {
      send: (events: readonly CloudEvent[]) => void sent.push(...events),
    };
    const early = await pool.connect();
    try {
      await early.query("begin");
      await early.query(
        `select ${SCHEMA}.emit_event('late.first', '{}'::jsonb)`,
      );
      expect((await outbox.emit("late.second")).ok).toBe(true);
      expect(await outbox.relay("late", sink)).toEqual({ delivered: 0 });
      await early.query("commit");
    } finally {
      early.release();
    }
    expect(await outbox.relay("late", sink)).toEqual({ delivered: 2 });
    expect(sent.map((event) => event.type)).toEqual([
      "dev.better-supabase.late.first",
      "dev.better-supabase.late.second",
    ]);
    expect((await outbox.unregister("late")).data).toBe(true);
  });

  it("deduplicates keys, tracks rows and keeps history", async () => {
    const first = await outbox.emit(
      "invoice.paid",
      {},
      { tenant: "t2", key: "inv-9" },
    );
    const again = await outbox.emit(
      "invoice.paid",
      {},
      { tenant: "t2", key: "inv-9" },
    );
    const other = await outbox.emit(
      "invoice.paid",
      {},
      { tenant: "t3", key: "inv-9" },
    );
    expect(again.data).toBe(first.data);
    expect(other.data).not.toBe(first.data);

    await pool.query(
      `insert into ${SCHEMA}.widgets values (1, 'acme', 'Bolt')`,
    );
    await pool.query(`update ${SCHEMA}.widgets set name = 'Nut' where id = 1`);
    await pool.query(`update ${SCHEMA}.widgets set name = 'Nut' where id = 1`);
    const history = await outbox.history({ subject: "widgets/1" });
    expect(history.data?.map((event) => event.type)).toEqual([
      "widget.created",
      "widget.updated",
    ]);
    expect(history.data?.[1]).toMatchObject({
      tenant: "acme",
      source: "better-supabase/track_events",
      payload: { row: { name: "Nut" } },
    });
  });

  it("hands consume handlers the rows with the actor", async () => {
    expect((await outbox.register("rows", { types: ["rows.*"] })).ok).toBe(
      true,
    );
    const actor = crypto.randomUUID();
    const client = await pool.connect();
    try {
      await client.query("begin");
      await client.query("select set_config('request.jwt.claims', $1, true)", [
        JSON.stringify({ sub: actor, role: "authenticated" }),
      ]);
      await client.query(
        `select ${SCHEMA}.emit_event('rows.created', '{"n":1}', null, 'tenant-1')`,
      );
      await client.query("commit");
    } finally {
      client.release();
    }
    const seen: {
      type: string;
      actorId: string | null;
      tenant: string | null;
    }[] = [];
    expect(
      await outbox.consume("rows", (events) => {
        seen.push(
          ...events.map(({ type, actorId, tenant }) => ({
            type,
            actorId,
            tenant,
          })),
        );
      }),
    ).toEqual({ delivered: 1 });
    expect(seen).toEqual([
      { type: "rows.created", actorId: actor, tenant: "tenant-1" },
    ]);
    expect((await outbox.unregister("rows")).data).toBe(true);
  });

  it("keeps the lease to one worker and purges only what consumers passed", async () => {
    await outbox.register("audit", { fromStart: true });
    const { rows } = await pool.query(
      `select ${SCHEMA}.outbox_claim('audit', 'w1', 1) as a, ${SCHEMA}.outbox_claim('audit', 'w2', 1) as b`,
    );
    expect(rows[0].a).toHaveLength(1);
    expect(rows[0].b).toEqual([]);
    await pool.query(`select ${SCHEMA}.outbox_ack('audit', 'w1', null)`);

    expect((await outbox.purge("0 seconds")).data).toBe(0);
    await outbox.relay("audit", { send: () => undefined });
    await outbox.relay("crm", { send: () => undefined });
    expect((await outbox.purge("0 seconds")).data).toBeGreaterThan(0);
  });
});
