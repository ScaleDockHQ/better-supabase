import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { splitStatements } from "../../src/sql/pipeline/split.ts";

/**
 * The Supabase and Postgres practices the generated SQL is held to (plan Part
 * 6). Each rule counts its findings per module over the module goldens. A count
 * may go down and never up, so a module that breaks a rule fails here and the
 * numbers in `practices-baseline.json` only shrink. `UPDATE_PRACTICES=1`
 * rewrites the baseline after a count dropped.
 */
const golden = join(import.meta.dirname, "__golden__");
const baselineFile = join(import.meta.dirname, "practices-baseline.json");

type Counts = Readonly<Record<string, number>>;

interface Rule {
  readonly name: string;
  readonly why: string;
  readonly count: (statements: readonly string[]) => number;
  /**
   * Counts the module's schema file of the `alone` and `with every module`
   * variants only. Data files, upgrade steps and tests may hold `do` blocks: a
   * schema diff never reads them.
   */
  readonly schemaOnly?: true;
}

const startsWith = (statement: string, pattern: RegExp): boolean =>
  pattern.test(statement.replaceAll(/\s+/g, " "));

const POLICY = /^create policy /i;
const FUNCTION = /^create (?:or replace )?function /i;
const VIEW = /^create (?:or replace )?view /i;
const TABLE = /^create table /i;
const DO_BLOCK = /^do\s+(?:\$|language\b)/i;

/**
 * Dynamic SQL: `execute format(...)` or `execute '...'`, not `execute
 * function`.
 */
const EXECUTES = /\bexecute\s+(?:(?:pg_catalog\.)?format\s*\(|')/i;

const tableOfPolicy = (statement: string): string =>
  /\bon ((?:"[^"]+"|\w+)(?:\.(?:"[^"]+"|\w+))?)/i.exec(statement)?.[1] ?? "";

const RULES: readonly Rule[] = [
  {
    name: "definer-without-search-path",
    why: "A security definer function runs with its owner's rights and must pin `search_path`.",
    count: (statements) =>
      statements.filter(
        (statement) =>
          startsWith(statement, FUNCTION) &&
          /security definer/i.test(statement) &&
          !/set search_path/i.test(statement),
      ).length,
  },
  {
    name: "user-metadata-in-policy",
    why: "`user_metadata` is editable by the user, so a policy never decides on it.",
    count: (statements) =>
      statements.filter(
        (statement) =>
          startsWith(statement, POLICY) &&
          /raw_user_meta_data|user_metadata/i.test(statement),
      ).length,
  },
  {
    name: "view-without-security-invoker",
    why: "A view runs with its owner's rights unless it sets `security_invoker`, which skips the caller's RLS.",
    count: (statements) =>
      statements.filter(
        (statement) =>
          startsWith(statement, VIEW) &&
          !/security_invoker\s*=\s*(?:true|on)/i.test(statement),
      ).length,
  },
  {
    name: "bare-timestamp-column",
    why: "`timestamp` has no time zone; columns use `timestamptz`.",
    count: (statements) =>
      statements
        .filter((statement) => startsWith(statement, TABLE))
        .reduce(
          (sum, statement) =>
            sum +
            (statement.match(/\s"?\w+"? timestamp(?!tz)(?! with)\b/gi) ?? [])
              .length,
          0,
        ),
  },
  {
    name: "serial-column",
    why: "`serial` columns are replaced by `generated always as identity`.",
    count: (statements) =>
      statements
        .filter((statement) => startsWith(statement, TABLE))
        .reduce(
          (sum, statement) =>
            sum + (statement.match(/\sbig?serial\b/gi) ?? []).length,
          0,
        ),
  },
  {
    name: "update-policy-without-select",
    why: "An update policy needs a select policy on the same table, or updates return no rows.",
    count: (statements) => {
      const policies = statements.filter((statement) =>
        startsWith(statement, POLICY),
      );

      const readable = new Set(
        policies
          .filter((statement) => / for (?:select|all)\b/i.test(statement))
          .map(tableOfPolicy),
      );

      const updating = new Set(
        policies
          .filter((statement) => / for update\b/i.test(statement))
          .map(tableOfPolicy),
      );

      return [...updating].filter((table) => !readable.has(table)).length;
    },
  },
  {
    name: "policy-bare-auth-call",
    why: "A policy calls `auth.uid()` and `auth.jwt()` inside `(select ...)`, so Postgres evaluates it once per statement instead of once per row.",
    count: (statements) =>
      statements.filter(
        (statement) =>
          startsWith(statement, POLICY) &&
          /(?<!select\s)\bauth\.(?:uid|jwt|role)\(\)/i.test(
            statement.replaceAll(/\s+/g, " "),
          ),
      ).length,
  },
  {
    name: "uncapped-page-limit",
    why: "A list function clamps its page size; a raw `limit p_limit` lets one call read the whole table.",
    count: (statements) =>
      statements.filter(
        (statement) =>
          startsWith(statement, FUNCTION) &&
          /\blimit\s+p_(?:limit|page_size|count)\b/i.test(statement),
      ).length,
  },
  {
    name: "security-definer-functions",
    why: "Definer functions only go down; each moves to security invoker when it can.",
    count: (statements) =>
      statements.filter(
        (statement) =>
          startsWith(statement, FUNCTION) &&
          /security definer/i.test(statement),
      ).length,
  },
  {
    name: "row-triggers",
    why: "Row triggers only go down; a statement trigger does the same work once per statement.",
    count: (statements) =>
      statements.filter(
        (statement) =>
          startsWith(statement, /^create (?:or replace )?trigger /i) &&
          /for each row/i.test(statement),
      ).length,
  },
  {
    name: "do-blocks",
    schemaOnly: true,
    why: "A top-level `do` block builds or changes objects at run time, which a schema diff cannot see (ADR 0251, ADR 0400).",
    count: (statements) =>
      statements.filter((statement) => startsWith(statement, DO_BLOCK)).length,
  },
  {
    name: "do-blocks-with-execute",
    schemaOnly: true,
    why: "A `do` block that runs `execute` writes its statements as text, so the diff cannot see them either (ADR 0400).",
    count: (statements) =>
      statements.filter(
        (statement) =>
          startsWith(statement, DO_BLOCK) && EXECUTES.test(statement),
      ).length,
  },
];

/**
 * The schema files the `alone` and `with every module` variants of a golden
 * renders.
 */
function aloneSchemaSections(text: string): string {
  return text
    .split(/^-- ==== /m)
    .filter((section) => /^(?:alone|with every module): schema /.test(section))
    .join("\n");
}

function measure(): Record<string, Counts> {
  const result: Record<string, Counts> = {};

  for (const file of readdirSync(golden)
    .filter((name) => name.endsWith(".sql"))
    .toSorted()) {
    const text = readFileSync(join(golden, file), "utf-8");

    const statements = splitStatements(text).map((statement) => statement.text);

    const schemaStatements = splitStatements(aloneSchemaSections(text)).map(
      (statement) => statement.text,
    );

    const counts: Record<string, number> = {};

    for (const rule of RULES) {
      const found = rule.count(
        rule.schemaOnly === true ? schemaStatements : statements,
      );

      if (found > 0) {
        counts[rule.name] = found;
      }
    }

    if (Object.keys(counts).length > 0) {
      result[file.replace(/\.sql$/, "")] = counts;
    }
  }

  return result;
}

describe("generated SQL practices", () => {
  const now = measure();

  if (process.env["UPDATE_PRACTICES"] === "1") {
    writeFileSync(baselineFile, `${JSON.stringify(now, null, 2)}\n`);
  }

  // SAFETY: the baseline is this test's own file, written by `measure`.
  const baseline = JSON.parse(readFileSync(baselineFile, "utf-8")) as Record<
    string,
    Counts
  >;

  // Each rule's `why` is the reason a module's count may not grow.
  it.each(RULES.map((rule) => [rule.name, rule] as const))(
    "%s never grows in a module",
    (_name, rule) => {
      const grown = Object.entries(now)
        .map(([module, counts]) => {
          const found = counts[rule.name] ?? 0;
          const allowed = baseline[module]?.[rule.name] ?? 0;

          return found > allowed
            ? `${module}: ${String(found)} (baseline ${String(allowed)})`
            : undefined;
        })
        .filter((line) => line !== undefined);

      expect(grown).toEqual([]);
    },
  );

  it("has a baseline row only for a module that still has findings", () => {
    const stale = Object.entries(baseline).flatMap(([module, counts]) =>
      Object.keys(counts)
        .filter((rule) => (now[module]?.[rule] ?? 0) < (counts[rule] ?? 0))
        .map((rule) => `${module}: ${rule}`),
    );

    // A count dropped: run `UPDATE_PRACTICES=1 vitest run tests/sql/practices.test.ts`.
    expect(stale).toEqual([]);
  });

  it("finds each rule's pattern in a minimal statement", () => {
    const sample = [
      "create function f() returns int language sql security definer as $$ select 1 $$",
      "create policy p on t for update using (auth.jwt() -> 'user_metadata' = 'x')",
      "create view v as select 1",
      "create table t (id bigserial, at timestamp)",
      "do $$ begin execute 'select 1'; end $$",
      "create policy b on o for select using (owner = auth.uid())",
      "create function l(p_limit int) returns setof t language sql as $$ select * from t limit p_limit $$",
    ];

    expect(
      Object.fromEntries(RULES.map((rule) => [rule.name, rule.count(sample)])),
    ).toEqual({
      "definer-without-search-path": 1,
      "user-metadata-in-policy": 1,
      "view-without-security-invoker": 1,
      "bare-timestamp-column": 1,
      "serial-column": 1,
      "update-policy-without-select": 1,
      "policy-bare-auth-call": 2,
      "uncapped-page-limit": 1,
      "security-definer-functions": 1,
      "row-triggers": 0,
      "do-blocks": 1,
      "do-blocks-with-execute": 1,
    });
  });
});
