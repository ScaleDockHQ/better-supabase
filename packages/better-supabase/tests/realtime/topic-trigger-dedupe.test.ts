import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { PgliteConnection } from "../../src/lite/runtime.ts";

import { loadLite } from "../../src/lite/runtime.ts";
import { defineTopic } from "../../src/realtime/index.ts";
import { DEDUPE_SETTING } from "../../src/realtime/topic-trigger.ts";

const changes = defineTopic("org:{organizationId}:changes");

const audit = (options: { readonly dedupeKey?: readonly string[] } = {}) =>
  changes.trigger("public.audit_logs", {
    events: ["insert"],
    event: "changed",
    payload: { actor_id: "actor_id", category: "category", source: "source" },
    dedupe: "transaction",
    ...options,
  });

describe("realtime trigger dedupe SQL", () => {
  it("checks a transaction-local hash before each send", () => {
    const sql = audit();

    expect(sql).toContain("  msg jsonb;\n  sent text;");
    expect(sql).toContain(
      "sent := md5(jsonb_build_array('org:' || (vals ->> 'organizationId') || ':changes', 'changed', msg)::text);",
    );
    expect(sql).toContain(
      `perform set_config('${DEDUPE_SETTING}', coalesce(current_setting('${DEDUPE_SETTING}', true), '') || sent || ' ', true);`,
    );
    expect(sql).toContain(
      "perform realtime.send(msg, 'changed', 'org:' || (vals ->> 'organizationId') || ':changes', true);",
    );
    expect(sql).not.toContain("broadcast_topic(");
  });

  it("compares only the dedupeKey fields", () => {
    expect(audit({ dedupeKey: ["category"] })).toContain(
      "jsonb_build_array('org:' || (vals ->> 'organizationId') || ':changes', 'changed', jsonb_build_object('category', msg -> 'category'))",
    );
  });

  it("leaves a trigger without dedupe as it was", () => {
    const sql = changes.trigger("public.audit_logs", {
      payload: { category: "category" },
    });

    expect(sql).not.toContain("sent");
    expect(sql).toContain("perform realtime.send(body,");
  });

  it("generates a function instead of calling broadcast_topic()", () => {
    expect(
      changes.trigger("public.audit_logs", { dedupe: "transaction" }),
    ).toContain("create or replace function");
  });

  it("refuses dedupeKey without dedupe, or with no fields", () => {
    expect(() =>
      changes.trigger("public.audit_logs", { dedupeKey: ["category"] }),
    ).toThrow(/dedupeKey needs dedupe/);
    expect(() => audit({ dedupeKey: [] })).toThrow(/dedupeKey lists no fields/);
  });
});

describe(
  "realtime trigger dedupe on Postgres (PGlite)",
  { timeout: 60_000 },
  () => {
    let connection: PgliteConnection | undefined;

    const run = async (sql: string): Promise<void> => {
      await connection!.driver.exec(sql);
    };

    const count = async (): Promise<Record<string, number>> => {
      // SAFETY: the query selects a topic and a count per row.
      const { rows } = (await connection!.driver.query(
        "select topic, count(*)::int as n from realtime.messages group by topic",
      )) as { rows: { topic: string; n: number }[] };

      return Object.fromEntries(rows.map((row) => [row.topic, row.n]));
    };

    beforeAll(async () => {
      const lite = await loadLite();

      if (lite === undefined) {
        throw new Error("@supabase/lite is a devDependency of these tests");
      }

      connection = await lite.createPgliteConnection();

      await run(`
      do $$ begin
        if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon; end if;
        if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated; end if;
      end $$;
      create schema if not exists realtime;
      create table if not exists realtime.messages (topic text, event text, payload jsonb, private boolean);
      create or replace function realtime.send(payload jsonb, event text, topic text, private boolean default true)
        returns void language sql as $f$ insert into realtime.messages values (topic, event, payload, private) $f$;
      create table public.audit_logs (
        id serial primary key,
        organization_id text not null,
        actor_id text,
        category text,
        source text
      );
      create table public.tasks (id int primary key, organization_id text not null, title text);
      insert into public.tasks select n, case when n % 2 = 0 then 'a' else 'b' end, 't' from generate_series(1, 500) n;
      create function public.audit_tasks() returns trigger language plpgsql as $f$
      begin
        insert into public.audit_logs (organization_id, actor_id, category, source)
        values (new.organization_id, 'u1', 'tasks', 'app');
        return null;
      end $f$;
      create trigger audit_tasks after update on public.tasks for each row execute function public.audit_tasks();
      ${audit()}
    `);
    });

    afterAll(async () => {
      await connection?.close();
    });

    it("sends one message per key for a 500-row write in one transaction", async () => {
      await run("delete from realtime.messages");
      await run(
        "begin; insert into public.audit_logs (organization_id, actor_id, category, source) select 'a', 'u1', 'tasks', 'app' from generate_series(1, 500); commit;",
      );

      expect(await count()).toEqual({ "org:a:changes": 1 });
    });

    it("dedupes rows that a row trigger inserts, statement by statement", async () => {
      await run("delete from realtime.messages");
      await run(
        "begin; update public.tasks set title = 'x'; update public.tasks set title = 'y'; commit;",
      );

      expect(await count()).toEqual({ "org:a:changes": 1, "org:b:changes": 1 });
    });

    it("sends again in the next transaction", async () => {
      await run("delete from realtime.messages");
      await run(
        "update public.tasks set title = 'z' where organization_id = 'a'",
      );
      await run(
        "update public.tasks set title = 'w' where organization_id = 'a'",
      );

      expect(await count()).toEqual({ "org:a:changes": 2 });
    });

    it("sends a message per distinct payload", async () => {
      await run("delete from realtime.messages");
      await run(
        "insert into public.audit_logs (organization_id, actor_id, category, source) values ('a', 'u1', 'tasks', 'app'), ('a', 'u2', 'tasks', 'app'), ('a', 'u1', 'tasks', 'app')",
      );

      expect(await count()).toEqual({ "org:a:changes": 2 });
    });

    it("sends nothing on rollback, and the next transaction still sends", async () => {
      await run("delete from realtime.messages");
      await run(
        "begin; insert into public.audit_logs (organization_id, actor_id, category, source) values ('a', 'u1', 'tasks', 'app'); rollback;",
      );

      expect(await count()).toEqual({});

      await run(
        "insert into public.audit_logs (organization_id, actor_id, category, source) values ('a', 'u1', 'tasks', 'app')",
      );

      expect(await count()).toEqual({ "org:a:changes": 1 });
    });

    it("sends again after a rolled-back savepoint", async () => {
      await run("delete from realtime.messages");
      await run(`
      begin;
      savepoint s;
      insert into public.audit_logs (organization_id, actor_id, category, source) values ('a', 'u1', 'tasks', 'app');
      rollback to savepoint s;
      insert into public.audit_logs (organization_id, actor_id, category, source) values ('a', 'u1', 'tasks', 'app');
      commit;
    `);

      expect(await count()).toEqual({ "org:a:changes": 1 });
    });
  },
);
