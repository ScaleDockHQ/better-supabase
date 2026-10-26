import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../src/config/blocks.ts";

import { adoptedTables } from "../../src/sql/adopted-columns.ts";

const columnsOf = (
  modules: AnyBlocksConfig,
  ownTables: Readonly<Record<string, string>>,
  table: string,
): readonly string[] =>
  Object.keys(
    adoptedTables(modules, ownTables).find(
      (entry) => `${entry.schema}.${entry.table}` === table,
    )?.columns ?? {},
  );

describe("adopted columns of the opt-in modes", () => {
  it("checks the employee, name and flat detail columns only in their modes", () => {
    const own = {
      "public.staff": "app.sql",
      "public.staff_private": "app.sql",
      "public.work_entries": "app.sql",
      "public.week_sheets": "app.sql",
    };

    const tables = {
      employees: {
        tables: {
          employees: "public.staff",
          privateDetails: "public.staff_private",
          contracts: null,
        },
      },
      "time-tracking": {
        tables: {
          entries: "public.work_entries",
          timesheets: "public.week_sheets",
        },
        columns: { timesheets: { approval: null } },
      },
    } satisfies AnyBlocksConfig;

    expect(columnsOf(tables, own, "public.staff")).not.toContain("firstName");
    expect(columnsOf(tables, own, "public.staff_private")).not.toContain(
      "city",
    );
    expect(columnsOf(tables, own, "public.work_entries")).not.toContain(
      "employee",
    );
    expect(columnsOf(tables, own, "public.week_sheets")).not.toContain(
      "employee",
    );

    const opted: AnyBlocksConfig = {
      employees: {
        ...tables.employees,
        options: { name: "split", privateDetails: "flat" },
      },
      "time-tracking": {
        ...tables["time-tracking"],
        options: { approvals: false, owner: "employee" },
      },
    };

    expect(columnsOf(opted, own, "public.staff")).toContain("firstName");
    expect(columnsOf(opted, own, "public.staff_private")).toContain("city");
    expect(columnsOf(opted, own, "public.work_entries")).toContain("employee");
    expect(columnsOf(opted, own, "public.week_sheets")).toContain("employee");
  });

  it("checks the calendar access, detail and attendee columns only in their modes", () => {
    const own = {
      "public.calendars": "app.sql",
      "public.events": "app.sql",
      "public.attendees": "app.sql",
    };

    const base: AnyBlocksConfig = {
      calendar: {
        tables: {
          calendars: "public.calendars",
          events: "public.events",
          attendees: "public.attendees",
        },
      },
    };

    expect(columnsOf(base, own, "public.calendars")).not.toContain(
      "visibility",
    );
    expect(columnsOf(base, own, "public.attendees")).not.toContain("organizer");

    const opted: AnyBlocksConfig = {
      calendar: {
        ...base["calendar"],
        options: { access: true, calendarDetails: true, attendeeKey: "any" },
      },
    };

    expect(columnsOf(opted, own, "public.calendars")).toContain("visibility");
    expect(columnsOf(opted, own, "public.calendars")).toContain("rank");
    expect(columnsOf(opted, own, "public.events")).toContain("owner");
    expect(columnsOf(opted, own, "public.attendees")).toContain("organizer");
  });
});
