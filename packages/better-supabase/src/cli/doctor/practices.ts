import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { writtenByBlocks } from "../sql-layout.ts";
import { splitStatements } from "./shared.ts";

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

/** The Supabase and Postgres practices held against the app's own SQL. */
export const PRACTICE_RULES: readonly Rule[] = [
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
];
