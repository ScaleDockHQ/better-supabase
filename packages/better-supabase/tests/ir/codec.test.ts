import { describe, expect, it } from "vitest";

import type { Include, Selection } from "../../src/ir/types.ts";
import type { Codec } from "../../src/schema/types.ts";

import { DbException } from "../../src/core/errors.ts";
import { decodeRows, needsDecoding } from "../../src/ir/codec.ts";
import { encodeValue } from "../../src/ir/wire.ts";
import { schema } from "../fixtures/generated-camel.ts";

const customers = schema.meta.tables["customers"];
const notes = schema.meta.tables["notes"];
const notesRelation = customers?.relations["notes"];
if (!customers || !notes || !notesRelation)
  throw new Error("Fixture tables missing");

function include(overrides: Partial<Include>): Include {
  if (!notes || !notesRelation) throw new Error("Fixture tables missing");
  return {
    alias: "notes",
    relation: notesRelation,
    target: notes,
    selection: { columns: [], includes: [] },
    where: undefined,
    orderBy: [],
    limit: undefined,
    required: false,
    ...overrides,
  };
}

describe("encodeValue", () => {
  it.each<[string, unknown, unknown]>([
    [
      "an Instant",
      Temporal.Instant.from("2026-01-02T00:00:00Z"),
      "2026-01-02T00:00:00Z",
    ],
    [
      "a ZonedDateTime, as its instant",
      Temporal.ZonedDateTime.from(
        "2026-01-02T01:00:00+01:00[Europe/Amsterdam]",
      ),
      "2026-01-02T00:00:00Z",
    ],
    [
      "a PlainDateTime",
      Temporal.PlainDateTime.from("2026-01-02T10:30:00"),
      "2026-01-02T10:30:00",
    ],
    ["a PlainDate", Temporal.PlainDate.from("2026-01-02"), "2026-01-02"],
    ["a PlainTime", Temporal.PlainTime.from("10:30"), "10:30:00"],
    ["a bigint", 9007199254740993n, "9007199254740993"],
    [
      "an array of both",
      [1n, [Temporal.Instant.fromEpochMilliseconds(0)]],
      ["1", ["1970-01-01T00:00:00Z"]],
    ],
    ["a string", "x", "x"],
    ["null", null, null],
  ])("encodes %s", (_name, value, expected) => {
    expect(encodeValue(value)).toEqual(expected);
  });

  it("passes objects through", () => {
    const value = { a: 1 };
    expect(encodeValue(value)).toBe(value);
  });
});

describe("Temporal equality in tests", () => {
  it("tells different instants apart", () => {
    expect(Temporal.Instant.fromEpochMilliseconds(0)).not.toEqual(
      Temporal.Instant.fromEpochMilliseconds(1),
    );
  });
});

describe("needsDecoding", () => {
  it.each<[string, Selection, boolean]>([
    [
      "plain columns",
      { columns: [{ alias: "id", column: "id" }], includes: [] },
      false,
    ],
    [
      "a codec column",
      {
        columns: [
          { alias: "at", column: "at", cast: "text", codec: "instant" },
        ],
        includes: [],
      },
      true,
    ],
    [
      "an aggregate",
      { columns: [], includes: [], aggregate: { count: true, measures: [] } },
      true,
    ],
    [
      "a count include",
      { columns: [], includes: [include({ count: "notes" })] },
      true,
    ],
    [
      "an aggregate include",
      {
        columns: [],
        includes: [include({ aggregate: { fn: "sum", name: "notes" } })],
      },
      true,
    ],
    ["a plain include", { columns: [], includes: [include({})] }, false],
    [
      "a nested codec",
      {
        columns: [],
        includes: [
          include({
            selection: {
              columns: [{ alias: "id", column: "id", codec: "bigint" }],
              includes: [],
            },
          }),
        ],
      },
      true,
    ],
  ])("%s", (_name, selection, expected) => {
    expect(needsDecoding(selection)).toBe(expected);
  });
});

describe("decodeRows", () => {
  it("returns the same rows without a selection or codecs", () => {
    const rows = [{ id: "a" }];
    expect(decodeRows(undefined, rows)).toBe(rows);
    expect(
      decodeRows(
        { columns: [{ alias: "id", column: "id" }], includes: [] },
        rows,
      ),
    ).toBe(rows);
  });

  it("applies column codecs to scalars, arrays and nulls", () => {
    const selection: Selection = {
      columns: [
        { alias: "at", column: "at", cast: "text", codec: "instant" },
        {
          alias: "local",
          column: "local",
          cast: "text",
          codec: "plainDateTime",
        },
        { alias: "big", column: "big", cast: "text", codec: "bigint" },
        { alias: "exact", column: "exact", cast: "text", codec: "string" },
        { alias: "days", column: "days", cast: "text", codec: "instant" },
        { alias: "gone", column: "gone", cast: "text", codec: "instant" },
        { alias: "absent", column: "absent", codec: "bigint" },
      ],
      includes: [],
    };
    expect(
      decodeRows(selection, [
        {
          at: "2026-01-02 01:00:00.123456+01",
          local: "2026-01-02 10:30:00",
          big: "9007199254740993",
          exact: 1.5,
          days: ["1970-01-01 00:00:00+00", null],
          gone: null,
        },
      ]),
    ).toEqual([
      {
        at: Temporal.Instant.from("2026-01-02T00:00:00.123456Z"),
        local: Temporal.PlainDateTime.from("2026-01-02T10:30:00"),
        big: 9007199254740993n,
        exact: "1.5",
        days: [Temporal.Instant.fromEpochMilliseconds(0), null],
        gone: null,
      },
    ]);
  });

  it.each<[string, Codec, unknown]>([
    ["infinity", "instant", "infinity"],
    ["-infinity", "plainDateTime", "-infinity"],
    ["infinity in an array", "instant", ["1970-01-01 00:00:00+00", "infinity"]],
  ])("rejects %s with an invalid_value error", (_name, codec, value) => {
    const selection: Selection = {
      columns: [{ alias: "at", column: "at", cast: "text", codec }],
      includes: [],
    };
    let thrown: unknown;
    try {
      decodeRows(selection, [{ at: value }]);
    } catch (cause) {
      thrown = cause;
    }
    expect(thrown).toBeInstanceOf(DbException);
    expect(thrown instanceof DbException && thrown.error).toMatchObject({
      kind: "invalid_value",
      column: "at",
      status: 500,
    });
  });

  it("folds aggregate counts and measures", () => {
    const selection: Selection = {
      columns: [{ alias: "status", column: "status" }],
      includes: [],
      aggregate: {
        count: true,
        measures: [
          {
            fn: "sum",
            key: "_sum_id",
            alias: "id",
            column: "id",
            cast: "text",
            codec: "bigint",
          },
          { fn: "avg", key: "_avg_id", alias: "id", column: "id" },
          {
            fn: "max",
            key: "_max_at",
            alias: "at",
            column: "at",
            cast: "text",
            codec: "instant",
          },
        ],
      },
    };
    expect(
      decodeRows(selection, [
        {
          status: "lead",
          _count: [{ count: 3 }],
          _sum_id: "12",
          _avg_id: 4,
          _max_at: null,
        },
        { status: "active", _count: 2, _sum_id: undefined, _avg_id: null },
        { status: "x", _count: [] },
        { status: "y" },
      ]),
    ).toEqual([
      {
        status: "lead",
        _count: 3,
        _sum: { id: 12n },
        _avg: { id: 4 },
        _max: { at: null },
      },
      {
        status: "active",
        _count: 2,
        _sum: { id: null },
        _avg: { id: null },
        _max: { at: null },
      },
      {
        status: "x",
        _count: 0,
        _sum: { id: null },
        _avg: { id: null },
        _max: { at: null },
      },
      {
        status: "y",
        _count: 0,
        _sum: { id: null },
        _avg: { id: null },
        _max: { at: null },
      },
    ]);
  });

  it("folds count includes from PostgREST lists and SQL numbers", () => {
    const selection: Selection = {
      columns: [],
      includes: [
        include({ alias: "_count_notes", count: "notes" }),
        include({ alias: "_count_locations", count: "locations" }),
      ],
    };
    expect(
      decodeRows(selection, [
        { _count_notes: [{ count: 3 }], _count_locations: 1 },
        { _count_notes: [{}] },
      ]),
    ).toEqual([
      { _count: { notes: 3, locations: 1 } },
      { _count: { notes: 0 } },
    ]);
  });

  it("folds aggregate includes from a list, an object, null or nothing", () => {
    const selection: Selection = {
      columns: [],
      includes: [
        include({
          alias: "_sum_notes",
          aggregate: { fn: "sum", name: "notes" },
          selection: {
            columns: [],
            includes: [],
            aggregate: {
              count: false,
              measures: [
                {
                  fn: "sum",
                  key: "id",
                  alias: "id",
                  column: "id",
                  cast: "text",
                  codec: "bigint",
                },
              ],
            },
          },
        }),
      ],
    };
    expect(
      decodeRows(selection, [
        { _sum_notes: [{ id: "7" }] },
        { _sum_notes: { id: "8" } },
        { _sum_notes: null },
        {},
      ]),
    ).toEqual([
      { _sum: { notes: { id: 7n } } },
      { _sum: { notes: { id: 8n } } },
      { _sum: { notes: { id: null } } },
      {},
    ]);
  });

  it("decodes embedded rows in lists and objects", () => {
    const inner: Selection = {
      columns: [{ alias: "id", column: "id", cast: "text", codec: "bigint" }],
      includes: [],
    };
    const selection: Selection = {
      columns: [],
      includes: [
        include({ selection: inner }),
        include({ alias: "first", selection: inner }),
      ],
    };
    expect(
      decodeRows(selection, [
        { notes: [{ id: "1" }, { id: "2" }], first: { id: "1" } },
        { notes: [], first: null },
      ]),
    ).toEqual([
      { notes: [{ id: 1n }, { id: 2n }], first: { id: 1n } },
      { notes: [], first: null },
    ]);
  });
});
