import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";
import type { BlockSqlAccessProvider } from "../../../src/sql/module-types.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { moduleProvider } from "../../fixtures/authorization-provider.ts";

const sqlOf = (
  modules: AnyBlocksConfig,
  installed: readonly string[] = ["calendar"],
): string =>
  renderBlocks(installed, { modules })
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
    expect(() =>
      sqlOf({ calendar: { options: { feed: { visibility: "private" } } } }, [
        "calendar",
        "share-links",
      ]),
    ).toThrow(/"access" or "public"/u);
    expect(() =>
      sqlOf({ calendar: { options: { feed: { limit: 0 } } } }, [
        "calendar",
        "share-links",
      ]),
    ).toThrow(/between 1 and 100000/u);
  });

  it("uses bounded feed defaults", () => {
    const sql = sqlOf({ calendar: {}, "share-links": {} }, [
      "calendar",
      "share-links",
    ]);

    expect(sql).toContain("interval '366 days'");
    expect(sql).toContain("limit 5000");
  });

  it("includes attendees and the feed user's reminders in feed events", () => {
    const sql = sqlOf({ calendar: {}, "share-links": {}, reminders: {} }, [
      "calendar",
      "reminders",
      "share-links",
    ]);

    expect(sql).toContain("'attendees'");
    expect(sql).toContain("'reminders'");
    expect(sql).toContain('r."user_id" = v_creator');
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

  it("checks calendar access through the provider's row grants for the given user", () => {
    const provider: BlockSqlAccessProvider = {
      ...moduleProvider,
      functions: {
        ...moduleProvider.functions,
        rowsWith: "authz.rows_{resource}({permission}, {ids})",
        rowsWithFor: "authz.rows_{resource}_for({user}, {permission}, {ids})",
      },
    };

    const render = (accessProvider: BlockSqlAccessProvider) =>
      renderBlocks(["calendar"], {
        accessProvider,
        modules: {
          permissions: { model: "provider" },
          calendar: {
            options: {
              access: true,
              accessFunctions: {
                read: { rows: "agenda_calendar", key: "agendaCalendar.read" },
                write: {
                  rows: "agenda_calendar",
                  key: "agendaCalendar.update",
                },
                share: { rows: "agenda_calendar", key: "agendaCalendar.share" },
              },
            },
          },
        },
      })
        .filter((file) => file.module === "calendar")
        .map((file) => file.contents)
        .join("\n");

    const sql = render(provider);

    expect(sql).toContain(
      "calendar_access.calendar_id::text in (select r.id::text from authz.rows_agenda_calendar_for(calendar_access.user_id, 'agendaCalendar.read', array[calendar_access.calendar_id::text]) as r(id))",
    );
    expect(sql).toContain("'agendaCalendar.update'");
    expect(sql).toContain("'agendaCalendar.share'");

    const { rowsWithFor: _unused, ...callerOnly } = provider.functions;
    const own = render({ ...provider, functions: callerOnly });

    expect(own).toContain(
      "calendar_access.user_id = auth.uid() and calendar_access.calendar_id::text in (select r.id::text from authz.rows_agenda_calendar('agendaCalendar.read', array[calendar_access.calendar_id::text]) as r(id))",
    );
    expect(() =>
      sqlOf({
        calendar: {
          options: {
            access: true,
            accessFunctions: { read: { rows: "agenda_calendar", key: "x" } },
          },
        },
      }),
    ).toThrow(/rowsWith/u);
  });
});
