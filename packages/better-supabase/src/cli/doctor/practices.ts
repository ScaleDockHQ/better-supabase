import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { splitStatements } from "../../sql/index.ts";
import { writtenByBlocks } from "../sql-layout.ts";
import { OWNERSHIP_RULES } from "./ownership.ts";

/** The statements of the app's own schema files, each with its file. */
function appStatements(
  context: DoctorContext,
): readonly {
  readonly path: string;
  readonly text: string;
  readonly line: number;
}[] {
  return (context.sqlFiles ?? [])
    .filter(
      (file) =>
        !file.path.includes("migrations/") &&
        !file.path.includes("better-supabase-data/") &&
        !writtenByBlocks(file),
    )
    .flatMap((file) =>
      splitStatements(file.text).map((statement) => ({
        path: file.path,
        text: statement.text.replaceAll(/\s+/g, " "),
        line: statement.line,
      })),
    );
}

const POLICY = /^create policy /i;

const tableOfPolicy = (text: string): string =>
  /\bon ((?:"[^"]+"|\w+)(?:\.(?:"[^"]+"|\w+))?)/i.exec(text)?.[1] ?? "";

const bareTable = (name: string): string =>
  name.replaceAll('"', "").replace(/^public\./, "");

/** The columns a policy compares with a caller-derived value. */
function policyColumns(text: string): string[] {
  const columns = new Set<string>();

  for (const match of text.matchAll(
    /\(?"?(\w+)"? (?:=|in) \(?\s*\(?select\b/gi,
  )) {
    columns.add((match[1] ?? "").toLowerCase());
  }

  return [...columns].filter((column) => !SQL_WORDS.has(column));
}

const SQL_WORDS = new Set([
  "exists",
  "any",
  "select",
  "all",
  "not",
  "and",
  "or",
]);

/**
 * Per table, the leading columns of every index, primary key and unique
 * constraint the app's files create.
 */
function indexedColumns(
  statements: readonly { readonly text: string }[],
): Map<string, Set<string>> {
  const indexed = new Map<string, Set<string>>();

  const add = (table: string, column: string | undefined): void => {
    if (column === undefined) {
      return;
    }

    const key = bareTable(table);
    const set = indexed.get(key) ?? new Set<string>();

    set.add(column.replaceAll('"', "").toLowerCase());
    indexed.set(key, set);
  };

  for (const { text } of statements) {
    const index =
      /^create (?:unique )?index (?:concurrently )?(?:if not exists )?\S+ on (?:only )?(\S+?)(?: using \w+)? ?\(\s*"?(\w+)"?/i.exec(
        text,
      );

    if (index) {
      add(index[1] ?? "", index[2]);

      continue;
    }

    const table = /^create table (?:if not exists )?(\S+?) ?\(/i.exec(text);

    if (table) {
      for (const key of text.matchAll(
        /(?:primary key|unique) ?\(\s*"?(\w+)"?/gi,
      )) {
        add(table[1] ?? "", key[1]);
      }

      for (const column of text.matchAll(
        /[(,] ?"?(\w+)"? [\w ()]*?(?:primary key|unique)\b/gi,
      )) {
        add(table[1] ?? "", column[1]);
      }
    }
  }

  return indexed;
}

/** The Supabase and Postgres practices held against the app's own SQL. */
const SQL_PRACTICES: readonly Rule[] = [
  {
    code: "BS365",
    severity: "warning",
    title: "An update policy has no select policy",
    description:
      "Postgres only updates rows the caller can also select, so a table with a `for update` policy and no `for select` or `for all` policy updates zero rows without an error. Add a select policy with the same condition. Reads the app's schema files.",
    check(context) {
      const policies = appStatements(context).filter((statement) =>
        POLICY.test(statement.text),
      );

      const readable = new Set(
        policies
          .filter((policy) => / for (?:select|all)\b/i.test(policy.text))
          .map((policy) => tableOfPolicy(policy.text)),
      );

      return policies
        .filter(
          (policy) =>
            / for update\b/i.test(policy.text) &&
            !readable.has(tableOfPolicy(policy.text)),
        )
        .map((policy): FindingInput => ({
          message: `${policy.path}: the update policy on ${tableOfPolicy(policy.text)} has no select policy, so updates return no rows. Add one for select.`,
          target: policy.path,
          location: { file: policy.path, line: policy.line },
        }));
    },
  },
  {
    code: "BS366",
    severity: "error",
    title: "A policy decides on user_metadata",
    description:
      "`raw_user_meta_data` and `user_metadata` are editable by the signed-in user, so a policy that reads them lets anyone grant themselves access. Put authorization data in `app_metadata` or in the authorization provider. Display fields in a trigger may read `raw_user_meta_data`; a policy never does. Reads the app's schema files.",
    check: (context) =>
      appStatements(context)
        .filter(
          (statement) =>
            POLICY.test(statement.text) &&
            /raw_user_meta_data|user_metadata/i.test(statement.text),
        )
        .map((statement): FindingInput => ({
          message: `${statement.path}: a policy reads user_metadata, which the user can change. Read app_metadata or ask the authorization provider.`,
          target: statement.path,
          location: { file: statement.path, line: statement.line },
        })),
  },
  {
    code: "BS367",
    severity: "warning",
    title: "A view skips the caller's row level security",
    description:
      "A view runs with its owner's rights unless it sets `security_invoker = true`, so it returns rows the caller's policies would hide. Create the view `with (security_invoker = true)`. Reads the app's schema files.",
    check: (context) =>
      appStatements(context)
        .filter(
          (statement) =>
            /^create (?:or replace )?view /i.test(statement.text) &&
            !/security_invoker\s*=\s*(?:true|on)/i.test(statement.text),
        )
        .map((statement): FindingInput => ({
          message: `${statement.path}: a view without security_invoker returns rows the caller's policies would hide. Add with (security_invoker = true).`,
          target: statement.path,
          location: { file: statement.path, line: statement.line },
        })),
  },
  {
    code: "BS368",
    severity: "info",
    title: "A column uses timestamp or serial",
    description:
      "`timestamp` has no time zone and `serial` is the legacy form of an identity column. Use `timestamptz` and `generated always as identity`. Reads the app's schema files.",
    check: (context) =>
      appStatements(context)
        .filter(
          (statement) =>
            /^create table /i.test(statement.text) &&
            /\s"?\w+"? (?:timestamp(?! with)\b(?!tz)|big?serial\b|smallserial\b)/i.test(
              statement.text,
            ),
        )
        .map((statement): FindingInput => ({
          message: `${statement.path}: a column is timestamp or serial. Use timestamptz and generated always as identity.`,
          target: statement.path,
          location: { file: statement.path, line: statement.line },
        })),
  },
  {
    code: "BS383",
    severity: "warning",
    title: "A storage policy set has insert but no select and update",
    description:
      "A storage upload with `upsert: true` reads the existing object and then updates it, so it needs `insert`, `select` and `update` policies on `storage.objects`. With `insert` alone the first upload works and every overwrite fails. Add the select and update policies, or turn upsert off. Reads the app's schema files.",
    check(context) {
      const policies = appStatements(context).filter(
        (statement) =>
          POLICY.test(statement.text) &&
          /\bon storage\.objects\b/i.test(statement.text),
      );

      const has = (pattern: RegExp): boolean =>
        policies.some((policy) => pattern.test(policy.text));

      const insert = policies.find((policy) =>
        / for (?:insert|all)\b/i.test(policy.text),
      );

      if (
        insert === undefined ||
        (has(/ for (?:select|all)\b/i) && has(/ for (?:update|all)\b/i))
      ) {
        return [];
      }

      return [
        {
          message: `${insert.path}: storage.objects has an insert policy but no select and update policy, so an upload with upsert fails on overwrite. Add both.`,
          target: insert.path,
          location: { file: insert.path, line: insert.line },
        },
      ];
    },
  },
  {
    code: "BS384",
    severity: "warning",
    title: "A policy calls auth.uid() once per row",
    description:
      "`auth.uid()`, `auth.jwt()` and `auth.role()` called bare in a policy run for every row the policy checks. Written as `(select auth.uid())`, Postgres evaluates the call once per statement. Wrap each call in `select`. Reads the app's schema files.",
    check: (context) =>
      appStatements(context)
        .filter(
          (statement) =>
            POLICY.test(statement.text) &&
            /(?<!select )\bauth\.(?:uid|jwt|role)\(\)/i.test(statement.text),
        )
        .map((statement): FindingInput => ({
          message: `${statement.path}: a policy calls auth.uid(), auth.jwt() or auth.role() outside (select ...), so Postgres runs it for every row. Write (select auth.uid()).`,
          target: statement.path,
          location: { file: statement.path, line: statement.line },
        })),
  },
  {
    code: "BS385",
    severity: "info",
    title: "A policy column has no index",
    description:
      "A policy that filters on `user_id = (select auth.uid())` runs that filter in every query on the table, so the column needs an index that starts with it (a composite index puts the tenant column first). Without one Postgres reads the whole table. Add `create index` on the column. Reads the app's schema files.",
    check(context) {
      const statements = appStatements(context);
      const indexed = indexedColumns(statements);

      return statements
        .filter((statement) => POLICY.test(statement.text))
        .flatMap((statement): FindingInput[] => {
          const table = bareTable(tableOfPolicy(statement.text));

          return policyColumns(statement.text)
            .filter((column) => !indexed.get(table)?.has(column))
            .map((column) => ({
              message: `${statement.path}: a policy on ${table} filters on ${column}, which no index starts with. Add create index on ${table} (${column}).`,
              target: statement.path,
              location: { file: statement.path, line: statement.line },
            }));
        });
    },
  },
];

/** The practice rules and the ownership rules over the app's schema files. */
export const PRACTICE_RULES: readonly Rule[] = [
  ...SQL_PRACTICES,
  ...OWNERSHIP_RULES,
];
