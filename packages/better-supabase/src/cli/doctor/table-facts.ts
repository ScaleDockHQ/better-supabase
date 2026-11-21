import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import {
  auditExemptTag,
  grantExpose,
  grantTag,
  lifecycleTag,
  sameTenantTag,
} from "../../sql/index.ts";
import { globs } from "./audit-coverage.ts";
import { catalogOf, qualified, tableObject } from "./shared.ts";

const configKey = (table: { schema: string; name: string }): string[] => [
  table.name,
  `${table.schema}.${table.name}`,
];

function recordKeys(value: unknown): string[] {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? Object.keys(value)
    : [];
}

/**
 * Table facts the config holds that a `comment on table` tag can hold next to
 * the table (BS702). A fact the table's comment already carries is not listed.
 */
export function configFactsATagCanHold(context: DoctorContext): FindingInput[] {
  const { config } = context;
  const listed: unknown = config.blocks["audit"]?.options?.["exempt"];
  const entries: unknown[] = Array.isArray(listed) ? listed : [];

  const exempt = globs(
    entries.map((entry) =>
      typeof entry === "string"
        ? entry
        : typeof entry === "object" &&
            entry !== null &&
            "table" in entry &&
            typeof entry.table === "string"
          ? entry.table
          : "",
    ),
  );

  const lifecycle = new Set(
    recordKeys(config.blocks["data-lifecycle"]?.options?.["tables"]),
  );

  return catalogOf(context).tables.flatMap((table) => {
    if (!config.schemas.includes(table.schema) || table.kind !== "table") {
      return [];
    }

    const comment = table.comment ?? null;
    const keys = configKey(table);
    const facts: string[] = [];

    if (
      auditExemptTag(comment) === undefined &&
      exempt.some((pattern) => pattern.test(qualified(table)))
    ) {
      facts.push("audit-exempt");
    }

    if (
      lifecycleTag(comment) === undefined &&
      keys.some((key) => lifecycle.has(key))
    ) {
      facts.push("data-lifecycle");
    }

    if (
      grantTag(comment) === undefined &&
      keys.some((key) => config.expose[key] !== undefined)
    ) {
      facts.push("grant");
    }

    return facts.length === 0
      ? []
      : [
          {
            message: `${qualified(table)} has ${facts.join(", ")} in the config. A comment on the table holds it next to the schema: run better-supabase codemod table-tags.`,
            target: qualified(table),
            object: tableObject(table),
          },
        ];
  });
}

function tryTag(read: () => unknown): string | undefined {
  try {
    read();
  } catch (error) {
    return error instanceof Error ? error.message : String(error);
  }

  return undefined;
}

/** `@bsb` table facts that cannot take effect (BS703). */
export function tableFactProblems(context: DoctorContext): FindingInput[] {
  return catalogOf(context).tables.flatMap((table) => {
    if (
      !context.config.schemas.includes(table.schema) ||
      table.kind !== "table"
    ) {
      return [];
    }

    const comment = table.comment ?? null;
    const target = qualified(table);
    const problems: string[] = [];

    const lifecycleError = tryTag(() => lifecycleTag(comment));

    if (lifecycleError === undefined) {
      const fact = lifecycleTag(comment);

      if (
        fact !== undefined &&
        fact.user === undefined &&
        fact.tenant === undefined
      ) {
        problems.push(
          "@bsb data-lifecycle names neither user= nor tenant=, so the block has no column to find the rows by",
        );
      }
    } else {
      problems.push(lifecycleError);
    }

    const grantError = tryTag(() => {
      const fact = grantTag(comment);

      if (fact !== undefined) {
        grantExpose(target, fact);
      }
    });

    if (grantError !== undefined) {
      problems.push(grantError);
    }

    const columnProblems = table.columns.flatMap((column) => {
      const fact = sameTenantTag(column.comment ?? null);

      if (fact === undefined || fact.skip === true) {
        return [];
      }

      const single = table.foreignKeys.some(
        (key) => key.columns.length === 1 && key.columns[0] === column.name,
      );

      return single
        ? []
        : [
            `@bsb same-tenant on ${column.name} needs a single-column foreign key on that column`,
          ];
    });

    return [...problems, ...columnProblems].map((problem) => ({
      message: `${target}: ${problem}.`,
      target,
      object: tableObject(table),
    }));
  });
}

/** Rules about table facts held in comments and in the config. */
export const TABLE_FACT_RULES: readonly Rule[] = [
  {
    code: "BS702",
    severity: "info",
    title: "Table fact held in the config",
    description:
      "The config holds an audit exemption, a `data-lifecycle` table entry or an `expose` entry for a table whose comment does not carry it. A `comment on table ... is '@bsb audit-exempt reason=...'`, `@bsb data-lifecycle user=...` or `@bsb grant authenticated=select` sits next to the table, so a review of the schema shows it. `better-supabase codemod table-tags` moves the entries. The config entry still works.",
    check: configFactsATagCanHold,
  },
  {
    code: "BS703",
    severity: "warning",
    title: "Table tag cannot take effect",
    description:
      "A `@bsb data-lifecycle`, `grant` or `same-tenant` tag is malformed or incomplete: a non-boolean flag, a `data-lifecycle` tag with neither `user=` nor `tenant=`, a `grant` with an unknown role or privilege, or `same-tenant` on a column with no single-column foreign key. The tag is ignored until it is fixed.",
    check: tableFactProblems,
  },
];
