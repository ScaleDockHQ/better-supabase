import { describe, expect, test } from "vitest";

import type { Design } from "../../src/create/index.ts";

import { SAMPLE_ROW_COUNT, sampleRows } from "../../src/create/index.ts";

const USER = {
  type: "uuid",
  references: { table: "auth.users", onDelete: "set null" },
} as const;

const content: Design = {
  appTables: {
    channels: {
      columns: {
        name: { type: "text", nullable: false },
        color: { type: "text", format: "color" },
      },
    },
    posts: {
      columns: {
        channel_id: {
          type: "uuid",
          nullable: false,
          references: { table: "channels", onDelete: "cascade" },
        },
        title: { type: "text", nullable: false },
        body: { type: "text", format: "long_text" },
        status: {
          type: "text",
          nullable: false,
          options: ["idea", "draft", "scheduled", "published"],
          default: "'idea'",
        },
        publish_at: { type: "timestamptz" },
        author_id: USER,
        link: { type: "text", format: "url" },
      },
      subject: { type: "post", title: "title" },
    },
  },
};

const events: Design = {
  appTables: {
    agenda_items: {
      columns: {
        starts_at: { type: "timestamptz", nullable: false },
        room: { type: "text" },
      },
    },
    attendees: {
      columns: {
        email: { type: "text", format: "email", nullable: false },
        checked_in: { type: "boolean", nullable: false, default: "false" },
      },
    },
  },
};

describe("sample rows", () => {
  test("returns nothing for a table the design doesn't have", () => {
    expect(sampleRows({}, "missing")).toEqual({ columns: [], rows: [] });
  });

  test("is deterministic and fills every column", () => {
    const design = content;
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
    const design = content;
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
    const design = events;
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

  test("fills phone, uuid, numeric, jsonb and array columns", () => {
    const [row] = sampleRows(
      {
        appTables: {
          misc: {
            columns: {
              phone: { type: "text", format: "phone", nullable: false },
              ref: { type: "uuid", nullable: false },
              amount: { type: "numeric", nullable: false },
              meta: { type: "jsonb", nullable: false },
              tags: { type: "text[]", nullable: false },
            },
          },
        },
      },
      "misc",
    ).rows;

    expect(row).toMatchObject({
      phone: "+1 555 0110",
      ref: "00000000-0000-4000-8000-000000000001",
      amount: "0.00",
      meta: "{}",
      tags: "{}",
    });
  });
});
