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
      '("offset_minutes" is null) <> ("trigger_at" is null)',
    );
    expect(sql).toContain('and "user_id" is null;');
  });

  it("drops alarms with the table", () => {
    const sql = sqlOf({ calendar: { tables: { alarms: null } } });

    expect(sql).not.toContain("calendar_event_alarms");
    expect(sql).not.toContain("'alarms'");
  });

  it("refuses an absolute trigger when the table has no column for it", () => {
    const sql = sqlOf({ calendar: { columns: { alarms: { at: null } } } });

    expect(sql).not.toContain('"trigger_at"');
    expect(sql).toContain("or x ->> 'at' is not null");
  });

  it("reads the app's alarm table in reads and feeds, per user when it has one", () => {
    const modules: AnyBlocksConfig = {
      calendar: {
        tables: { alarms: "public.event_alarms" },
        columns: {
          alarms: {
            offsetMinutes: "minutes_before",
            method: "action",
            user: "user_id",
            related: null,
            at: null,
            repeat: null,
            repeatMinutes: null,
            description: null,
            summary: null,
            createdAt: null,
          },
        },
      },
    };

    const sql = renderBlocks(["calendar", "share-links"], {
      modules,
      ownTables: { "public.event_alarms": "app.sql" },
    })
      .filter((file) => file.module === "calendar")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).not.toContain(
      'create table if not exists "public"."event_alarms"',
    );
    expect(sql).toContain("'reminders', coalesce((select jsonb_agg(");
    expect(sql).toContain('l."user_id" = v_creator');
    expect(sql).toContain(`- 'alarms') || jsonb_build_object('reminders'`);
  });

  it("refuses the feed's former reminders option", () => {
    expect(() =>
      renderBlocks(["calendar", "share-links"], {
        modules: {
          calendar: {
            options: {
              feed: {
                reminders: {
                  table: "public.a",
                  event: "e",
                  offsetMinutes: "m",
                },
              },
            },
          },
        },
      }),
    ).toThrow(/tables\.alarms/u);
  });
});
