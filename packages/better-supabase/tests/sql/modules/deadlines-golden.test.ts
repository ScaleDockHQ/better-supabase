import { describe, expect, it } from "vitest";

import type { DeadlineCount } from "../../../src/sql/modules/deadlines-values.ts";

import {
  deadlineAdd,
  deadlineIsHoliday,
  evaluateVersion,
} from "../../../src/sql/modules/deadlines-evaluate.ts";
import { evaluatorSql } from "../../../src/sql/modules/deadlines-evaluator.ts";
import { validateRuleVersion } from "../../../src/sql/modules/deadlines-validate.ts";
import { validatorSql } from "../../../src/sql/modules/deadlines-validator.ts";
import { triggerGrant, userGrant } from "../../../src/sql/shared.ts";
import { liteStack } from "../../../src/testing/lite.ts";
import { contentOf, GOLDEN } from "../../fixtures/deadlines.ts";

/** Lite migrates and seeds PGlite in process; the grids take a while. */
const BOOT = { timeout: 240_000 };

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon;
  end if;
end;
$$;
create schema if not exists deadlines_golden;
`;

const fn = (name: string): string => `deadlines_golden.${name}`;

const literal = (value: unknown): string =>
  `'${JSON.stringify(value ?? null).replaceAll("'", "''")}'::jsonb`;

const text = (value: string | undefined): string =>
  value === undefined ? "null::text" : `'${value.replaceAll("'", "''")}'`;

/** A DO block that raises with the label and the SQL value unless it matches. */
function check(label: string, actual: string, expected: string): string {
  return `if (${actual}) is distinct from (${expected}) then
    raise exception 'mismatch in %: %', ${text(label)}, (${actual});
  end if;`;
}

async function run(checks: readonly string[]): Promise<void> {
  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      evaluatorSql(fn, userGrant, triggerGrant),
      validatorSql(fn, userGrant, triggerGrant),
    ],
    seed: [`do $$\nbegin\n  ${checks.join("\n  ")}\nend;\n$$;`],
  });

  expect(stack.url).not.toBe("");
}

const az = GOLDEN.find((fixture) => fixture.name === "az")?.content.counting;

const days = (year: number): string[] =>
  Array.from({ length: 366 }, (_, index) =>
    new Date(Date.UTC(year, 0, 1 + index)).toISOString().slice(0, 10),
  ).filter((day) => day.startsWith(String(year)));

const COUNTS: readonly DeadlineCount[] = [
  { from: "x", n: 0, unit: "days" },
  { from: "x", n: 45, unit: "days" },
  { from: "x", n: 1, unit: "months" },
  { from: "x", n: 13, unit: "months" },
  { from: "x", n: 3, unit: "months", day_of_month: 15 },
  { from: "x", n: 1, unit: "months", day_of_month: 28 },
  { from: "x", n: 5, unit: "business_days" },
  { from: "x", n: 20, unit: "business_days" },
  { before: "x", n: 10, unit: "days" },
  { before: "x", n: 2, unit: "months" },
  { before: "x", n: 3, unit: "business_days" },
  { before: "x" },
];

const ANCHORS = Array.from({ length: 30 }, (_, index) =>
  new Date(Date.UTC(2026, 0, 29 + index * 13)).toISOString().slice(0, 10),
);

/** Contents that are not valid, each with problems at several levels. */
const INVALID: readonly unknown[] = [
  null,
  [],
  {},
  { rules: [], groups: [] },
  {
    rules: [
      "x",
      { key: "A", group: "missing", citation: {} },
      {
        key: "a",
        group: "g",
        title: 5,
        status: "maybe",
        adjust: "sideways",
        required: "yes",
        citation: { reference: " " },
        applies: {
          Bad: ["x"],
          tier: [],
          one: "present",
          two: ["a", "a"],
          start: { from: "2026-02-30" },
          end: { before: "2026-01-01", after: "x" },
        },
        deadline: {
          first_of: [
            { from: "x", n: 1, unit: "days", each: "furnishing_month" },
          ],
        },
        exceptions: [
          1,
          {
            name: "e",
            when: {},
            unless: { x: "" },
            result: "x",
            remedy: 3,
            note: "n",
            status: "x",
            citation: {},
          },
          {
            name: "e",
            when: { x: true },
            result: "barred",
            citation: { reference: "r" },
          },
        ],
        meta: [],
      },
      {
        key: "a",
        group: "g",
        citation: { reference: "r" },
        deadline: {
          from: "x",
          before: "y",
          n: -1,
          unit: "weeks",
          day_of_month: 30,
          each: "year",
        },
      },
      {
        key: "b",
        group: "g",
        citation: { reference: "r" },
        deadline: {
          first_of: [{ from: "x", n: 1, unit: "days" }, 4],
          extra: 1,
        },
      },
      {
        key: "c",
        group: "g",
        citation: { reference: "r" },
        deadline: {
          later_of: [
            { from: "x", n: 1 },
            { before: "x", each: "furnishing_month" },
          ],
        },
      },
      {
        key: "d",
        group: "g",
        citation: { reference: "r" },
        deadline: { from: "x", unit: "days" },
        exceptions: {},
      },
      {
        key: "e",
        group: "g",
        citation: { reference: "r" },
        deadline: 4,
        applies: [],
      },
    ],
    groups: [
      5,
      { key: "g", citation: { reference: "r" }, requires: ["h"] },
      { key: "g", title: "x".repeat(201), citation: {}, meta: "x" },
      { key: "h", citation: { reference: "r" }, requires: ["i"] },
      { key: "i", citation: { reference: "r" }, requires: ["g"] },
      { key: "j", citation: { reference: "r" }, requires: ["j", "zz"] },
      { key: "Bad", citation: { reference: "r" } },
    ],
    counting: {
      roll_to: "x",
      roll_when: ["sunday", "sunday"],
      holidays: [
        "x",
        { name: "", date: { month: 13, day: 1 }, citation: {} },
        {
          name: "a",
          date: { month: 1, weekday: "funday", nth: 6 },
          citation: { reference: "r" },
          observed: [
            { falls_on: "x" },
            {
              falls_on: "sunday",
              observe: "following_monday",
              citation: { reference: "r" },
            },
          ],
        },
        {
          name: "b",
          date: { month: 1, day: 1 },
          citation: { reference: "r" },
          observed: {},
        },
      ],
      citation: {},
      status: "x",
    },
    meta: { big: "x".repeat(40_000) },
  },
  {
    rules: [{ key: "a", group: "g", citation: { reference: "r" } }],
    groups: [{ key: "g", citation: { reference: "r" } }],
    counting: { roll_to: "next_business_day", roll_when: [], holidays: 1 },
  },
  {
    rules: [{ key: "a", group: "g", citation: { reference: "r" } }],
    groups: [{ key: "g", citation: { reference: "r" } }],
    counting: [],
  },
];

describe("deadline evaluation in Postgres", BOOT, () => {
  it("gives every golden case the expected results, as the TypeScript evaluator does", async () => {
    const checks = GOLDEN.flatMap((fixture) =>
      fixture.cases.map((test) => {
        const content = contentOf(fixture, test);
        const ts = evaluateVersion(content, test.facts, test.asOf, test.group);

        expect(JSON.parse(JSON.stringify(ts))).toEqual(test.expect);

        return check(
          `${fixture.name}: ${test.name}`,
          `${fn("evaluate_deadlines")}(${literal(content)}, ${literal(test.facts)}, '${test.asOf}', ${text(test.group)})`,
          literal(test.expect),
        );
      }),
    );

    await expect(run(checks)).resolves.toBeUndefined();
  });

  it("finds the same holidays and counts the same dates as the TypeScript twins", async () => {
    const holidays = [...days(2026), ...days(2027), ...days(2028)].filter(
      (day) => deadlineIsHoliday(az ?? undefined, day),
    );

    const calendar = GOLDEN.find((fixture) => fixture.name === "calendar");

    const truths = (calendar?.holidays ?? []).map((entry) => {
      expect([
        entry.date,
        deadlineIsHoliday(az ?? undefined, entry.date),
      ]).toEqual([entry.date, entry.holiday]);

      return check(
        `holiday ${entry.date}`,
        `${fn("deadline_is_holiday")}(${literal(az)}, '${entry.date}')`,
        String(entry.holiday),
      );
    });

    const adds = ANCHORS.flatMap((anchor) =>
      COUNTS.map((count) =>
        check(
          `add ${anchor} ${JSON.stringify(count)}`,
          `${fn("deadline_add")}('${anchor}', ${literal(count)}, ${literal(az)})`,
          `'${deadlineAdd(anchor, count, az)}'::date`,
        ),
      ),
    );

    await expect(
      run([
        check(
          "holidays 2026 to 2028",
          `array(select d::date from generate_series('2026-01-01'::date, '2028-12-31'::date, interval '1 day') d where ${fn("deadline_is_holiday")}(${literal(az)}, d::date) order by d)`,
          `array[${holidays.map((day) => `'${day}'::date`).join(", ")}]`,
        ),
        ...truths,
        ...adds,
      ]),
    ).resolves.toBeUndefined();
  });

  it("finds the same problems in invalid content, in the same order", async () => {
    const checks = INVALID.map((content, index) => {
      const issues = validateRuleVersion(content);

      expect(issues.length).toBeGreaterThan(0);

      return check(
        `invalid ${index + 1}`,
        `${fn("validate_deadline_rules")}(${literal(content)})`,
        issues.length === 0
          ? "'{}'::text[]"
          : `array[${issues.map((issue) => text(issue)).join(", ")}]`,
      );
    });

    await expect(run(checks)).resolves.toBeUndefined();
  });
});
