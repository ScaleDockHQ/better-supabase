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

  it("reads a before trigger that assigns new.column", () => {
    expect(
      writtenValues(
        `create function public.on_stage() returns trigger language plpgsql as $$
begin
  if new.stage = 'won' then
    new.status := 'closed';
  else
    new."status" := 'open';
  end if;
  new.note := 'x';
  return new;
end;
$$;
create trigger t_on_stage before update of stage on ${table} for each row execute function public.on_stage();`,
        table,
        "status",
      ),
    ).toEqual(["closed", "open"]);
  });

  it("ignores a trigger function on another table", () => {
    expect(
      writtenValues(
        `create function public.f() returns trigger language plpgsql as $$ begin new.status := 'closed'; return new; end; $$;
create trigger t before insert on public.other for each row execute function public.f();`,
        table,
        "status",
      ),
    ).toEqual([]);
  });

  it("stops an update at the end of its statement", () => {
    expect(
      writtenValues(
        `update ${table} set status = 'held'; insert into public.other (x) select 'digested' from y;`,
        table,
        "status",
      ),
    ).toEqual(["held"]);
  });

  it("stops an insert select at the end of its statement", () => {
    expect(
      writtenValues(
        `insert into ${table} (status) select 'held'; perform f('digested') from z;`,
        table,
        "status",
      ),
    ).toEqual(["held"]);
  });

  it("reads an insert with a table alias", () => {
    expect(
      writtenValues(
        `insert into ${table} as d (status) values ('held');`,
        table,
        "status",
      ),
    ).toEqual(["held"]);
  });

  it("reads an uppercase do update set", () => {
    expect(
      writtenValues(
        `insert into ${table} (id, status) values ('a', 'pending') ON CONFLICT (id) DO UPDATE SET status = 'sent';`,
        table,
        "status",
      ),
    ).toEqual(["pending", "sent"]);
  });

  it("does not pair a trigger with the next statement's table", () => {
    expect(
      writtenValues(
        `create function public.f() returns trigger language plpgsql as $$ begin new.status := 'closed'; return new; end; $$;
select format('create trigger t before insert on %s for each row', 'x');
create trigger t2 before insert on ${table} for each row execute function public.g();
create trigger t3 before insert on public.other for each row execute function public.f();`,
        table,
        "status",
      ),
    ).toEqual([]);
  });

  it("ignores an after trigger", () => {
    expect(
      writtenValues(
        `create function public.f() returns trigger language plpgsql as $$ begin new.status := 'closed'; return new; end; $$;
create trigger t after insert on ${table} for each row execute function public.f();`,
        table,
        "status",
      ),
    ).toEqual([]);
  });
});
