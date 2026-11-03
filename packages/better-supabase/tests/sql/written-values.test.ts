import { describe, expect, it } from "vitest";

import { writtenValues } from "../../src/sql/written-values.ts";

const table = "public.notification_deliveries";

describe("writtenValues", () => {
  it("reads an insert with a column list and values", () => {
    expect(
      writtenValues(
        `insert into "public"."notification_deliveries" ("id", "status") values ('a', 'pending');`,
        table,
        "status",
      ),
    ).toEqual(["pending"]);
  });

  it("reads every row of a multi-row insert", () => {
    expect(
      writtenValues(
        `insert into ${table} (status, channel) values ('pending', 'email'), ('held', 'email');`,
        table,
        "status",
      ),
    ).toEqual(["pending", "held"]);
  });

  it("reads a case in an insert select", () => {
    expect(
      writtenValues(
        `insert into ${table} (id, status)
select r.id, case when c = 'in_app' then 'sent' else case when cadence(r.id) in ('daily', 'weekly') then 'held' else 'pending' end end
from recipients r;`,
        table,
        "status",
      ),
    ).toEqual(["sent", "held", "pending"]);
  });

  it("reads an update set assignment", () => {
    expect(
      writtenValues(
        `update ${table} d set status = 'digested', attempted_at = now() where d.id = any(ids);`,
        table,
        "status",
      ),
    ).toEqual(["digested"]);
  });

  it("reads an update with an alias", () => {
    expect(
      writtenValues(
        `update ${table} as d set "status" = 'held'::text where d.id = 'a';`,
        table,
        "status",
      ),
    ).toEqual(["held"]);
  });

  it("reads the do update set of an upsert", () => {
    expect(
      writtenValues(
        `insert into ${table} (recipient_id, status) values ('a', 'pending') on conflict (recipient_id) do update set status = 'sent';`,
        table,
        "status",
      ),
    ).toEqual(["pending", "sent"]);
  });

  it("ignores a value a parameter carries", () => {
    expect(
      writtenValues(
        `insert into ${table} (request_id, decision) values (v_req.id, approval_settle.decision);`,
        table,
        "decision",
      ),
    ).toEqual([]);
  });

  it("ignores literals of another column", () => {
    expect(
      writtenValues(
        `insert into ${table} (channel, status) values ('email', 'pending');`,
        table,
        "status",
      ),
    ).toEqual(["pending"]);
  });

  it("ignores literals only compared or declared", () => {
    expect(
      writtenValues(
        `create table ${table} (status text check (status in ('pending', 'held')));
select 1 from ${table} where status = 'held';`,
        table,
        "status",
      ),
    ).toEqual([]);
  });

  it("ignores comments", () => {
    expect(
      writtenValues(
        `-- insert into ${table} (status) values ('held');
/* update ${table} set status = 'digested'; */`,
        table,
        "status",
      ),
    ).toEqual([]);
  });

  it("ignores a value_unsupported label", () => {
    expect(
      writtenValues(
        `update ${table} set status = better_supabase.value_unsupported('archived');`,
        table,
        "status",
      ),
    ).toEqual([]);
  });

  it("unescapes a quote", () => {
    expect(
      writtenValues(
        `insert into ${table} (status) values ('it''s');`,
        table,
        "status",
      ),
    ).toEqual(["it's"]);
  });
});
