import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../src/config/blocks.ts";

import { renderBlocks } from "../../src/sql/render.ts";
import {
  appValues,
  checkedValueMaps,
  readValue,
  valueIn,
  writeValue,
} from "../../src/sql/value-maps.ts";
import { ownTablesOf } from "../fixtures/own-tables.ts";

const TABLES = {
  items: {
    columns: { state: "state", priority: "priority", title: "title" },
    typed: ["state"],
    mappable: ["priority"],
  },
};

const render = (
  modules: AnyBlocksConfig,
  blocks: readonly string[],
  module: string,
): string =>
  renderBlocks(blocks, { modules, ownTables: ownTablesOf(modules, blocks) })
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("value maps", () => {
  it("checks tables, columns and labels", () => {
    expect(
      checkedValueMaps(
        "blocks.tasks",
        { items: { state: { started: ["a", "b"] } } },
        TABLES,
      ),
    ).toEqual({ items: { state: { started: ["a", "b"] } } });
    expect(() =>
      checkedValueMaps("blocks.tasks", { nope: {} }, TABLES),
    ).toThrow(/unknown table "nope"/u);
    expect(() =>
      checkedValueMaps("blocks.tasks", { items: { title: {} } }, TABLES),
    ).toThrow(/does not map values of this column/u);
    expect(() =>
      checkedValueMaps(
        "blocks.tasks",
        { items: { state: { started: [] } } },
        TABLES,
      ),
    ).toThrow(/non-empty list/u);
    expect(() =>
      checkedValueMaps(
        "blocks.tasks",
        { items: { state: { started: 1 } } },
        TABLES,
      ),
    ).toThrow(/app value/u);
  });

  it("writes, reads and compares mapped labels", () => {
    const map = {
      cancelled: "canceled",
      started: ["in_progress", "on_hold"],
      triage: null,
    };

    expect(appValues(map, "started")).toEqual(["in_progress", "on_hold"]);
    expect(appValues(map, "triage")).toEqual([]);
    expect(appValues(map, "done")).toEqual(["done"]);
    expect(writeValue(undefined, "v")).toBe("v");
    expect(writeValue(map, "v")).toBe(
      "(case v when 'cancelled' then 'canceled' when 'started' then 'in_progress' when 'triage' then better_supabase.value_unsupported('triage') else v end)",
    );
    expect(readValue(map, "x.s")).toBe(
      "(case (x.s)::text when 'canceled' then 'cancelled' when 'in_progress' then 'started' when 'on_hold' then 'started' else (x.s)::text end)",
    );
    expect(valueIn(undefined, "x.s", ["completed", "canceled"])).toBe(
      "x.s in ('completed', 'canceled')",
    );
    expect(valueIn(undefined, "x.s", ["canceled"], true)).toBe(
      "x.s <> 'canceled'",
    );
    expect(valueIn(map, "x.s", ["started"])).toBe(
      "x.s in ('in_progress', 'on_hold')",
    );
    expect(valueIn(map, "x.s", ["triage"])).toBe("false");
    expect(valueIn(map, "x.s", ["triage"], true)).toBe("true");
  });

  it("renders a tasks guard over an app table with a many-to-one state map", () => {
    const sql = render(
      {
        tasks: {
          tables: { items: "public.tasks" },
          values: {
            items: {
              state: {
                triage: null,
                backlog: "todo",
                unstarted: "todo",
                started: ["in_progress", "on_hold"],
                completed: "done",
                canceled: null,
              },
              priority: {
                "0": "none",
                "1": "urgent",
                "2": "high",
                "3": "medium",
                "4": "low",
              },
            },
          },
        },
      },
      ["subjects", "pipelines", "tasks"],
      "tasks",
    );

    expect(sql).toContain(`new."state" = 'done'`);
    expect(sql).not.toContain("in ('completed', 'canceled')");
    expect(sql).toContain(
      `better_supabase.as_column_type((case coalesce(create_work_item.attrs ->> 'priority', '0') when '0' then 'none'`,
    );
    expect(sql).toContain(
      `'state', (case (tree."state")::text when 'todo' then 'backlog'`,
    );
  });

  it("maps the pipeline status values a tasks binding writes", () => {
    const sql = render(
      {
        tasks: {
          tables: { items: "public.tasks" },
          values: {
            items: {
              state: { started: ["in_progress", "on_hold"], canceled: null },
            },
          },
        },
      },
      ["subjects", "pipelines", "tasks"],
      "pipelines",
    );

    expect(sql).toContain("when 'started' then 'in_progress'");
    expect(sql).not.toContain("when 'canceled' then 'canceled'");
  });

  it("casts mappable columns only when they have a values entry", () => {
    const base = {
      calendar: {
        tables: {
          calendars: "public.calendars",
          events: "public.events",
          attendees: "public.event_attendees",
        },
      },
    };

    const plain = render(base, ["calendar"], "calendar");

    expect(plain).not.toContain(`(null::"public"."calendars")."owner_id"`);
    expect(plain).toContain(`(null::"public"."events")."transparency"`);
    expect(plain).toContain(`(null::"public"."event_attendees")."response"`);

    const mapped = render(
      {
        calendar: {
          ...base.calendar,
          values: {
            calendars: { ownerId: {} },
            events: { status: { cancelled: "canceled" }, transparency: {} },
            attendees: { response: { "needs-action": "pending" } },
          },
        },
      },
      ["calendar"],
      "calendar",
    );

    expect(mapped).toContain(`(null::"public"."calendars")."owner_id"`);
    expect(mapped).toContain(`"status" <> 'canceled'`);
    expect(mapped).toContain(`= 'pending'`);
  });

  it("refuses values for a column the block does not map", () => {
    expect(() =>
      renderBlocks(["tags"], {
        modules: { tags: { values: { tags: { name: { a: "b" } } } } },
      }),
    ).toThrow(/blocks\.tags\.values\.tags\.name/u);
  });
});
