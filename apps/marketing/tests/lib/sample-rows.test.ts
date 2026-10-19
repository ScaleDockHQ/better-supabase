import { describe, expect, test } from "vitest";

import { DESIGN_TEMPLATES } from "../../lib/design-templates";
import {
  hiddenColumns,
  SAMPLE_ROW_COUNT,
  sampleRows,
} from "../../lib/sample-rows";

const content = DESIGN_TEMPLATES.find((each) => each.id === "content-calendar");
const events = DESIGN_TEMPLATES.find((each) => each.id === "event-planning");

describe("sample rows", () => {
  test("leaves server-only columns out for a signed-in member", () => {
    const design = {
      appTables: {
        projects: {
          columns: {
            name: { type: "text" as const },
            budget: { type: "integer" as const, access: "read" as const },
            internal_notes: {
              type: "text" as const,
              access: "server" as const,
            },
          },
        },
      },
    };

    expect(hiddenColumns(design.appTables.projects, "member")).toEqual([
      "internal_notes",
    ]);
    expect(hiddenColumns(design.appTables.projects, "server")).toEqual([]);
    expect(
      sampleRows(design, "projects", SAMPLE_ROW_COUNT, "member").columns,
    ).toEqual(["name", "budget"]);
    expect(sampleRows(design, "projects").columns).toEqual([
      "name",
      "budget",
      "internal_notes",
    ]);
  });

  test("returns nothing for a table the design doesn't have", () => {
    expect(sampleRows({}, "missing")).toEqual({ columns: [], rows: [] });
  });

  test("is deterministic and fills every column", () => {
    const design = content?.design ?? {};
    const first = sampleRows(design, "posts");

    expect(sampleRows(design, "posts")).toEqual(first);
    expect(first.rows).toHaveLength(SAMPLE_ROW_COUNT);
    expect(first.columns).toEqual([
      "channel_id",
      "title",
      "body",
      "status",
      "publish_at",
      "author_id",
      "link",
    ]);
  });

  test("uses titles, options, formats and references", () => {
    const design = content?.design ?? {};
    const [row] = sampleRows(design, "posts").rows;

    expect(row).toMatchObject({
      title: "Post 1",
      status: "idea",
      channel_id: "Channel 1",
      author_id: "Ada Lovelace",
      link: "https://example.com/link/1",
      publish_at: "2026-01-05 09:00",
    });

    const channels = sampleRows(design, "channels").rows;

    expect(channels[0]).toMatchObject({ name: "Channel 1", color: "#2563eb" });
  });

  test("leaves some optional cells empty and fills required ones", () => {
    const design = events?.design ?? {};
    const rows = sampleRows(design, "attendees").rows;

    expect(rows[3]).toMatchObject({
      email: "katherine@example.com",
      checked_in: "false",
    });

    const agenda = sampleRows(design, "agenda_items").rows;

    expect(agenda[3]?.["room"]).toBeNull();
    expect(agenda[3]?.["starts_at"]).not.toBeNull();
  });

  test("keeps numbers inside the column's bounds", () => {
    const rows = sampleRows(
      {
        appTables: {
          scores: {
            columns: {
              stars: { type: "integer", format: "rating", nullable: false },
              share: { type: "integer", format: "percent", nullable: false },
              size: { type: "integer", min: 2, max: 8, nullable: false },
              price: { type: "bigint", format: "currency", nullable: false },
              done: { type: "boolean", nullable: false },
              due: { type: "date", nullable: false },
            },
          },
        },
      },
      "scores",
    ).rows;

    const numbers = (key: string): readonly number[] =>
      rows.map((row) => Number(row[key]));

    expect(Math.min(...numbers("stars"))).toBe(1);
    expect(Math.max(...numbers("stars"))).toBe(5);
    expect(Math.max(...numbers("share"))).toBeLessThanOrEqual(100);
    expect(Math.max(...numbers("size"))).toBe(8);

    expect(rows[1]).toMatchObject({
      size: "5",
      price: "25.00",
      done: "false",
      due: "2026-01-08",
    });
  });
});
