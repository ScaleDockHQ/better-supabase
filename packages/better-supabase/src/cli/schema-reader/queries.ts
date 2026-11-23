import type { CatalogPolicy } from "../introspect/types.ts";
import type {
  DeclaredFact,
  DropFact,
  FileFacts,
  ForeignKeyFact,
  IndexFact,
  TableFact,
  ViewFact,
} from "./facts.ts";

/** Privileges one role gets on a table, from the policies that name it. */
export interface PolicyGrantFact {
  /** `schema.table`, unquoted. */
  readonly table: string;
  readonly role: "anon" | "authenticated";
  readonly privileges: readonly ("select" | "insert" | "update" | "delete")[];
}

/** A view the files create. */
export interface ViewSummary {
  /** Its columns, or `undefined` when they can't be read (`select *`). */
  readonly columns: readonly string[] | undefined;
  /** Whether `insert`, `update` and `delete` reach the table under it. */
  readonly updatable: boolean;
}

/** An index a `create index` statement builds. */
export interface IndexSummary {
  readonly name: string | undefined;
  /** `schema.table`. */
  readonly table: string;
  readonly unique: boolean;
  readonly method: string;
  readonly partial: boolean;
  /** The `where` clause, including the keyword, when the index is partial. */
  readonly where?: string;
  readonly columns: readonly string[];
  readonly plain: boolean;
}

/** An index of the app's, by its name when it has one, and its leading columns. */
export interface OwnIndexSummary {
  readonly name?: string;
  readonly columns: readonly string[];
  readonly unique?: boolean;
  readonly plain?: boolean;
  readonly method?: string;
  readonly where?: string;
}

/** A foreign key the files declare. */
export interface ForeignKeySummary {
  readonly table: string;
  readonly columns: readonly string[];
  readonly references: string;
  readonly referencedColumns: readonly string[];
  readonly deferrable?: boolean;
}

const COMMANDS = ["select", "insert", "update", "delete"] as const;

const inSchemas = (name: string, schemas: readonly string[]): boolean =>
  schemas.includes(name.slice(0, name.indexOf(".")));

interface Event {
  readonly index: number;
  readonly apply: () => void;
}

/** Runs the events of one file in statement order. */
function inOrder(events: readonly Event[]): void {
  for (const event of events.toSorted((a, b) => a.index - b.index)) {
    event.apply();
  }
}

const drops = (facts: FileFacts, kind: DropFact["kind"]): readonly DropFact[] =>
  facts.drops.filter((drop) => drop.kind === kind);

/**
 * The tables the files create, as `schema.table`, in the order they first
 * appear. A later `drop table` removes one. Only tables in `schemas` are kept.
 */
export function declaredTables(
  files: readonly FileFacts[],
  schemas: readonly string[],
): string[] {
  const found = new Set<string>();

  for (const facts of files) {
    inOrder([
      ...facts.tables.map((table): Event => ({
        index: table.index,
        apply: () => {
          if (inSchemas(table.name, schemas)) {
            found.add(table.name);
          }
        },
      })),
      ...drops(facts, "table").map((drop): Event => ({
        index: drop.index,
        apply: () => {
          found.delete(drop.name);
        },
      })),
    ]);
  }

  return [...found];
}

/** Column names and types of each table in `schemas`, by `schema.table`. */
export function declaredColumnTypes(
  files: readonly FileFacts[],
  schemas: readonly string[],
): Map<string, Map<string, string>> {
  const found = new Map<string, Map<string, string>>();

  for (const facts of files) {
    for (const table of facts.tables) {
      if (!inSchemas(table.name, schemas)) {
        continue;
      }

      const known = found.get(table.name) ?? new Map<string, string>();

      for (const column of table.columns) {
        known.set(column.name, column.type);
      }

      found.set(table.name, known);
    }
  }

  return found;
}

/** Column names of each table in `schemas`, by `schema.table`. */
export function declaredTableColumns(
  files: readonly FileFacts[],
  schemas: readonly string[],
): Map<string, Set<string>> {
  return new Map(
    [...declaredColumnTypes(files, schemas)].map(
      ([table, columns]) => [table, new Set(columns.keys())] as const,
    ),
  );
}

/** The columns `alter table ... add column` adds, with their types. */
export function addedColumnTypes(
  files: readonly FileFacts[],
  schemas: readonly string[],
): Map<string, Map<string, string>> {
  const found = new Map<string, Map<string, string>>();

  for (const facts of files) {
    for (const alter of facts.alters) {
      if (alter.addedColumns.length === 0 || !inSchemas(alter.table, schemas)) {
        continue;
      }

      const known = found.get(alter.table) ?? new Map<string, string>();

      for (const column of alter.addedColumns) {
        known.set(column.name, column.type);
      }

      found.set(alter.table, known);
    }
  }

  return found;
}

/** The tables in `schemas` the files leave with row level security on. */
export function rlsTables(
  files: readonly FileFacts[],
  schemas: readonly string[],
): string[] {
  const found = new Set<string>();

  for (const facts of files) {
    inOrder([
      ...facts.alters
        .filter((alter) => alter.enablesRls)
        .map((alter): Event => ({
          index: alter.index,
          apply: () => {
            if (inSchemas(alter.table, schemas)) {
              found.add(alter.table);
            }
          },
        })),
      ...drops(facts, "table").map((drop): Event => ({
        index: drop.index,
        apply: () => {
          found.delete(drop.name);
        },
      })),
    ]);
  }

  return [...found];
}

/**
 * The views and materialized views the files create, as `schema.view`, with
 * their columns and whether they are auto-updatable. A later `drop view`
 * removes one. A view with an `instead of` trigger is updatable.
 */
export function declaredViews(
  files: readonly FileFacts[],
  schemas: readonly string[],
): ReadonlyMap<string, ViewSummary> {
  const found = new Map<string, ViewSummary>();
  const insteadOf = new Set<string>();

  for (const facts of files) {
    for (const trigger of facts.triggers) {
      if (trigger.timing === "instead of") {
        insteadOf.add(trigger.table);
      }
    }

    inOrder([
      ...facts.views.map((view: ViewFact): Event => ({
        index: view.index,
        apply: () => {
          if (inSchemas(view.name, schemas)) {
            found.set(view.name, {
              columns: view.columns,
              updatable: view.updatable,
            });
          }
        },
      })),
      ...drops(facts, "view").map((drop): Event => ({
        index: drop.index,
        apply: () => {
          found.delete(drop.name);
        },
      })),
    ]);
  }

  for (const view of insteadOf) {
    const entry = found.get(view);

    if (entry !== undefined) {
      found.set(view, { ...entry, updatable: true });
    }
  }

  return found;
}

/**
 * The privileges the permissive policies imply, per table and role: `for all`
 * gives the four commands, `to public` (or no `to`) counts for `authenticated`
 * only, so `anon` needs a policy that names it. Restrictive policies grant
 * nothing.
 */
export function policyGrants(
  files: readonly FileFacts[],
  schemas: readonly string[],
): PolicyGrantFact[] {
  type Named = Map<
    string,
    { roles: PolicyGrantFact["role"][]; privileges: readonly string[] }
  >;

  const policies = new Map<string, Named>();

  for (const facts of files) {
    inOrder([
      ...facts.policies.map((policy): Event => ({
        index: policy.index,
        apply: () => {
          if (!inSchemas(policy.table, schemas) || !policy.permissive) {
            return;
          }

          const privileges =
            policy.command === "all" ? COMMANDS : [policy.command];

          const roles = (policy.roles.length === 0 ? ["public"] : policy.roles)
            .map((role) => (role === "public" ? "authenticated" : role))
            .filter(
              (role): role is PolicyGrantFact["role"] =>
                role === "anon" || role === "authenticated",
            );

          const named: Named = policies.get(policy.table) ?? new Map();

          named.set(policy.name, { roles, privileges });
          policies.set(policy.table, named);
        },
      })),
      ...drops(facts, "policy").map((drop): Event => ({
        index: drop.index,
        apply: () => {
          const at = drop.name.lastIndexOf(".");

          policies.get(drop.name.slice(0, at))?.delete(drop.name.slice(at + 1));
        },
      })),
      ...drops(facts, "table").map((drop): Event => ({
        index: drop.index,
        apply: () => {
          policies.delete(drop.name);
        },
      })),
    ]);
  }

  const found = new Map<
    string,
    { table: string; role: PolicyGrantFact["role"]; privileges: Set<string> }
  >();

  for (const [table, named] of policies) {
    for (const { roles, privileges } of named.values()) {
      for (const role of roles) {
        const key = `${table}\u0000${role}`;

        const entry = found.get(key) ?? {
          table,
          role,
          privileges: new Set<string>(),
        };

        for (const privilege of privileges) {
          entry.privileges.add(privilege);
        }

        found.set(key, entry);
      }
    }
  }

  return [...found.values()]
    .map((entry): PolicyGrantFact => ({
      table: entry.table,
      role: entry.role,
      privileges: COMMANDS.filter((command) => entry.privileges.has(command)),
    }))
    .toSorted((a, b) => {
      if (a.table === b.table) {
        return a.role < b.role ? -1 : 1;
      }

      return a.table < b.table ? -1 : 1;
    });
}

/** The schema the app's own files create `extension` in, if they say. */
export function extensionSchema(
  sources: readonly FileFacts[],
  extension: string,
): string | undefined {
  for (const facts of sources) {
    if (facts.module) {
      continue;
    }

    const found = facts.objects.find(
      (object) => object.kind === "extension" && object.name === extension,
    );

    if (found?.schema !== undefined) {
      return found.schema;
    }
  }

  return undefined;
}

/**
 * A trigger function that keeps `updated_at` current by its name, as the
 * `updated-at` module's `replace_equivalent_triggers` reads it.
 */
const UPDATED_AT_FUNCTION = /updated_at|moddatetime|touch/i;

const SETS_UPDATED_AT = /\bnew\s*\.\s*"?updated_at"?\s*:?=/i;

/**
 * The update trigger that keeps `updated_at` current on each table in `schemas`
 * the files create one on, by `schema.table`: its function is named like one or
 * the files define it with `new.updated_at :=`. A call to `track_updated_at`
 * counts. Block triggers (`bsb_*`) don't.
 */
export function declaredUpdatedAtTriggers(
  files: readonly FileFacts[],
  schemas: readonly string[],
): Readonly<Record<string, string>> {
  const setters = new Set<string>();

  for (const facts of files) {
    for (const fn of facts.functions) {
      if (fn.body !== undefined && SETS_UPDATED_AT.test(fn.body)) {
        setters.add(fn.name);
      }
    }
  }

  const found: Record<string, string> = {};

  for (const facts of files) {
    for (const call of facts.calls) {
      const target = call.strings[0];

      if (
        target === undefined ||
        call.name.split(".").at(-1) !== "track_updated_at"
      ) {
        continue;
      }

      const table = target.includes(".") ? target : `public.${target}`;

      if (inSchemas(table, schemas)) {
        found[table] ??= "bsb_updated_at";
      }
    }

    for (const trigger of facts.triggers) {
      const name = trigger.function.slice(trigger.function.indexOf(".") + 1);

      if (
        trigger.name.startsWith("bsb_") ||
        trigger.timing === "instead of" ||
        !trigger.events.includes("update") ||
        !inSchemas(trigger.table, schemas)
      ) {
        continue;
      }

      if (UPDATED_AT_FUNCTION.test(name) || setters.has(trigger.function)) {
        found[trigger.table] ??= trigger.name;
      }
    }
  }

  return found;
}

/** Each `create index` of a file. */
export function indexStatements(facts: FileFacts): IndexSummary[] {
  return facts.indexes.map((index: IndexFact) => ({
    name: index.name,
    table: index.table,
    unique: index.unique,
    method: index.method.toLowerCase(),
    partial: index.predicate !== undefined,
    ...(index.predicate === undefined
      ? {}
      : { where: `where ${index.predicate}` }),
    columns: index.columns,
    plain: index.plain,
  }));
}

/** Whether `predicate` is exactly `<column> is not null` for one of `columns`. */
const NOT_NULL_KEY = /^(?:"([^"]+)"|([A-Za-z_][\w$]*))\s+is\s+not\s+null$/i;

function notNullKey(
  predicate: string | undefined,
  columns: readonly string[],
): boolean {
  if (predicate === undefined) {
    return false;
  }

  const text = predicate
    .trim()
    .replace(/^where\s+/i, "")
    .replace(/^\(+/, "")
    .replace(/\)+$/, "")
    .trim();

  const match = NOT_NULL_KEY.exec(text);
  const column = match?.[1] ?? match?.[2];

  return column !== undefined && columns.includes(column);
}

/**
 * The leading columns of every index the files give each table in `schemas`:
 * `create index` statements, and the primary keys and unique constraints in
 * `create table`.
 */
export function declaredIndexes(
  files: readonly FileFacts[],
  schemas: readonly string[],
): ReadonlyMap<string, readonly OwnIndexSummary[]> {
  const found = new Map<string, OwnIndexSummary[]>();

  const add = (
    table: string,
    columns: readonly string[],
    name?: string,
    unique = false,
    plain = true,
    other: Pick<OwnIndexSummary, "method" | "where"> = {},
  ): void => {
    if (columns.length > 0 && inSchemas(table, schemas)) {
      found.set(table, [
        ...(found.get(table) ?? []),
        {
          ...(name === undefined ? {} : { name }),
          columns,
          ...(unique ? { unique } : {}),
          plain,
          ...other,
        },
      ]);
    }
  };

  for (const facts of files) {
    for (const index of indexStatements(facts)) {
      const notNull = index.unique && notNullKey(index.where, index.columns);

      if (
        index.method === "btree" &&
        (!index.partial || notNull) &&
        index.columns.length > 0
      ) {
        add(index.table, index.columns, index.name, index.unique, index.plain);
      } else if (index.plain && index.columns.length > 0) {
        add(index.table, index.columns, index.name, index.unique, true, {
          ...(index.method === "btree" ? {} : { method: index.method }),
          ...(index.where === undefined ? {} : { where: index.where }),
        });
      }
    }

    for (const table of facts.tables) {
      for (const key of table.keys) {
        if (!key.nullsNotDistinct) {
          add(table.name, key.columns, undefined, true);
        }
      }
    }
  }

  return found;
}

/**
 * The foreign keys in `files`: `references` on a column, `foreign key` table
 * constraints and `alter table ... add constraint ... foreign key`, in the
 * order they appear. Only tables in `schemas` are kept.
 */
export function declaredForeignKeys(
  files: readonly FileFacts[],
  schemas: readonly string[],
): ForeignKeySummary[] {
  interface Pending {
    readonly table: string;
    readonly key: ForeignKeyFact;
  }

  const pending: Pending[] = [];
  const primaryKeys = new Map<string, readonly string[]>();

  for (const facts of files) {
    const found: { readonly index: number; readonly key: Pending }[] = [];

    for (const table of facts.tables) {
      if (table.primaryKey.length > 0) {
        primaryKeys.set(table.name, table.primaryKey);
      }

      for (const key of table.foreignKeys) {
        found.push({ index: table.index, key: { table: table.name, key } });
      }
    }

    for (const alter of facts.alters) {
      for (const key of alter.addedForeignKeys) {
        found.push({ index: alter.index, key: { table: alter.table, key } });
      }
    }

    pending.push(
      ...found.toSorted((a, b) => a.index - b.index).map(({ key }) => key),
    );
  }

  return pending
    .filter(({ table }) => inSchemas(table, schemas))
    .map(({ table, key }) => ({
      table,
      columns: key.columns,
      references: key.references,
      referencedColumns:
        key.referencedColumns.length > 0
          ? key.referencedColumns
          : (primaryKeys.get(key.references) ?? ["id"]),
      ...(key.deferrable ? { deferrable: true } : {}),
    }));
}

/** What `parseDeclared` returns for a file, built from its facts. */
export interface DeclarationSummary {
  readonly objects: readonly {
    readonly kind: DeclaredFact["kind"];
    readonly name: string;
    readonly line: number;
    readonly ifNotExists: boolean;
  }[];
  readonly alters: readonly {
    readonly table: string;
    readonly columns: readonly string[];
    readonly definitions: readonly {
      readonly name: string;
      readonly type: string;
    }[];
    readonly line: number;
  }[];
  readonly creates: readonly {
    readonly table: string;
    readonly definitions: readonly {
      readonly name: string;
      readonly type: string;
    }[];
  }[];
  readonly tags: readonly { readonly table: string; readonly tags: string }[];
  readonly policies: readonly {
    readonly table: string;
    readonly name: string;
    readonly terms: string;
    readonly line: number;
  }[];
  readonly doBlocks: readonly number[];
  readonly inserts: readonly number[];
  readonly outsideTransaction: boolean;
}

const definitionsOf = (
  columns: TableFact["columns"],
): { name: string; type: string }[] =>
  columns.map((column) => ({ name: column.name, type: column.definition }));

/** The declaration model's view of one file: what it creates and alters. */
export function declarationsOf(facts: FileFacts): DeclarationSummary {
  const replaced = new Set(drops(facts, "trigger").map((drop) => drop.name));

  return {
    // A trigger the file drops first is an override of the one a block declares.
    objects: facts.declared
      .filter((each) => each.kind !== "trigger" || !replaced.has(each.name))
      .map((each) => ({
        kind: each.kind,
        name:
          each.arity === undefined
            ? each.name
            : `${each.name}/${String(each.arity)}`,
        line: each.line,
        ifNotExists: each.ifNotExists,
      })),
    alters: facts.alters
      .filter((alter) => alter.addedColumns.length > 0)
      .map((alter) => ({
        table: alter.table,
        columns: alter.addedColumns.map((column) => column.name),
        definitions: definitionsOf(alter.addedColumns),
        line: alter.line,
      })),
    creates: facts.tables.map((table) => ({
      table: table.name,
      definitions: definitionsOf(table.columns),
    })),
    tags: facts.comments
      .filter((comment) => comment.target === "table")
      .map((comment) => ({ table: comment.name, tags: comment.text })),
    policies: facts.policies.map((policy) => ({
      table: policy.table,
      name: policy.name,
      terms: policy.terms,
      line: policy.line,
    })),
    doBlocks: facts.doCreates,
    inserts: facts.inserts,
    outsideTransaction: facts.outsideTransaction,
  };
}

/**
 * The policies the files leave on each `schema.table` in `schemas`, in order: a
 * later `drop policy` removes one, and a later `create policy` of the same name
 * replaces it.
 */
export function declaredPolicies(
  files: readonly FileFacts[],
  schemas: readonly string[],
): Record<string, CatalogPolicy[]> {
  const found = new Map<string, Map<string, CatalogPolicy>>();

  for (const facts of files) {
    inOrder([
      ...facts.policies.map((policy): Event => ({
        index: policy.index,
        apply: () => {
          if (!inSchemas(policy.table, schemas)) {
            return;
          }

          const named =
            found.get(policy.table) ?? new Map<string, CatalogPolicy>();

          named.set(policy.name, {
            name: policy.name,
            command: COMMANDS.find((c) => c === policy.command) ?? "all",
            roles: policy.roles.length === 0 ? ["public"] : policy.roles,
            permissive: policy.permissive,
            using: policy.using ?? null,
            check: policy.withCheck ?? null,
          });

          found.set(policy.table, named);
        },
      })),
      ...drops(facts, "policy").map((drop): Event => ({
        index: drop.index,
        apply: () => {
          const at = drop.name.lastIndexOf(".");

          found.get(drop.name.slice(0, at))?.delete(drop.name.slice(at + 1));
        },
      })),
    ]);
  }

  return Object.fromEntries(
    [...found].map(([table, named]) => [table, [...named.values()]]),
  );
}
