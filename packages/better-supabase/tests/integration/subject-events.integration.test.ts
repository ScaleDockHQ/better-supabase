import type { PoolClient } from "pg";

import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { ModuleLayout } from "../../src/sql/module-types.ts";

import { renderModules } from "../../src/sql/render.ts";
import { dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const ACME = "00000000-0000-4000-8000-000000000001";
const USER = "00000000-0000-4000-8000-0000000000a1";

const layout: ModuleLayout = {
  modules: {
    "state-machine": {
      options: {
        machines: {
          ticket_status: {
            table: "events_it.tickets",
            column: "status",
            initial: "open",
            tenant: "organization_id",
            transitions: { open: ["closed"], closed: [] },
          },
        },
      },
    },
    reminders: { schema: "events_it" },
  },
};

describe.skipIf(!live)("subject-bound events in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  let client: PoolClient;

  const payloads = async (type: string): Promise<Record<string, unknown>[]> =>
    (
      await client.query<{ payload: Record<string, unknown> }>(
        "select payload from better_supabase.outbox_events where type = $1 and organization_id = $2 order by position",
        [type, ACME],
      )
    ).rows.map((row) => row.payload);

  beforeAll(async () => {
    client = await pool.connect();
    await client.query("begin");
    await client.query(`create schema events_it;
      create table events_it.tickets (
        id text primary key,
        organization_id uuid not null,
        status text not null default 'open'
      );
      insert into events_it.tickets (id, organization_id) values ('t1', '${ACME}');`);

    for (const file of renderModules(
      ["outbox", "state-machine", "reminders"],
      layout,
    )) {
      if (file.kind !== "test") {
        await client.query(file.contents);
      }
    }
  });

  afterAll(async () => {
    await client.query("rollback");
    client.release();
    await pool.end();
  });

  it("status.changed carries the tenant and the previous status", async () => {
    await client.query(
      "select better_supabase.transition('ticket_status', 't1', 'closed', 'done')",
    );
    expect(await payloads("status.changed")).toEqual([
      {
        organizationId: ACME,
        subjectType: "ticket_status",
        subjectId: "t1",
        from: "open",
        to: "closed",
        reason: "done",
      },
    ]);
  });

  it("status.changed follows a direct update, without a stale reason, and skips a no-op", async () => {
    await client.query(
      `insert into events_it.tickets (id, organization_id) values ('t2', '${ACME}')`,
    );
    await client.query(
      "update events_it.tickets set status = 'open' where id = 't2'",
    );
    await client.query(
      "update events_it.tickets set status = 'closed' where id = 't2'",
    );

    const t2 = (await payloads("status.changed")).filter(
      (p) => p["subjectId"] === "t2",
    );

    expect(t2).toEqual([
      {
        organizationId: ACME,
        subjectType: "ticket_status",
        subjectId: "t2",
        from: "open",
        to: "closed",
        reason: null,
      },
    ]);
  });

  it("reminder.sent names the subject and the owner, once per occurrence", async () => {
    const { rows } = await client.query<{ id: string }>(
      `insert into events_it.reminders (tenant_id, subject_type, subject_id, user_id)
       values ($1, 'ticket', 't1', $2) returning id`,
      [ACME, USER],
    );

    const id = rows[0]!.id;

    const mark = async (): Promise<boolean> =>
      (
        await client.query<{ value: boolean }>(
          "select events_it.mark_reminder_sent($1, '2026-10-14T09:00:00Z') as value",
          [id],
        )
      ).rows[0]!.value;

    expect(await mark()).toBe(true);
    expect(await mark()).toBe(false);
    expect(await payloads("reminder.sent")).toEqual([
      {
        organizationId: ACME,
        id,
        subjectType: "ticket",
        subjectId: "t1",
        userId: USER,
      },
    ]);
  });
});
