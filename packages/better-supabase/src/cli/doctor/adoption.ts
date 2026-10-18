import type { FindingInput, Rule } from "./rules.ts";

import {
  excludedColumns,
  moduleLayout,
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

/** Checks that point at a shorter config for adopted schemas. */
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
];
