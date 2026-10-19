import type { SQLInputValue } from "node:sqlite";

import { describe, expect, it } from "vitest";

import type { SelectOp } from "../../src/ir/types.ts";
import type {
  FilterQuery,
  FilterRecordField,
  FilterRule,
} from "../../src/list/index.ts";
import type { TableMeta } from "../../src/schema/types.ts";

import { compileSqlite } from "../../src/compile/sqlite.ts";
import { builderFor } from "../../src/ir/build.ts";
import { filterFieldsOf, filterWhere } from "../../src/list/filter-query.ts";
import { evaluateFilterQuery } from "../../src/list/index.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { createSqlite } from "../fixtures/sqlite.ts";

const customers: TableMeta = schema.meta.tables["customers"]!;

const fields = filterFieldsOf(customers, {
  name: { type: "text" },
  kvk: { type: "text" },
  status: { type: "select" },
  archivedAt: { type: "date" },
  createdAt: { type: "date" },
  contact: { type: "relation", column: "primaryContactId" },
});

const now = Temporal.Instant.from("2026-10-13T22:30:00Z");
const clock = { now, timeZone: "Europe/Amsterdam" };

const ORG = "00000000-0000-4000-8000-000000000001";
const CONTACT = "00000000-0000-4000-8000-0000000000c1";

const rows = [
  {
    id: "00000000-0000-4000-8000-000000000101",
    name: "Acme Holding",
    kvk: "1001",
    status: "active",
    primaryContactId: CONTACT,
    archivedAt: null,
    createdAt: "2026-10-13T08:00:00Z",
  },
  {
    id: "00000000-0000-4000-8000-000000000102",
    name: "Bolt BV",
    kvk: null,
    status: "lead",
    primaryContactId: null,
    archivedAt: "2026-10-01T12:00:00Z",
    createdAt: "2026-09-20T08:00:00Z",
  },
  {
    id: "00000000-0000-4000-8000-000000000103",
    name: "acme labs",
    kvk: "",
    status: "archived",
    primaryContactId: null,
    archivedAt: "2026-10-12T23:30:00Z",
    createdAt: "2026-10-12T21:00:00Z",
  },
  {
    id: "00000000-0000-4000-8000-000000000104",
    name: "Zeta",
    kvk: "2002",
    status: "active",
    primaryContactId: CONTACT,
    archivedAt: null,
    createdAt: "2025-12-31T23:30:00Z",
  },
] as const;

const { sqlite } = createSqlite(schema.meta);

const insert = sqlite.prepare(
  `insert into "customers" (id, organization_id, name, kvk, status, primary_contact_id, archived_at, created_at, updated_at, metadata)
   values (?, ?, ?, ?, ?, ?, ?, ?, ?, '{}')`,
);

for (const row of rows) {
  insert.run(
    row.id,
    ORG,
    row.name,
    row.kvk,
    row.status,
    row.primaryContactId,
    row.archivedAt,
    row.createdAt,
    row.createdAt,
  );
}

function selectOf(where: unknown): SelectOp {
  return {
    kind: "select",
    table: customers,
    selection: { columns: [{ alias: "id", column: "id" }], includes: [] },
    where: builderFor(schema.meta).where(customers, where),
    orderBy: [],
    limit: undefined,
    offset: undefined,
    count: undefined,
    head: false,
    single: undefined,
  };
}

/** The ids `filterWhere` selects, run through SQLite. */
function selected(query: FilterQuery): string[] {
  const where = filterWhere(query, fields, clock);
  const plan = compileSqlite(selectOf(where ?? {}));

  if (plan.kind !== "select" || plan.rows === undefined) {
    throw new Error("Expected a select");
  }

  // SAFETY: the compiler binds only SqliteValue parameters; rows are plain objects.
  const found = sqlite
    .prepare(plan.rows.text)
    .all(...(plan.rows.params as SQLInputValue[])) as { id: string }[];

  return found.map((row) => row.id).toSorted();
}

/** The ids `evaluateFilterQuery` matches. */
function evaluated(query: FilterQuery): string[] {
  return rows
    .filter((row) => evaluateFilterQuery(query, row, fields, clock).matched)
    .map((row) => row.id)
    .toSorted();
}

let ids = 0;

function rule(
  path: string,
  operator: string,
  value?: unknown,
  negated?: boolean,
): FilterRule {
  ids += 1;

  return {
    id: `r${String(ids)}`,
    type: "rule",
    path: [path],
    operator,
    ...(value === undefined ? {} : { value }),
    ...(negated === undefined ? {} : { negated }),
  };
}

function group(
  rules: FilterQuery["rules"],
  combinator: "and" | "or" = "and",
): FilterQuery {
  ids += 1;

  return { id: `g${String(ids)}`, type: "group", combinator, rules };
}

const day = (date: string) => ({ date });

describe("evaluateFilterQuery", () => {
  const cases: readonly (readonly [string, FilterQuery])[] = [
    ["contains, case-insensitive", group([rule("name", "contains", "ACME")])],
    ["not_contains", group([rule("name", "not_contains", "acme")])],
    ["starts_with", group([rule("name", "starts_with", "ac")])],
    ["ends_with", group([rule("name", "ends_with", "BV")])],
    ["text is", group([rule("kvk", "is", "1001")])],
    [
      "text is_not on a nullable column",
      group([rule("kvk", "is_not", "1001")]),
    ],
    ["text empty", group([rule("kvk", "empty")])],
    ["text not_empty", group([rule("kvk", "not_empty")])],
    [
      "select is_any_of",
      group([rule("status", "is_any_of", ["lead", "active"])]),
    ],
    ["select is_none_of", group([rule("status", "is_none_of", ["active"])])],
    ["relation is", group([rule("contact", "is", CONTACT)])],
    ["relation is_not", group([rule("contact", "is_not", CONTACT)])],
    ["relation empty", group([rule("contact", "empty")])],
    ["negated flag", group([rule("status", "is", "active", true)])],
    [
      "date is today",
      group([
        rule("createdAt", "is", { relative: { unit: "day", offset: 0 } }),
      ]),
    ],
    [
      "date is_before",
      group([rule("createdAt", "is_before", day("2026-10-01"))]),
    ],
    [
      "date is_after",
      group([rule("createdAt", "is_after", day("2026-10-12"))]),
    ],
    [
      "date is_on_or_before",
      group([rule("archivedAt", "is_on_or_before", day("2026-10-13"))]),
    ],
    [
      "date is_on_or_after",
      group([rule("createdAt", "is_on_or_after", day("2026-10-13"))]),
    ],
    [
      "date between",
      group([
        rule("createdAt", "between", [day("2026-01-01"), day("2026-10-12")]),
      ]),
    ],
    [
      "date not_between",
      group([
        rule("archivedAt", "not_between", [
          day("2026-10-01"),
          day("2026-10-02"),
        ]),
      ]),
    ],
    ["date is_not", group([rule("archivedAt", "is_not", day("2026-10-13"))])],
    [
      "nested groups",
      group([
        rule("status", "is_not", "archived"),
        group(
          [rule("name", "starts_with", "acme"), rule("kvk", "empty")],
          "or",
        ),
      ]),
    ],
    [
      "or at the root",
      group([rule("kvk", "is", "2002"), rule("name", "ends_with", "bv")], "or"),
    ],
    [
      "an unfinished rule",
      group([rule("name", ""), rule("status", "is", "lead")]),
    ],
    ["nothing left", group([rule("name", "")])],
  ];

  it.each(cases)("selects the same records as filterWhere: %s", (_, query) => {
    expect(evaluated(query)).toEqual(selected(query));
  });

  it("reports each node's result and treats a missing value as unknown", () => {
    const tree = group([
      rule("kvk", "contains", "1"),
      rule("status", "is", "lead"),
    ]);

    const [kvkRule, statusRule] = tree.rules;
    const result = evaluateFilterQuery(tree, rows[1], fields, clock);

    expect(result.matched).toBe(false);
    expect(result.results[kvkRule!.id]).toBeNull();
    expect(result.results[statusRule!.id]).toBe(true);
    expect(result.results[tree.id]).toBeNull();
  });

  it("reads dotted columns on nested records and numbers given as text", () => {
    const nested: readonly FilterRecordField[] = [
      {
        id: "submitter.seniority",
        type: "select",
        column: "submitter.seniority",
        columnMeta: { type: "text", nullable: true },
      },
      {
        id: "amount",
        type: "number",
        column: "amount",
        columnMeta: { type: "int8", nullable: false },
      },
      {
        id: "tags",
        type: "multiselect",
        column: "tags",
        columnMeta: { type: "text", nullable: true },
      },
    ];

    const expense = {
      submitter: { seniority: "manager" },
      amount: "12500",
      tags: ["travel", "food"],
    };

    const tree: FilterQuery = {
      id: "root",
      type: "group",
      combinator: "and",
      rules: [
        {
          id: "a",
          type: "rule",
          path: ["submitter", "seniority"],
          operator: "is",
          value: "manager",
        },
        { id: "b", type: "rule", path: ["amount"], operator: "gt", value: 500 },
        {
          id: "c",
          type: "rule",
          path: ["tags"],
          operator: "has_any_of",
          value: ["travel"],
        },
        {
          id: "d",
          type: "rule",
          path: ["amount"],
          operator: "between",
          value: [20_000, 10_000],
        },
      ],
    };

    expect(evaluateFilterQuery(tree, expense, nested).matched).toBe(true);
    expect(
      evaluateFilterQuery(tree, { ...expense, amount: 100 }, nested).results,
    ).toMatchObject({ b: false, root: false });
  });
});
