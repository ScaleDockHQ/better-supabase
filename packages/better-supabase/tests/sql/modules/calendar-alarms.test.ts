import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";

const sqlOf = (modules: AnyBlocksConfig = {}): string =>
  renderBlocks(["calendar"], { modules })
    .filter((file) => file.module === "calendar")
    .map((file) => file.contents)
    .join("\n");

describe("calendar alarms", () => {
  it("keeps alarms in their own table, saved and read with the event", () => {
    const sql = sqlOf();

    expect(sql).toContain(
      'create table if not exists "better_supabase"."calendar_event_alarms"',
    );
    expect(sql).toContain("if v_item ? 'alarms' then");
    expect(sql).toContain(`'alarms', coalesce((select jsonb_agg(`);
    expect(sql).toContain(
      '("trigger_minutes" is null) <> ("trigger_at" is null)',
    );
  });

  it("drops alarms with the table", () => {
    const sql = sqlOf({ calendar: { tables: { alarms: null } } });

    expect(sql).not.toContain("calendar_event_alarms");
    expect(sql).not.toContain("'alarms'");
  });

  it("refuses an absolute trigger when the table has no column for it", () => {
    const sql = sqlOf({
      calendar: { columns: { alarms: { triggerAt: null } } },
    });

    expect(sql).not.toContain('"trigger_at"');
    expect(sql).toContain("triggerAt");
  });
});
