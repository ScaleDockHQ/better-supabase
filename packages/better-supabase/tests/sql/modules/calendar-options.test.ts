import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";

const sqlOf = (modules: AnyBlocksConfig): string =>
  renderBlocks(["calendar"], { modules })
    .filter((file) => file.module === "calendar")
    .map((file) => file.contents)
    .join("\n");

describe("calendar options", () => {
  it("refuses options it can't use", () => {
    expect(() =>
      sqlOf({ calendar: { options: { accessFunctions: { read: "x" } } } }),
    ).toThrow(/needs options.access/u);
    expect(() =>
      sqlOf({
        calendar: {
          options: { access: true, accessFunctions: { read: "no_schema" } },
        },
      }),
    ).toThrow(/schema-qualified/u);
    expect(() =>
      sqlOf({ calendar: { options: { recurrence: "rows" } } }),
    ).toThrow(/"inline" or "table"/u);
    expect(() =>
      sqlOf({ calendar: { options: { attendeeKey: "phone" } } }),
    ).toThrow(/"email" or "any"/u);
  });

  it("calls the app's access functions in place of grants", () => {
    const sql = sqlOf({
      calendar: {
        options: {
          access: true,
          accessFunctions: {
            read: "public.can_read_calendar",
            write: "public.can_write_calendar",
          },
        },
      },
    });

    expect(sql).toContain('"public"."can_read_calendar"');
    expect(sql).toContain('"public"."can_write_calendar"');
  });

  it("creates the rules and dates tables in table mode", () => {
    const sql = sqlOf({ calendar: { options: { recurrence: "table" } } });

    expect(sql).toContain("calendar_event_dates");
    expect(sql).toContain("calendar_event_rules");
  });
});
