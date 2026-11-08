import { describe, expect, it } from "vitest";

import type {
  FilterFieldInfo,
  FilterNode,
  FilterQuery,
} from "../../src/list/filter-query.ts";

import {
  dateBounds,
  decodeFilterQuery,
  encodeFilterQuery,
  filterWhere,
} from "../../src/list/filter-query.ts";

const NOW = Temporal.Instant.from("2026-03-15T22:30:00Z");

function field(
  type: FilterFieldInfo["type"],
  columnType: string,
  nullable = false,
): FilterFieldInfo {
  return {
    id: "when",
    type,
    column: "when",
    columnMeta: { type: columnType, nullable, db: "when" },
    label: "When",
    operators: [],
  };
}

const rule = (
  operator: string,
  value?: unknown,
  negated?: boolean,
  path: string[] = ["when"],
): FilterNode => ({
  id: operator,
  type: "rule",
  path,
  operator,
  value,
  ...(negated === undefined ? {} : { negated }),
});

const group = (
  combinator: "and" | "or",
  ...rules: FilterNode[]
): FilterQuery => ({ id: "root", type: "group", combinator, rules });

describe("dateBounds", () => {
  it("resolves a day for a date column", () => {
    expect(
      dateBounds(field("date", "date"), { date: "2026-01-31" }, {}),
    ).toEqual({ start: "2026-01-31", end: "2026-02-01" });
  });

  it.each([
    ["day", 2, "2026-03-17"],
    ["week", -1, "2026-03-08"],
    ["month", 1, "2026-04-15"],
    ["year", 1, "2027-03-15"],
  ] as const)("shifts relative %s values", (unit, offset, expected) => {
    expect(
      dateBounds(
        field("date", "date"),
        { relative: { unit, offset } },
        { now: NOW },
      ).start,
    ).toBe(expected);
  });

  it("resolves relative days in the clock's zone", () => {
    const relative = { unit: "day", offset: 0 } as const;

    expect(
      dateBounds(field("date", "date"), { relative }, { now: NOW }).start,
    ).toBe("2026-03-15");
    expect(
      dateBounds(
        field("date", "date"),
        { relative },
        { now: NOW, timeZone: "Asia/Tokyo" },
      ).start,
    ).toBe("2026-03-16");
  });

  it("uses the current instant when the clock has none", () => {
    const bounds = dateBounds(
      field("date", "date"),
      { relative: { unit: "day", offset: 0 } },
      {},
    );

    expect(bounds.end > bounds.start).toBe(true);
  });

  it("returns local timestamps for timestamp columns", () => {
    expect(
      dateBounds(field("date", "timestamp"), { date: "2026-03-15" }, {}),
    ).toEqual({ start: "2026-03-15T00:00:00", end: "2026-03-16T00:00:00" });
    expect(
      dateBounds(
        field("date", "timestamp"),
        { date: "2026-03-15", time: "09:30" },
        {},
      ),
    ).toEqual({ start: "2026-03-15T09:30:00", end: "2026-03-15T09:31:00" });
  });

  it("returns instants for timestamptz columns", () => {
    expect(
      dateBounds(
        field("date", "timestamptz"),
        { date: "2026-03-15" },
        { timeZone: "Europe/Amsterdam" },
      ),
    ).toEqual({ start: "2026-03-14T23:00:00Z", end: "2026-03-15T23:00:00Z" });
    expect(
      dateBounds(
        field("date", "timestamptz"),
        { date: "2026-03-15", time: "12:00" },
        {},
      ).end,
    ).toBe("2026-03-15T12:01:00Z");
  });
});

describe("filterWhere dates", () => {
  const day = { date: "2026-03-15" };
  const tz = field("date", "timestamptz");
  const start = "2026-03-15T00:00:00Z";
  const end = "2026-03-16T00:00:00Z";

  it.each([
    ["is", { when: { gte: start, lt: end } }],
    ["is_before", { when: { lt: start } }],
    ["is_after", { when: { gte: end } }],
    ["is_on_or_before", { when: { lt: end } }],
    ["is_on_or_after", { when: { gte: start } }],
  ])("compiles %s", (operator, expected) => {
    expect(filterWhere(group("and", rule(operator, day)), [tz])).toEqual(
      expected,
    );
  });

  it("compiles a date range and rejects unknown date operators", () => {
    expect(
      filterWhere(
        group("and", rule("between", [day, { date: "2026-03-17" }])),
        [tz],
      ),
    ).toEqual({ when: { gte: start, lt: "2026-03-18T00:00:00Z" } });

    expect(() =>
      filterWhere(group("and", rule("sideways", day)), [tz]),
    ).toThrow('Unknown date operator "sideways"');
  });

  it("negates, keeping rows without a value for nullable columns", () => {
    const nullable = field("date", "timestamptz", true);
    const query = group("and", rule("is_not", day));

    expect(filterWhere(query, [tz])).toEqual({
      NOT: { when: { gte: start, lt: end } },
    });
    expect(filterWhere(query, [nullable])).toEqual({
      OR: [
        { NOT: { when: { gte: start, lt: end } } },
        { when: { isNull: true } },
      ],
    });
    expect(
      filterWhere(group("and", rule("empty", undefined, true)), [nullable]),
    ).toEqual({ NOT: { when: { isNull: true } } });
  });

  it("combines groups and skips unknown or empty rules", () => {
    const text = { ...field("text", "text"), id: "other", column: "other" };
    const unknown = rule("eq", 1, false, ["nope"]);

    expect(filterWhere(group("and", rule(""), unknown), [tz])).toBeUndefined();

    expect(
      filterWhere(group("or", rule("is", day), rule("is_before", day)), [tz]),
    ).toEqual({
      OR: [{ when: { gte: start, lt: end } }, { when: { lt: start } }],
    });
    expect(
      filterWhere(group("and", rule("is", day), rule("is_after", day)), [tz]),
    ).toEqual({
      AND: [{ when: { gte: start, lt: end } }, { when: { gte: end } }],
    });
    expect(
      filterWhere(group("and", rule("empty", undefined, false, ["other"])), [
        text,
      ]),
    ).toEqual({ OR: [{ other: { isNull: true } }, { other: { eq: "" } }] });
  });
});

describe("filter query encoding", () => {
  it("round trips unicode and rejects malformed input", () => {
    const query = group("and", rule("eq", "héllo ✓"));

    expect(decodeFilterQuery(encodeFilterQuery(query))).toEqual(query);
    expect(decodeFilterQuery("not base64!")).toBeUndefined();
    expect(decodeFilterQuery("bm90IGpzb24")).toBeUndefined();
    expect(decodeFilterQuery("_w")).toBeUndefined();
  });
});
