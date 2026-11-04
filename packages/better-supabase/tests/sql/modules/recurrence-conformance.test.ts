import { describe, expect, it } from "vitest";

import { rruleOccurrences } from "../../../src/core/recurrence.ts";
import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

interface Case {
  readonly label: string;
  readonly rule: string;
  readonly dtstart: string;
  readonly tz: string;
  readonly from: string;
  readonly until: string;
}

const CASES: readonly Case[] = [
  {
    label: "weekly across the spring DST change",
    rule: "FREQ=WEEKLY;BYDAY=MO,WE;COUNT=12",
    dtstart: "2026-03-02T08:30:00Z",
    tz: "Europe/Amsterdam",
    from: "2026-03-01T00:00:00Z",
    until: "2026-05-01T00:00:00Z",
  },
  {
    label: "monthly on the last Friday",
    rule: "FREQ=MONTHLY;BYDAY=-1FR",
    dtstart: "2026-01-30T17:00:00Z",
    tz: "America/New_York",
    from: "2026-01-01T00:00:00Z",
    until: "2026-12-31T00:00:00Z",
  },
  {
    label: "daily with an interval and UNTIL",
    rule: "FREQ=DAILY;INTERVAL=3;UNTIL=20260320T000000Z",
    dtstart: "2026-03-01T12:00:00Z",
    tz: "UTC",
    from: "2026-03-05T00:00:00Z",
    until: "2026-04-01T00:00:00Z",
  },
];

const RANGE_START = (item: Case): string => item.from;

function checkFor(item: Case, expected: readonly string[]): string {
  const list = expected.map((value) => `'${value}'::timestamptz`).join(", ");

  return `
  if coalesce((select array_agg(o order by o) from better_supabase.rrule_occurrences('${item.rule}', '${item.dtstart}'::timestamptz, '${item.tz}', tstzrange('${RANGE_START(item)}'::timestamptz, '${item.until}'::timestamptz, '[)')) o), array[]::timestamptz[]) is distinct from array[${list}]::timestamptz[] then
    raise exception '${item.label}: %', (select array_agg(o order by o) from better_supabase.rrule_occurrences('${item.rule}', '${item.dtstart}'::timestamptz, '${item.tz}', tstzrange('${RANGE_START(item)}'::timestamptz, '${item.until}'::timestamptz, '[)')) o);
  end if;`;
}

describe("rrule_occurrences", () => {
  it("returns the instants the TypeScript expander returns", () => {
    for (const item of CASES) {
      const found = rruleOccurrences({
        rule: item.rule,
        dtstart: Temporal.Instant.from(item.dtstart),
        tz: item.tz,
        from: Temporal.Instant.from(item.from),
        until: Temporal.Instant.from(item.until),
      });

      expect(found.length).toBeGreaterThan(0);
    }
  });

  it(
    "matches the TypeScript expander in Postgres",
    { timeout: 60_000 },
    async () => {
      const checks = CASES.map((item) =>
        checkFor(
          item,
          rruleOccurrences({
            rule: item.rule,
            dtstart: Temporal.Instant.from(item.dtstart),
            tz: item.tz,
            from: Temporal.Instant.from(item.from),
            until: Temporal.Instant.from(item.until),
          }).map((instant) => instant.toString()),
        ),
      ).join("\n");

      const files = renderBlocks(["recurrence"], {});

      await using stack = await liteStack({
        driver: "pglite",
        migrations: [
          "create schema if not exists better_supabase;",
          ...files
            .filter((file) => file.kind === "schema")
            .map((file) => file.contents),
        ],
        seed: [`do $$\nbegin${checks}\nend;\n$$;`],
      });

      expect(stack.url).not.toBe("");
    },
  );
});
