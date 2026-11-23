import { describe, expect, it } from "vitest";

import type { BlockConfig } from "../../../src/config/blocks.ts";

import { moduleBody, renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const audit = (config: BlockConfig = {}) =>
  moduleBody("audit", { modules: { audit: config } })!;

const withHousekeeping = (config: BlockConfig) =>
  renderBlocks(["audit", "housekeeping"], { modules: { audit: config } });

const schemaSql = (config: BlockConfig): string[] => [
  "create schema if not exists better_supabase;",
  ...withHousekeeping(config)
    .filter((file) => file.kind === "schema")
    .map((file) => file.contents),
];

const DELETE_CHECK = `do $$
declare
  v_run jsonb;
begin
  insert into better_supabase.audit_events (table_name, op, occurred_at)
  values ('public.notes', 'insert', now() - interval '100 days'),
         ('public.notes', 'insert', now() - interval '10 days');
  v_run := better_supabase.maintenance('audit_retention');
  if v_run -> 0 ->> 'status' <> 'ok' or (v_run -> 0 -> 'result' ->> 'purged')::int <> 1 then
    raise exception 'run %', v_run;
  end if;
  if (select count(*) from better_supabase.audit_events) <> 1 then
    raise exception 'the old entry survived';
  end if;
end;
$$;`;

const DETACH_CHECK = `do $$
declare
  v_run jsonb;
begin
  create table better_supabase.audit_events_p202001 partition of better_supabase.audit_events
    for values from ('2020-01-01 00:00:00+00') to ('2020-02-01 00:00:00+00');
  insert into better_supabase.audit_events (table_name, op, occurred_at)
  values ('public.notes', 'insert', '2020-01-15 00:00:00+00'),
         ('public.notes', 'insert', now());
  v_run := better_supabase.maintenance('audit_retention');
  if v_run -> 0 ->> 'status' <> 'ok' or (v_run -> 0 -> 'result' ->> 'detached')::int <> 1 then
    raise exception 'run %', v_run;
  end if;
  if (select count(*) from better_supabase.audit_events) <> 1 then
    raise exception 'the detached month still reads through the log';
  end if;
  if (select count(*) from better_supabase.audit_events_p202001) <> 1 then
    raise exception 'the detached month lost its rows';
  end if;
end;
$$;`;

describe("audit retention", () => {
  it("keeps every entry when unset", () => {
    expect(audit()).not.toContain("audit_retention_run");
    expect(
      withHousekeeping({})
        .map((file) => file.contents)
        .join("\n"),
    ).not.toContain("'audit_retention'");
  });

  it("adds the audit_retention job to maintenance()", () => {
    const sql = withHousekeeping({ options: { retention: { keep: "1 year" } } })
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain(
      "('audit_retention', 'better_supabase.audit_retention_run', interval '1 hour')",
    );
    expect(sql).toContain(
      "v_purged := better_supabase.purge_audit_log(interval '1 year', 10000);",
    );
    expect(sql).not.toContain("detach partition");
  });

  it("detaches whole months and creates the coming ones on a partitioned log", () => {
    const sql = audit({
      options: {
        partitioned: true,
        retention: { keep: "6 months", onExpire: "detach", batch: 500 },
      },
    });

    expect(sql).toContain("alter table %s detach partition %s");
    expect(sql).toContain(
      "v_created := better_supabase.maintain_partitions();",
    );
    expect(sql).toContain("purge_audit_log(interval '6 months', 500)");
  });

  it("refuses detach without a partitioned log, and a bad interval", () => {
    expect(() =>
      audit({ options: { retention: { keep: "1 year", onExpire: "detach" } } }),
    ).toThrow('onExpire "detach" needs a log the block owns');
    expect(() =>
      audit({ options: { retention: { keep: "forever" } } }),
    ).toThrow('keep must be an interval such as "90 days"');
    expect(() =>
      audit({ options: { retention: { keep: "1 year", batch: 0 } } }),
    ).toThrow("batch must be a positive integer");
  });

  it("installs housekeeping when retention is set", () => {
    expect(
      renderBlocks(["audit"], {
        modules: { audit: { options: { retention: { keep: "1 year" } } } },
      }).some((file) => file.module === "housekeeping"),
    ).toBe(true);
  });

  it(
    "deletes entries past keep from maintenance()",
    { timeout: 60_000 },
    async () => {
      await using stack = await liteStack({
        driver: "pglite",
        migrations: schemaSql({ options: { retention: { keep: "90 days" } } }),
        seed: [DELETE_CHECK],
      });

      expect(stack.url).not.toBe("");
    },
  );

  it(
    "detaches a month past keep and leaves its table",
    { timeout: 60_000 },
    async () => {
      await using stack = await liteStack({
        driver: "pglite",
        migrations: schemaSql({
          options: {
            partitioned: true,
            retention: { keep: "1 year", onExpire: "detach" },
          },
        }),
        seed: [DETACH_CHECK],
      });

      expect(stack.url).not.toBe("");
    },
  );
});
