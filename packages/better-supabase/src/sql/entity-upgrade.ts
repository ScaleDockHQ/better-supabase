import type { ModuleContext } from "./context.ts";
import type { ModuleLayout } from "./module-types.ts";
import type { Qualified } from "./rename-sql.ts";

import { sqlString } from "../core/template.ts";
import { entityMarkers } from "./markers.ts";
import { moduleContext } from "./module-context.ts";
import { isOperationModule, moduleOperations } from "./modules/access-model.ts";
import {
  ADDED_COLUMN,
  FUNCTION,
  guarded,
  identParts,
  INDEX,
  NOT_COLUMN,
  POLICY,
  qualified,
  quote,
  renameColumn,
  renameFunction,
  renameTable,
  sqlName,
  TABLE,
  TRIGGER,
  unquote,
} from "./rename-sql.ts";
import { renderModules } from "./render.ts";

/** One statement `sql upgrade` runs to move an installed block to new names. */
export interface EntityRenameStep {
  readonly module: string;
  readonly description: string;
  readonly sql: string;
}

/** The renames for changed `blocks.<name>.entities`, or why they can't run. */
export interface EntityRenamePlan {
  readonly steps: readonly EntityRenameStep[];
  /** One message per module whose objects don't pair up between the names. */
  readonly refused: readonly string[];
}

/** The objects one module body creates, in the order it creates them. */
interface Created {
  readonly tables: Qualified[];
  /** Per table, its columns in order; then the columns added later. */
  readonly columns: (readonly [Qualified, string])[];
  readonly indexes: (readonly [string, Qualified])[];
  readonly policies: (readonly [string, Qualified])[];
  readonly triggers: (readonly [string, Qualified])[];
  readonly functions: Qualified[];
}

function created(body: string, schema: string): Created {
  const tables: Qualified[] = [];
  const columns: (readonly [Qualified, string])[] = [];

  for (const match of body.matchAll(TABLE)) {
    const table = qualified(match[1]!, schema);
    tables.push(table);

    for (const line of match[2]!.split("\n")) {
      const text = line.trim();
      const first = identParts(text)[0];

      if (text === "" || text.startsWith("--") || NOT_COLUMN.test(text)) {
        continue;
      }

      if (first !== undefined && text.startsWith(first)) {
        columns.push([table, unquote(first)]);
      }
    }
  }

  for (const match of body.matchAll(ADDED_COLUMN)) {
    columns.push([qualified(match[1]!, schema), unquote(match[2]!)]);
  }

  const named = (pattern: RegExp): (readonly [string, Qualified])[] =>
    [...body.matchAll(pattern)].map(
      (match) => [unquote(match[1]!), qualified(match[2]!, schema)] as const,
    );

  return {
    tables,
    columns,
    indexes: named(INDEX),
    policies: named(POLICY),
    triggers: named(TRIGGER),
    functions: [...body.matchAll(FUNCTION)].map((match) =>
      qualified(match[1]!, schema),
    ),
  };
}

/**
 * `{ work_item: { name: "task", plural: "tasks" } }` from
 * `work_item=task/tasks`.
 */
function markerEntities(
  marker: string,
): Record<string, { name: string; plural: string }> {
  return Object.fromEntries(
    marker
      .split(" ")
      .filter((part) => part.includes("="))
      .map((part) => {
        const [key = "", noun = ""] = part.split("=");
        const [name = "", plural = ""] = noun.split("/");

        return [key, { name, plural }];
      }),
  );
}

/**
 * The layout with `modules` back at the entities their files were installed
 * with.
 */
function installedLayout(
  layout: ModuleLayout,
  markers: ReadonlyMap<string, string>,
  modules: readonly string[],
): ModuleLayout {
  const configured = { ...layout.modules };

  for (const module of modules) {
    const { entities: _entities, ...rest } = configured[module] ?? {};
    const marker = markers.get(module);

    configured[module] =
      marker === undefined
        ? rest
        : { ...rest, entities: markerEntities(marker) };
  }

  return { ...layout, modules: configured };
}

/**
 * Pairs two lists created in the same order, or undefined when their lengths
 * differ.
 */
function pairs<T>(
  before: readonly T[],
  after: readonly T[],
): (readonly [T, T])[] | undefined {
  return before.length === after.length
    ? before.map((item, index) => [item, after[index]!] as const)
    : undefined;
}

const same = (a: Qualified, b: Qualified): boolean =>
  a.schema === b.schema && a.name === b.name;

/** The structural renames between one module's body under two sets of names. */
function bodyRenames(
  before: Created,
  after: Created,
): readonly string[] | undefined {
  const tables = pairs(before.tables, after.tables);
  const columns = pairs(before.columns, after.columns);
  const indexes = pairs(before.indexes, after.indexes);
  const policies = pairs(before.policies, after.policies);
  const triggers = pairs(before.triggers, after.triggers);
  const functions = pairs(before.functions, after.functions);

  if (!tables || !columns || !indexes || !policies || !triggers || !functions) {
    return undefined;
  }

  const once = new Set<string>();

  const add = (statement: string): readonly string[] => {
    if (once.has(statement)) {
      return [];
    }

    once.add(statement);

    return [statement];
  };

  return [
    ...tables.flatMap(([from, to]) =>
      same(from, to) ? [] : add(renameTable(from, to)),
    ),
    ...columns.flatMap(([[, from], [table, to]]) =>
      from === to ? [] : add(renameColumn(table, from, to)),
    ),
    ...indexes.flatMap(([[from], [to, table]]) =>
      from === to
        ? []
        : add(
            `alter index if exists ${sqlName({ schema: table.schema, name: from })} rename to ${quote(to)};`,
          ),
    ),
    ...policies.flatMap(([[from], [to, table]]) =>
      from === to
        ? []
        : add(
            guarded(
              `exists (select 1 from pg_policies where schemaname = ${sqlString(table.schema)} and tablename = ${sqlString(table.name)} and policyname = ${sqlString(from)})`,
              `alter policy ${quote(from)} on ${sqlName(table)} rename to ${quote(to)};`,
            ),
          ),
    ),
    ...triggers.flatMap(([[from], [to, table]]) =>
      from === to
        ? []
        : add(
            guarded(
              `exists (select 1 from pg_trigger where tgrelid = to_regclass(${sqlString(sqlName(table))}) and tgname = ${sqlString(from)})`,
              `alter trigger ${quote(from)} on ${sqlName(table)} rename to ${quote(to)};`,
            ),
          ),
    ),
    ...functions.flatMap(([from, to]) =>
      same(from, to) ? [] : add(renameFunction(from, to)),
    ),
  ];
}

/** Permission keys the module checks, renamed: they are rows in `permissions`. */
function permissionKeyRenames(
  module: string,
  before: ModuleContext,
  after: ModuleContext,
): readonly (readonly [string, string])[] {
  if (!isOperationModule(module)) {
    return [];
  }

  const keys: Readonly<Record<string, string>> = moduleOperations(module);

  const renamed = Object.entries(keys).flatMap(([action, fallback]) => {
    const from = before.permissionKey(action, fallback);
    const to = after.permissionKey(action, fallback);

    return from === to ? [] : [[from, to] as const];
  });

  const wildcard = (key: string): string => key.replace(/\.[^.]*$/, ".*");

  const wildcards = renamed.flatMap(([from, to]) =>
    wildcard(from) === wildcard(to)
      ? []
      : [[wildcard(from), wildcard(to)] as const],
  );

  return [
    ...new Map(
      [...renamed, ...wildcards].map((pair) => [pair.join(" "), pair]),
    ).values(),
  ];
}

/** Subject types the module's renamed entities registered under. */
function subjectTypeRenames(
  before: ModuleContext,
  after: ModuleContext,
): readonly (readonly [string, string])[] {
  return Object.values(after.resolved.entities).flatMap((entity) => {
    const was = before.resolved.entities[entity.key];

    return entity.subject === undefined ||
      was === undefined ||
      was.to.singular === entity.to.singular
      ? []
      : [[was.to.singular, entity.to.singular] as const];
  });
}

/** Every installed table with a `subjectType` column, as `[table, column]`. */
function subjectColumns(
  contexts: ReadonlyMap<string, ModuleContext>,
): readonly (readonly [string, string])[] {
  return [...contexts.values()].flatMap((ctx) =>
    ctx.mode === "custom"
      ? []
      : Object.entries(ctx.names.tables).flatMap(([table, spec]) =>
          "subjectType" in spec.columns && ctx.hasTable(table)
            ? [[ctx.table(table), ctx.col(table, "subjectType")] as const]
            : [],
        ),
  );
}

const namesLabel = (marker: string | undefined): string =>
  marker === undefined || marker === "" ? "default names" : marker;

/**
 * The statements that move installed blocks from the entity names their files
 * carry (`@bs-entities`) to the names `layout` gives them: tables, columns,
 * indexes, policies, triggers and functions are renamed in place, permission
 * keys keep their grants, and stored subject types follow. `installedText` is
 * the installed module files or migration; `modules` the installed modules.
 */
export function entityRenamePlan(
  names: readonly string[],
  modules: readonly string[],
  installedText: string,
  layout: ModuleLayout,
): EntityRenamePlan {
  const before = entityMarkers(installedText);

  const current = renderModules(names, layout).filter(
    (file) => file.kind === "schema",
  );

  const after = entityMarkers(current.map((file) => file.contents).join("\n"));

  const changed = modules.filter(
    (module) => (before.get(module) ?? "") !== (after.get(module) ?? ""),
  );

  if (changed.length === 0) {
    return { steps: [], refused: [] };
  }

  const oldLayout = installedLayout(layout, before, changed);

  const previous = renderModules(names, oldLayout).filter(
    (file) => file.kind === "schema",
  );

  const rendered = previous.map((file) => file.module);

  const bodyOf = (files: typeof current, module: string): string =>
    files
      .filter((file) => file.module === module)
      .map((file) => file.contents)
      .join("\n");

  const contexts = (from: ModuleLayout): Map<string, ModuleContext> =>
    new Map(
      rendered.map((module) => [module, moduleContext(module, from, rendered)]),
    );

  const oldContexts = contexts(oldLayout);
  const newContexts = contexts(layout);
  const steps: EntityRenameStep[] = [];
  const refused: string[] = [];

  for (const module of rendered) {
    const schema = newContexts.get(module)?.schemaName ?? "better_supabase";

    const renames = bodyRenames(
      created(bodyOf(previous, module), schema),
      created(bodyOf(current, module), schema),
    );

    if (renames === undefined) {
      refused.push(
        `blocks.${module}.entities changed on an installed block (${namesLabel(before.get(module))} to ${namesLabel(after.get(module))}), and its objects don't pair up between the two names. Rename them in a migration, or keep the names the block was installed with.`,
      );
      continue;
    }

    steps.push(
      ...renames.map((sql) => ({
        module,
        description: "Renames an object after blocks.<name>.entities.",
        sql,
      })),
    );
  }

  const access = newContexts.get("access");

  if (access?.mode !== "custom" && access?.hasTable("permissions")) {
    const table = access.table("permissions");
    const key = access.col("permissions", "key");

    for (const module of changed) {
      const was = oldContexts.get(module);
      const now = newContexts.get(module);

      for (const [from, to] of was && now
        ? permissionKeyRenames(module, was, now)
        : []) {
        steps.push({
          module,
          description: `Renames the permission key ${from} to ${to}.`,
          sql: guarded(
            `to_regclass(${sqlString(table)}) is not null`,
            `update ${table} set ${key} = ${sqlString(to)} where ${key} = ${sqlString(from)} and not exists (select 1 from ${table} where ${key} = ${sqlString(to)});`,
          ),
        });
      }
    }
  }

  const columns = subjectColumns(newContexts);

  for (const module of changed) {
    const was = oldContexts.get(module);
    const now = newContexts.get(module);

    for (const [from, to] of was && now ? subjectTypeRenames(was, now) : []) {
      steps.push(
        ...columns.map(([table, column]) => ({
          module,
          description: `Moves stored subjects of type ${from} to ${to}.`,
          sql: `update ${table} set ${column} = ${sqlString(to)} where ${column} = ${sqlString(from)};`,
        })),
      );
    }
  }

  return { steps, refused };
}
