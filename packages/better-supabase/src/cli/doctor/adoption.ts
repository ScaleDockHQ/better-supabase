import type {
  AdoptedTable,
  BlockSqlNames,
  DataExportPlan,
  TableCheckValues,
  ValueMaps,
} from "../../sql/index.ts";
import type {
  CatalogColumn,
  CatalogEnum,
  CatalogTable,
} from "../introspect/types.ts";
import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import {
  adoptedTables,
  adoptedViews,
  appValues,
  checkedValueMaps,
  checkValues,
  dataExportPlan,
  declaredCheckValues,
  excludedColumns,
  moduleLayout,
  moduleSource,
  redundantNulls,
  SECRET_COLUMNS,
  sameTenantColumn,
  sameTenantTrigger,
  SQL_MODULES,
  writtenValues,
} from "../../sql/index.ts";
import { tenantEntries } from "../codemod-config.ts";
import { notNullTag } from "../gen/model-functions.ts";
import { configFor } from "../gen/shared.ts";
import { isRecord } from "../guards.ts";
import { appTablesWithoutPolicies } from "./app-table-policies.ts";
import { adoptionContext, appTablesOf, appViewsOf } from "./app-tables.ts";
import { blockColumnsOnOwnedTables } from "./owned-columns.ts";
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

const READ_ONLY_KEY =
  /\bbetter_supabase"?\s*\.\s*"?(?:can|tenant_ids_with)"?\s*\([^)]*?'([^']*\.(?:read|view))'/giu;

/**
 * The permission keys ending in `.read` or `.view` that an update policy
 * checks.
 */
function readOnlyUpdateKeys(
  table: CatalogTable,
): readonly { readonly policy: string; readonly key: string }[] {
  return table.policies.flatMap((policy) =>
    policy.permissive &&
    !/^bsb?_/u.test(policy.name) &&
    (policy.command === "update" || policy.command === "all")
      ? [
          ...new Set(
            [
              ...`${policy.using ?? ""} ${policy.check ?? ""}`.matchAll(
                READ_ONLY_KEY,
              ),
            ].map((match) => match[1]!),
          ),
        ].map((key) => ({ policy: policy.name, key }))
      : [],
  );
}

function updatePolicyReadKeys(context: DoctorContext): FindingInput[] {
  return catalogOf(context).tables.flatMap((table) =>
    table.schema === "better_supabase"
      ? []
      : readOnlyUpdateKeys(table).map(({ policy, key }) => ({
          message: `Policy "${policy}" on ${qualified(table)} lets a caller update rows with the read permission "${key}". Every column of the row is writable for it. Check a write permission there, and guard the columns that need another one with columnGroups.`,
          target: `${qualified(table)}.${policy}`,
        })),
  );
}

/**
 * Checks for adopted schemas: config the SQL could carry, and references and
 * exports the modules leave open.
 */
export const ADOPTION_RULES: readonly Rule[] = [
  {
    code: "BS338",
    severity: "info",
    title: "gen.functions.notNull entry a comment tag could replace",
    description:
      "`gen` reads `@notNull` and `@notNull(a, b)` from a function's comment. A `gen.functions.<name>.notNull` entry for a function in the read schemas can move to the comment, next to the SQL it describes. A config entry wins over the tag.",
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
      "`upgrade` turns `select(*, -col)` in `expose` into the table's declared columns minus the excluded ones. An excluded column the table no longer has excludes nothing, and a renamed secret column is then granted under its new name. Remove the exclusion, or exclude the new name.",
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
      "A foreign key checks that the referenced row exists, not that it belongs to the row's tenant. Doctor lists each single-column key between two tables that both have the tenant column, when the key doesn't include that column and the table has no `bsb_same_tenant_<column>` trigger. List the reference in `blocks.memberships.options.sameTenant`, or set `sameTenant: { auto: true }` to derive every one from the schema files.",
    check: (context) => {
      if (!context.config.blockNames.includes("memberships")) {
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
                message: `${qualified(table)}.${column} references ${key.refSchema}.${key.refTable}, and both have ${tenant}, but no trigger checks that the referenced row has the same ${tenant}. Add it to blocks.memberships.options.sameTenant, or set sameTenant: { auto: true }.`,
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
    title: "Enum column of the app's that a module writes as text",
    description:
      "A module writes a text parameter or computed text value into a column of the app's table that the snapshot declares as an enum; string literals are fine. Postgres has no implicit cast from text to an enum, so the module's functions fail when they run. Columns the module casts to their declared type, such as the tags `kind`, the numbering `entity` and the profiles `locale`, may be enums.",
    check: (context) => {
      const { tables } = catalogOf(context);

      // Every table the database has may be the app's; a table a block
      // created has text columns, so it never reports here.
      const ownTables = Object.fromEntries(
        tables.map((table) => [qualified(table), "database"]),
      );

      return adoptedTables(
        context.config.blocks,
        ownTables,
        adoptionContext(context),
      ).flatMap((adopted) => {
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
              message: `blocks.${adopted.module} writes text into ${target} (${adopted.logical}.${logical}), which is the enum ${column.typeSchema}.${column.udt}. Postgres does not cast text to an enum, so the module's functions fail. Change the column to text with a check constraint on its values.`,
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
    title: "App webhook endpoints without a format",
    description:
      "A `webhooks-out` endpoints table of the app's that maps no `format` column sends every endpoint in `blocks.webhooks-out.options.defaultFormat`. Its default changed from the 0.8 body (`standard`) to `cloudevents` in 0.9, so receivers built for the old body break without any change to the config. `upgrade` refuses this config; doctor reports it for configs it loads without that check. Set `defaultFormat` explicitly, or add a format column and map it in `columns.endpoints.format`.",
    check: (context) => {
      const block = context.config.blocks["webhooks-out"];

      if (
        block === undefined ||
        block.options?.["defaultFormat"] !== undefined ||
        typeof block.columns?.["endpoints"]?.["format"] === "string"
      ) {
        return [];
      }

      const adopted = adoptedTables(
        context.config.blocks,
        appTablesOf(context),
        adoptionContext(context),
      ).find(
        (entry) =>
          entry.module === "webhooks-out" && entry.logical === "endpoints",
      );

      if (adopted === undefined) {
        return [];
      }

      const table = catalogOf(context).tables.find(
        (entry) =>
          entry.schema === adopted.schema && entry.name === adopted.table,
      );

      const name = `${adopted.schema}.${adopted.table}`;

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
    code: "BS349",
    severity: "warning",
    title: "Block writes through a view Postgres can't update",
    description:
      "A block table is mapped to a view of the app's (`blocks.<name>.tables`), and the block's TypeScript API inserts, updates or deletes its rows, but the view is not auto-updatable and has no `instead of` trigger: it has `distinct`, `group by`, a join, an aggregate or a set operation, or it is a materialized view. The block's functions that read the view work; the API calls that write it fail. Write those rows to the table under the view, add `instead of` triggers to the view, or map the block's table to a table.",
    check: (context) => {
      const views = appViewsOf(context);

      if (Object.keys(views.ownViews).length === 0) {
        return [];
      }

      return adoptedViews(context.config.blocks, appTablesOf(context), views)
        .filter((view) => view.writes && !view.updatable)
        .map((view) => ({
          message: `blocks.${view.module}.tables.${view.logical} is the view ${view.view}, which Postgres can't write through, and the block's TypeScript API writes ${view.logical} rows. Those calls fail; write the rows to the table under the view, add instead of triggers, or map ${view.logical} to a table.`,
          target: view.view,
        }));
    },
  },
  {
    code: "BS379",
    severity: "error",
    title: "A columns entry the render refuses",
    description:
      "`blocks.<name>.columns.<table>.<column>` is `null` for an optional column the view the block runs over lacks anyway, or `columns.<table>.tenant` repeats `sql.tenantColumn`. The block leaves out a column its view lacks, and `sql.tenantColumn` fills every tenant column, so the entry says nothing and the render refuses it. Run `better-supabase codemod config` to remove the entries. A `null` for a column the view has, or for a table you own, is fine.",
    check: (context) => {
      const views = appViewsOf(context);

      const nulls =
        Object.keys(views.ownViews).length === 0
          ? []
          : redundantNulls({
              modules: context.config.blocks,
              ownTables: appTablesOf(context),
              ...views,
            }).map((entry) => ({
              block: entry.block,
              table: entry.logical,
              column: entry.column,
              why: `${entry.view} has no "${entry.name}" column, so the block leaves it out already`,
            }));

      return [...nulls, ...tenantEntries(context.config)].map(
        (entry): FindingInput => ({
          message: `blocks.${entry.block}.columns.${entry.table}.${entry.column}: ${entry.why}. Run \`better-supabase codemod config\` to remove it.`,
          target: `blocks.${entry.block}.columns.${entry.table}.${entry.column}`,
        }),
      );
    },
  },
  {
    code: "BS622",
    severity: "warning",
    title: "A block adds a column to a table your files create",
    description:
      "A block runs over a table the app creates and adds an optional column to it with `add column if not exists`, and the app's own schema files don't declare that column. Blocks no longer add columns to tables you own, and the feature that needs the column turns off instead. Run `better-supabase codemod owned-columns` to declare the columns in your schema files, or map the column to `null` in `blocks.<name>.columns` to keep the feature off.",
    check: blockColumnsOnOwnedTables,
  },
  {
    code: "BS350",
    severity: "warning",
    title: "App table governs its policies but lacks one for a command",
    description:
      "A block runs over a table of the app's with `ownTablePolicies: \"app\"`, so it adds none of its `bsb_` policies there, and the table has no permissive policy for a command one of those policies would have granted. With row level security on, or off (the block's file turns it on), Postgres denies that command to every caller, so the block's functions that run as the caller and its TypeScript API find no rows for it. A missing `select` policy is a warning, a missing write policy is info. Add the app's own policy for each command the app uses, or set `ownTablePolicies` back to `block` for the block.",
    check: appTablesWithoutPolicies,
  },
  {
    code: "BS361",
    severity: "warning",
    title: "App table's check rejects values a block writes",
    description:
      "A block runs over one of your tables, and a check constraint or an enum on a column the block writes rejects a value the block writes into it. The module's own table declares the values it writes in its `check (column in (...))` constraint, and the block writes them through the column your config maps. A narrower check or enum makes the block's inserts and updates fail. Widen the check constraint or add the values to the enum.",
    check: checkValuesOverAdoptedTables,
  },
  {
    code: "BS362",
    severity: "warning",
    title: "Update policy checks a read permission",
    description:
      "A permissive policy for `update` (or `all`) checks a permission whose key ends in `.read` or `.view`. Anyone who can read a row can then change every column of it. Check a write permission in the policy, and put the columns that need a stricter permission in `tables.<name>.columnGroups`, which renders a trigger that raises 42501 when a caller without the group's permission changes one of them.",
    check: updatePolicyReadKeys,
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

const TEXT_TYPES = new Set([
  "text",
  "varchar",
  "bpchar",
  "char",
  "citext",
  "name",
]);

type AllowedValues =
  | {
      readonly values: ReadonlySet<string>;
      /** The enum type, when the column is an enum. */
      readonly enumName: string;
    }
  | {
      readonly values: ReadonlySet<string>;
      /** The check constraint that narrows the column. */
      readonly constraint: string;
    };

/** The values an app column accepts: its enum, or its membership checks. */
function allowedValues(
  column: CatalogColumn,
  table: CatalogTable,
  enums: ReadonlyMap<string, CatalogEnum>,
): AllowedValues | undefined {
  if (column.isArray) {
    return undefined;
  }

  if (column.isEnum) {
    const entry = enums.get(`${column.typeSchema}.${column.udt}`);

    return entry === undefined
      ? undefined
      : {
          values: new Set(entry.values),
          enumName: `${entry.schema}.${entry.name}`,
        };
  }

  if (!TEXT_TYPES.has(column.udt)) {
    return undefined;
  }

  let found:
    | { readonly values: ReadonlySet<string>; readonly constraint: string }
    | undefined;

  for (const check of table.checks) {
    const parsed = checkValues(check.definition);

    if (parsed === undefined || parsed.column !== column.name) {
      continue;
    }

    const accepted = new Set(parsed.values);

    found = {
      values:
        found === undefined
          ? accepted
          : new Set([...found.values].filter((value) => accepted.has(value))),
      constraint: found?.constraint ?? check.name,
    };
  }

  return found;
}

/** The module's own tables as it declares them, with the checks it writes. */
interface ManagedTables {
  readonly checks: readonly TableCheckValues[];
  readonly tables: BlockSqlNames["tables"];
  readonly values: ValueMaps;
  readonly sql: string;
}

function managedTables(
  name: string,
  context: DoctorContext,
): ManagedTables | Error | undefined {
  const module = SQL_MODULES[name];
  const tables = module?.names?.tables;

  if (module === undefined || tables === undefined) {
    return undefined;
  }

  try {
    const adoption = adoptionContext(context);

    const layout = {
      ...moduleLayout(
        context.config,
        undefined,
        [],
        undefined,
        adoption.accessProvider,
      ),
      ownTables: appTablesOf(context),
      ...appViewsOf(context),
    };

    return {
      checks: declaredCheckValues([{ text: module.sql }]),
      tables,
      values: checkedValueMaps(
        `blocks.${name}`,
        context.config.blocks[name]?.values,
        tables,
      ),
      sql: moduleSource(name, layout, context.config.blockNames) ?? module.sql,
    };
  } catch (error) {
    return error instanceof Error ? error : new Error(String(error));
  }
}

/** `blocks.<name>.options.statuses`: the stored value a block gives a label. */
function optionValues(
  options: Readonly<Record<string, unknown>> | undefined,
  label: string,
): readonly string[] {
  const statuses = options?.["statuses"];

  if (!isRecord(statuses)) {
    return [];
  }

  const value = statuses[label];

  return typeof value === "string" && value.length > 0 ? [value] : [];
}

function checkRejectsMessage(
  table: AdoptedTable,
  logical: string,
  column: string,
  missing: readonly string[],
  allowed: AllowedValues,
): string {
  const name = `${table.schema}.${table.table}`;
  const values = missing.map((value) => `"${value}"`).join(", ");
  const writes = `blocks.${table.module} writes ${values} into ${table.logical}.${logical}`;

  if ("enumName" in allowed) {
    return `${name}.${column} is the enum ${allowed.enumName}, which lacks ${values}, and ${writes}, so those writes fail. Add the values to the enum.`;
  }

  const accepted = [...allowed.values].map((value) => `"${value}"`).join(", ");

  return `${name}.${column} allows ${accepted}, and ${writes}, so those writes fail. Widen the check constraint ${allowed.constraint} to accept ${values}.`;
}

/** Checks of the app's tables that reject a value the module writes (BS361). */
function checkValuesOverAdoptedTables(context: DoctorContext): FindingInput[] {
  const adopted = adoptedTables(
    context.config.blocks,
    appTablesOf(context),
    adoptionContext(context),
  );

  if (adopted.length === 0) {
    return [];
  }

  const { tables, enums } = catalogOf(context);

  const byName = new Map(tables.map((table) => [qualified(table), table]));

  const enumByName = new Map(
    enums.map((entry) => [`${entry.schema}.${entry.name}`, entry]),
  );

  const rendered = new Map<string, ManagedTables | Error | undefined>();
  const findings: FindingInput[] = [];

  for (const adoptedTable of adopted) {
    let managed = rendered.get(adoptedTable.module);

    if (!rendered.has(adoptedTable.module)) {
      managed = managedTables(adoptedTable.module, context);
      rendered.set(adoptedTable.module, managed);

      if (managed instanceof Error) {
        findings.push({
          severity: "info",
          message: `blocks.${adoptedTable.module} could not be rendered with this config (${managed.message}), so doctor did not check the values it writes into your tables.`,
          target: `blocks.${adoptedTable.module}`,
        });
      }
    }

    if (managed === undefined || managed instanceof Error) {
      continue;
    }

    const spec = managed.tables[adoptedTable.logical];

    if (spec === undefined) {
      continue;
    }

    const name = `${adoptedTable.schema}.${adoptedTable.table}`;
    const catalogTable = byName.get(name);

    if (catalogTable === undefined) {
      continue;
    }

    const logicalByColumn = new Map(
      Object.entries(spec.columns).map(([logical, column]) => [
        column,
        logical,
      ]),
    );

    for (const check of managed.checks) {
      if (check.table.split(".").at(-1) !== spec.name) {
        continue;
      }

      const logical = logicalByColumn.get(check.column);

      if (logical === undefined) {
        continue;
      }

      const physical = adoptedTable.columns[logical];

      if (physical === undefined) {
        continue;
      }

      const column = catalogTable.columns.find(
        (entry) => entry.name === physical,
      );

      if (column === undefined) {
        continue;
      }

      const allowed = allowedValues(column, catalogTable, enumByName);

      if (allowed === undefined) {
        continue;
      }

      const options = context.config.blocks[adoptedTable.module]?.options;

      const written = new Set(
        writtenValues(
          managed.sql,
          `${adoptedTable.schema}.${adoptedTable.table}`,
          physical,
        ),
      );

      const wanted = [
        ...new Set(
          check.values.flatMap((label) => {
            const mapped = optionValues(options, label);

            const values =
              mapped.length > 0
                ? mapped
                : appValues(
                    managed.values[adoptedTable.logical]?.[logical],
                    label,
                  );

            const first = values[0];

            return first !== undefined && written.has(first) ? [first] : [];
          }),
        ),
      ];

      const missing = wanted.filter((value) => !allowed.values.has(value));

      if (missing.length === 0) {
        continue;
      }

      findings.push({
        message: checkRejectsMessage(
          adoptedTable,
          logical,
          physical,
          missing,
          allowed,
        ),
        target: `${name}.${physical}`,
      });
    }
  }

  return findings;
}
