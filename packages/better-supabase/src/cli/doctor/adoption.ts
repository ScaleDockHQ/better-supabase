import type { DataExportPlan } from "../../sql/index.ts";
import type { CatalogTable } from "../introspect/types.ts";
import type { FindingInput, Rule } from "./rules.ts";

import {
  adoptedTables,
  dataExportPlan,
  excludedColumns,
  moduleLayout,
  SECRET_COLUMNS,
  sameTenantColumn,
  sameTenantTrigger,
} from "../../sql/index.ts";
import { notNullTag } from "../gen/model-functions.ts";
import { configFor } from "../gen/shared.ts";
import { catalogOf, qualified } from "./shared.ts";

const tagText = (notNull: true | readonly string[]): string =>
  notNull === true ? "@notNull" : `@notNull(${notNull.join(", ")})`;

const sameNotNull = (
  a: true | readonly string[] | undefined,
  b: true | readonly string[],
): boolean =>
  a === true || b === true
    ? a === b
    : a !== undefined &&
      a.length === b.length &&
      a.every((name) => b.includes(name));

/** Checks for adopted schemas: config the SQL could carry, and references and exports the modules leave open. */
export const ADOPTION_RULES: readonly Rule[] = [
  {
    code: "BS338",
    severity: "info",
    title: "functions.notNull entry a comment tag could replace",
    description:
      "`gen` reads `@notNull` and `@notNull(a, b)` from a function's comment. A `functions.<name>.notNull` entry for a function in the read schemas can move to the comment, next to the SQL it describes. A config entry wins over the tag.",
    check: (context) => {
      const { config } = context;

      return catalogOf(context).functions.flatMap((fn): FindingInput[] => {
        const notNull = configFor(
          config.functions,
          fn.schema,
          fn.name,
        )?.notNull;

        if (notNull === undefined || !config.schemas.includes(fn.schema)) {
          return [];
        }

        const name = `${fn.schema}.${fn.name}`;
        const tag = notNullTag(fn.comment);
        const wanted = tagText(notNull);

        let message: string;

        if (sameNotNull(tag, notNull)) {
          message = `functions.${fn.name}.notNull matches the ${wanted} tag on ${name}(${fn.signature}). Remove the config entry.`;
        } else if (tag === undefined) {
          message = `functions.${fn.name}.notNull can move to the function: add \`${wanted}\` to the comment on ${name}(${fn.signature}) (\`comment on function ${name}(${fn.signature}) is '${wanted}';\`), then remove the config entry.`;
        } else {
          message = `functions.${fn.name}.notNull (${wanted}) differs from the ${tagText(tag)} tag on ${name}(${fn.signature}), and the config entry wins. Make them agree, then remove the config entry.`;
        }

        return [{ message, target: `${name}(${fn.signature})` }];
      });
    },
  },
  {
    code: "BS339",
    severity: "warning",
    title: "expose excludes a column the table doesn't have",
    description:
      "`sql sync` turns `select(*, -col)` in `expose` into the table's declared columns minus the excluded ones. An excluded column the table no longer has excludes nothing, and a renamed secret column is then granted under its new name. Remove the exclusion, or exclude the new name.",
    check: (context) => {
      const tables = new Map(
        catalogOf(context).tables.map((table) => [qualified(table), table]),
      );

      return Object.entries(context.config.expose).flatMap(
        ([key, roles]): FindingInput[] => {
          const table = tables.get(key.includes(".") ? key : `public.${key}`);

          if (table === undefined) {
            return [];
          }

          const columns = new Set(table.columns.map((column) => column.name));

          const missing = [
            ...new Set(
              [...roles.anon, ...roles.authenticated, ...roles.serviceRole]
                .flatMap((privilege) => excludedColumns(privilege))
                .filter((column) => !columns.has(column)),
            ),
          ];

          return missing.map((column) => ({
            message: `expose.${key} excludes "${column}", which ${qualified(table)} doesn't have, so it excludes nothing. Remove "-${column}", or exclude the column's new name.`,
            target: `${qualified(table)}.${column}`,
          }));
        },
      );
    },
  },
  {
    code: "BS340",
    severity: "info",
    title: "Tenant foreign key without a same-tenant trigger",
    description:
      "A foreign key checks that the referenced row exists, not that it belongs to the row's tenant. Doctor lists each single-column key between two tables that both have the tenant column, when the key doesn't include that column and the table has no `bs_same_tenant_<column>` trigger. List the reference in `blocks.tenant.options.sameTenant`, or set `sameTenant: { auto: true }` to derive every one from the schema files.",
    check: (context) => {
      if (!context.config.blockNames.includes("tenant")) {
        return [];
      }

      const tenant = sameTenantColumn(moduleLayout(context.config));
      const { tables } = catalogOf(context);

      const tenantTables = new Set(
        tables
          .filter((table) =>
            table.columns.some((column) => column.name === tenant),
          )
          .map(qualified),
      );

      return tables
        .filter(
          (table) =>
            context.config.schemas.includes(table.schema) &&
            tenantTables.has(qualified(table)),
        )
        .flatMap((table) => {
          const triggers = new Set(
            table.triggers.map((trigger) => trigger.name),
          );

          return table.foreignKeys.flatMap((key): FindingInput[] => {
            const [column] = key.columns;

            if (
              column === undefined ||
              key.columns.length !== 1 ||
              column === tenant ||
              !tenantTables.has(`${key.refSchema}.${key.refTable}`) ||
              triggers.has(sameTenantTrigger(column))
            ) {
              return [];
            }

            return [
              {
                message: `${qualified(table)}.${column} references ${key.refSchema}.${key.refTable}, and both have ${tenant}, but no trigger checks that the referenced row has the same ${tenant}. Add it to blocks.tenant.options.sameTenant, or set sameTenant: { auto: true }.`,
                target: `${qualified(table)}.${column}`,
              },
            ];
          });
        });
    },
  },
  {
    code: "BS342",
    severity: "error",
    title: "Adopted enum column the module writes as text",
    description:
      "A module in adopt mode writes a text parameter or computed text value into a column the snapshot declares as an enum; string literals are fine. Postgres has no implicit cast from text to an enum, so the module's functions fail when they run. Columns the module casts to their declared type, such as the tags `kind` and the number-sequences `entity`, may be enums.",
    check: (context) => {
      const { tables } = catalogOf(context);

      return adoptedTables(context.config.blocks).flatMap((adopted) => {
        const table = tables.find(
          (entry) =>
            entry.schema === adopted.schema && entry.name === adopted.table,
        );

        if (table === undefined) {
          return [];
        }

        return adopted.textColumns.flatMap((logical): FindingInput[] => {
          const name = adopted.columns[logical];
          const column = table.columns.find((entry) => entry.name === name);

          if (column?.isEnum !== true || column.isArray) {
            return [];
          }

          const target = `${qualified(table)}.${column.name}`;

          return [
            {
              message: `blocks.${adopted.module} is in adopt mode and writes text into ${target} (${adopted.logical}.${logical}), which is the enum ${column.typeSchema}.${column.udt}. Postgres does not cast text to an enum, so the module's functions fail. Change the column to text with a check constraint on its values.`,
              target,
            },
          ];
        });
      });
    },
  },
  {
    code: "BS344",
    severity: "warning",
    title: "Adopted webhook endpoints without a format",
    description:
      "An adopted `webhooks-out` endpoints table that maps no `format` column sends every endpoint in `blocks.webhooks-out.options.defaultFormat`. Its default changed from the 0.8 body (`standard`) to `cloudevents` in 0.9, so receivers built for the old body break without any change to the config. `sql sync` refuses this config; doctor reports it for configs it loads without that check. Set `defaultFormat` explicitly, or add a format column and map it in `columns.endpoints.format`.",
    check: (context) => {
      const block = context.config.blocks["webhooks-out"];

      if (
        block?.mode !== "adopt" ||
        block.options?.["defaultFormat"] !== undefined ||
        typeof block.columns?.["endpoints"]?.["format"] === "string"
      ) {
        return [];
      }

      const adopted = adoptedTables(context.config.blocks).find(
        (entry) =>
          entry.module === "webhooks-out" && entry.logical === "endpoints",
      );

      const table =
        adopted === undefined
          ? undefined
          : catalogOf(context).tables.find(
              (entry) =>
                entry.schema === adopted.schema && entry.name === adopted.table,
            );

      const name =
        adopted === undefined
          ? "The adopted endpoints table"
          : `${adopted.schema}.${adopted.table}`;

      const unmapped = table?.columns.some(
        (column) => column.name === "format",
      );

      const has = unmapped
        ? "has a format column the config doesn't map"
        : "has no format column";

      return [
        {
          message: `${name} ${has}, so every endpoint gets blocks.webhooks-out.options.defaultFormat, which defaults to "cloudevents" since 0.9 ("standard" before). Set defaultFormat to the body your receivers expect, or map columns.endpoints.format.`,
          target: "blocks.webhooks-out.options.defaultFormat",
        },
      ];
    },
  },
  {
    code: "BS341",
    severity: "warning",
    title: "Data export includes a column that looks like a secret",
    description:
      "A data export writes every column of each table it reads, except the ones in `omit`. Doctor reports columns of the exported tables, including the ones `autoTables` finds, whose name matches `token`, `secret`, `_hash`, `password`, `api_key` or `license_key` and that no `omit` and no `omitPattern` leaves out. Add the column to the table's `omit`, keep the table out of exports with `export: false` or `autoTables.exclude`, or set `blocks.data-lifecycle.options.omitPattern`.",
    check: (context) => {
      const plan = dataExportPlan(
        moduleLayout(context.config),
        context.config.blockNames,
      );

      if (plan === undefined) {
        return [];
      }

      const secret = new RegExp(SECRET_COLUMNS, "i");
      const omitted = patternOf(plan.omitPattern);
      const tables = catalogOf(context).tables;
      const byName = new Map(tables.map((table) => [qualified(table), table]));

      const exported = [
        ...plan.tables.map((entry) => ({
          table: byName.get(entry.name),
          omit: entry.omit,
        })),
        ...autoExported(plan, tables),
      ];

      const findings = new Map<string, FindingInput>();

      for (const { table, omit } of exported) {
        if (table === undefined) {
          continue;
        }

        for (const column of table.columns) {
          const target = `${qualified(table)}.${column.name}`;

          if (
            !secret.test(column.name) ||
            omit.includes(column.name) ||
            omitted?.test(column.name) === true ||
            findings.has(target)
          ) {
            continue;
          }

          findings.set(target, {
            message: `Data exports of ${qualified(table)} include ${column.name}, which looks like a secret. Add it to the table's omit, keep the table out of exports, or set blocks.data-lifecycle.options.omitPattern.`,
            target,
          });
        }
      }

      return [...findings.values()];
    },
  },
];

const NO_OMIT: readonly string[] = [];

/** The tables `autoTables` adds to exports, which omit nothing. */
function autoExported(
  plan: DataExportPlan,
  tables: readonly CatalogTable[],
): { readonly table: CatalogTable; readonly omit: readonly string[] }[] {
  const { auto } = plan;

  if (auto === undefined) {
    return [];
  }

  return tables
    .filter(
      (table) =>
        auto.schemas.includes(table.schema) &&
        !auto.excluded(qualified(table)) &&
        table.columns.some((column) => auto.columns.includes(column.name)),
    )
    .map((table) => ({ table, omit: NO_OMIT }));
}

/** `omitPattern` as a JavaScript regex; undefined when off or not valid there. */
function patternOf(pattern: string | undefined): RegExp | undefined {
  if (pattern === undefined) {
    return undefined;
  }

  try {
    return new RegExp(pattern, "i");
  } catch {
    return undefined;
  }
}
