import { describe, expect, it } from "vitest";

import { MAX_BATCH } from "../../src/core/batch-limit.ts";
import {
  batchFunction,
  defaultPartition,
  defaultPartitionName,
  dropExpiredPartitions,
} from "../../src/sql/shared.ts";

describe("batchFunction", () => {
  it("calls the single-row function per element with its own savepoint", () => {
    const sql = batchFunction({
      name: "app.record_many",
      call: "app.record",
      args: [
        ["kind", "text"],
        ["detail", "jsonb", "'{}'"],
        ["count", "integer"],
      ],
      returns: "text",
      result: "id",
      hint: "RECORD_BATCH",
    });

    expect(sql).toContain(
      "create or replace function app.record_many(events jsonb)",
    );
    expect(sql).toContain("security definer\nset search_path = ''");
    expect(sql).toContain("kind => batch_event ->> 'kind'");
    expect(sql).toContain(
      "detail => coalesce(nullif(batch_event -> 'detail', 'null'::jsonb), '{}')",
    );
    expect(sql).toContain("count => (batch_event ->> 'count')::integer");
    expect(sql).toContain(`jsonb_array_length(events) > ${String(MAX_BATCH)}`);
    expect(sql).toContain("hint = 'RECORD_BATCH_TOO_LARGE'");
    expect(sql).toContain("hint = 'RECORD_BATCH_NOT_ARRAY'");
    expect(sql).toContain("exception when others then");
    expect(sql).toContain("jsonb_build_object('id', batch_result)");
  });

  it("passes each element whole to a jsonb parameter, with a custom limit", () => {
    const sql = batchFunction({
      name: "app.send_many",
      call: "app.send",
      args: "item",
      returns: "jsonb",
      result: "sent",
      hint: "SEND_BATCH",
      max: 10,
    });

    expect(sql).toContain("item => batch_event");
    expect(sql).toContain("jsonb_array_length(events) > 10");
  });
});

describe("partition helpers", () => {
  it("names and creates the default partition only for a partitioned table", () => {
    const name = defaultPartitionName({ schema: "app", name: "events" });
    expect(name).toBe('"app"."events_default"');

    const sql = defaultPartition('"app"."events"', name);
    expect(sql).toContain("c.relkind from pg_catalog.pg_class c");
    expect(sql).toContain(
      'create table if not exists "app"."events_default" partition of "app"."events" default;',
    );
  });

  it("drops expired months, skipping the busy ones", () => {
    const sql = dropExpiredPartitions({
      table: '"app"."events"',
      cutoff: "now() - interval '30 days'",
      purged: "v_dropped",
      busy: "p.status <> 'done' and $1",
      using: ["v_flag"],
    });

    expect(sql).toContain(
      `better_supabase.expired_partitions('"app"."events"'::regclass, now() - interval '30 days')`,
    );
    expect(sql).toContain(
      "execute format('select exists (select 1 from %s p where p.status <> ''done'' and $1)', v_part) into v_part_busy using v_flag;",
    );
    expect(sql).toContain("continue when v_part_busy;");
    expect(sql).toContain("execute format('drop table %s', v_part);");
    expect(sql).toContain("v_dropped := v_dropped + v_part_rows;");
    expect(
      dropExpiredPartitions({
        table: '"app"."events"',
        cutoff: "null",
        purged: "n",
      }),
    ).not.toContain("v_part_busy");
  });
});
