import type { Declaration } from "../../sql/index.ts";
import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import {
  buildModel,
  conflicts,
  duplicatePolicies,
  ownerOf,
  PRELUDE_FUNCTIONS,
  splitStatements,
} from "../../sql/index.ts";
import { overridesIn } from "./overrides.ts";
import { workflowOf } from "./shared.ts";

/** Schema files, not migrations or data files. */
const schemaFiles = (
  context: DoctorContext,
): readonly { readonly path: string; readonly text: string }[] =>
  (context.sqlFiles ?? []).filter(
    (file) =>
      !file.path.includes("migrations/") &&
      !file.path.includes("better-supabase-data/"),
  );

const MIGRATION_PATH = /(?:^|\/)migrations\//;

/** The schemas Supabase manages: objects there are not the app's to declare. */
const MANAGED_SCHEMAS: ReadonlySet<string> = new Set([
  "auth",
  "storage",
  "extensions",
  "realtime",
  "graphql",
  "graphql_public",
  "vault",
  "pgsodium",
  "pgbouncer",
  "supabase_functions",
  "net",
  "cron",
  "pgmq",
]);

/** What the coverage rules compare: objects a migration and a file both name. */
const COVERED_KINDS: ReadonlySet<Declaration["kind"]> = new Set([
  "table",
  "view",
  "type",
  "function",
]);

const IDENT_PART = String.raw`(?:"(?:[^"]|"")+"|[A-Za-z_][\w$]*)`;

const NAMED = String.raw`(${IDENT_PART}(?:\s*\.\s*${IDENT_PART})?)`;

const DROP = new RegExp(
  String.raw`^drop\s+(table|view|type|function|procedure)\s+(?:if\s+exists\s+)?${NAMED}`,
  "i",
);

const RENAME = new RegExp(
  String.raw`^alter\s+(table|view|type|function|procedure)\s+(?:if\s+exists\s+)?(?:only\s+)?${NAMED}\s*(?:\([^)]*\)\s*)?rename\s+to\s+(${IDENT_PART})`,
  "i",
);

const TRIGGER = new RegExp(
  String.raw`^create\s+(?:or\s+replace\s+)?(?:constraint\s+)?trigger\s+${IDENT_PART}\s+(before|after|instead of)\s+.*?\s+on\s+${NAMED}`,
  "i",
);

/** The text inside each balanced `check (...)` of a statement. */
function checkBodies(statement: string): string[] {
  const bodies: string[] = [];

  for (const match of statement.matchAll(/\bcheck\s*\(/gi)) {
    let depth = 1;
    let at = match.index + match[0].length;
    const start = at;

    while (at < statement.length && depth > 0) {
      const char = statement[at];

      depth += char === "(" ? 1 : char === ")" ? -1 : 0;
      at += 1;
    }

    bodies.push(statement.slice(start, at - 1));
  }

  return bodies;
}

/** A body with a `between` and an `and` or `or` besides the between's own. */
function mixesBetween(body: string): boolean {
  if (!/\bbetween\b/i.test(body)) {
    return false;
  }

  const rest = body.replaceAll(
    /\bbetween\s+(?:\([^)]*\)|[^\s()]+)\s+and\s+(?:\([^)]*\)|[^\s()]+)/gi,
    " ",
  );

  return /\b(?:and|or)\b/i.test(rest);
}

/** `schema.name` unquoted, with `public` for a bare name. */
const plain = (name: string): string => {
  const parts = name
    .split(/\s*\.\s*/)
    .map((part) => part.replace(/^"(.*)"$/, "$1").replaceAll('""', '"'));

  return parts.length === 1 ? `public.${parts[0]!}` : parts.join(".");
};

/** Whether `name` (`schema.name`) is in a schema Supabase manages. */
const inManagedSchema = (name: string): boolean =>
  MANAGED_SCHEMAS.has(name.slice(0, name.indexOf(".")));

const bare = (name: string): string => name.replace(/\/\d+$/, "");

/**
 * The tables, views, types and functions the migrations leave behind, oldest
 * migration first: a `create` adds one, a `drop` removes it and a `rename`
 * moves it. Each has the file and line of its `create`.
 */
function migratedObjects(
  migrations: readonly { readonly path: string; readonly text: string }[],
): ReadonlyMap<string, Declaration> {
  const state = new Map<string, Declaration>();

  for (const file of migrations.toSorted((a, b) =>
    a.path.localeCompare(b.path),
  )) {
    const created = new Map<number, Declaration>();

    for (const object of [...buildModel([file]).objects.values()].flat()) {
      if (COVERED_KINDS.has(object.kind)) {
        created.set(object.line, object);
      }
    }

    for (const statement of splitStatements(file.text)) {
      const flat = statement.text.replaceAll(/\s+/g, " ");
      const object = created.get(statement.line);

      if (object !== undefined) {
        state.set(bare(object.name), { ...object, file: file.path });
        continue;
      }

      const dropped = DROP.exec(flat);

      if (dropped !== null) {
        state.delete(plain(dropped[2]!));
        continue;
      }

      const renamed = RENAME.exec(flat);

      if (renamed !== null) {
        const from = plain(renamed[2]!);
        const held = state.get(from);

        if (held !== undefined) {
          const schema = from.slice(0, from.indexOf("."));
          state.delete(from);
          state.set(
            `${schema}.${plain(renamed[3]!).slice(plain(renamed[3]!).indexOf(".") + 1)}`,
            held,
          );
        }
      }
    }
  }

  return state;
}

/**
 * The objects the migrations create and the schema files don't
 * (`migrationOnly`) and the reverse (`fileOnly`), among the tables, views,
 * types and functions outside Supabase's schemas.
 */
function coverage(context: DoctorContext): {
  readonly migrationOnly: readonly Declaration[];
  readonly fileOnly: readonly Declaration[];
} {
  const all = context.sqlFiles ?? [];
  const migrations = all.filter((file) => MIGRATION_PATH.test(file.path));

  const files = all
    .filter((file) => !MIGRATION_PATH.test(file.path))
    .filter((file) => !file.path.includes("better-supabase-data/"));

  const migrated = migratedObjects(migrations);
  const declared = buildModel(files);

  // A `do` block can rename or create an object by name, which this reading
  // can't follow, so a history that has one reports nothing.
  const dynamic = migrations.some((file) =>
    splitStatements(file.text).some((statement) =>
      /^do\b/i.test(statement.text),
    ),
  );

  if (dynamic) {
    return { migrationOnly: [], fileOnly: [] };
  }

  const declaredObjects = new Map(
    [...declared.objects.values()]
      .map((list) => list[0]!)
      .filter(
        (object) =>
          COVERED_KINDS.has(object.kind) && !inManagedSchema(object.name),
      )
      .map((object) => [bare(object.name), object] as const),
  );

  return {
    migrationOnly: [...migrated]
      .filter(([name]) => !inManagedSchema(name) && !declaredObjects.has(name))
      .map(([, object]) => object),
    fileOnly: [...declaredObjects]
      .filter(([name]) => !migrated.has(name))
      .map(([, object]) => object),
  };
}

/**
 * Objects whose second definition replaces the first, so the owners must not
 * share them.
 */
const SHARED_KINDS: ReadonlySet<Declaration["kind"]> = new Set([
  "table",
  "view",
  "function",
  "type",
  "sequence",
]);

/** Who owns objects, held against the schema model of every schema file. */
export const OWNERSHIP_RULES: readonly Rule[] = [
  {
    code: "BS369",
    severity: "warning",
    title: "An app file declares an object a block module declares",
    description:
      "A table, view, function or type that both a block module file and one of the app's files create is defined twice, so the declarative diff keeps whichever file it reads last. Take the object out of one file: let the app file alter the block's table, or map the block to another name. Reads every schema file.",
    check(context) {
      const files = schemaFiles(context);

      // A function tagged `@bsb-override-of` replaces the module's on purpose;
      // BS394 holds it against the module's current text.
      const overridden = new Set(
        overridesIn(files).map((each) => `${each.file}\0${each.name}`),
      );

      return conflicts(buildModel(files))
        .filter(({ declarations }) => {
          const first = declarations[0];

          return (
            first !== undefined &&
            SHARED_KINDS.has(first.kind) &&
            declarations.some((each) => each.owner.kind === "module") &&
            declarations.some((each) => each.owner.kind === "app")
          );
        })
        .flatMap(({ declarations }) =>
          declarations
            .filter(
              (each) =>
                each.owner.kind === "app" &&
                !(
                  each.kind === "function" &&
                  overridden.has(`${each.file}\0${plain(bare(each.name))}`)
                ),
            )
            .map((each): FindingInput => {
              const module = declarations.find(
                (other) => other.owner.kind === "module",
              )!;

              return {
                message: `${each.file}: the ${each.kind} ${each.name} is also declared by the ${module.owner.kind === "module" ? module.owner.name : ""} module (${module.file}). Declare it once.`,
                target: each.file,
                location: { file: each.file, line: each.line },
              };
            }),
        );
    },
  },
  {
    code: "BS370",
    severity: "error",
    title: "A schema file asks for transaction=false",
    description:
      "`-- pg-delta: transaction=false` runs a file's statements outside a transaction, so a failure halfway leaves the schema partly applied and a schema diff can no longer tell which part ran. Create the index concurrently in a hand migration with a lock_timeout instead. Reads every schema file.",
    check: (context) =>
      schemaFiles(context)
        .filter((file) =>
          /^--\s*pg-delta:\s*transaction\s*=\s*false\b/im.test(file.text),
        )
        .map((file): FindingInput => ({
          message: `${file.path}: remove the transaction=false line and run the statement in a hand migration.`,
          target: file.path,
          location: { file: file.path, line: 1 },
        })),
  },
  {
    code: "BS371",
    severity: "warning",
    title: "Two schema files declare the same object",
    description:
      "A function, policy, trigger, index, table, view, type or sequence that two schema files both create has two definitions, and the declarative diff keeps whichever file it reads last. The helpers every block calls live once in the prelude file, so a copy of one in a module file means the file is older than the prelude: run `better-supabase upgrade`. Reads every schema file.",
    check(context) {
      const files = schemaFiles(context);
      const model = buildModel(files);

      return conflicts(model).flatMap(({ declarations }): FindingInput[] => {
        const first = declarations[0];

        if (
          first === undefined ||
          first.kind === "extension" ||
          first.kind === "schema" ||
          new Set(declarations.map((each) => each.file)).size < 2
        ) {
          return [];
        }

        const shared = SHARED_KINDS.has(first.kind);

        if (
          shared &&
          declarations.some((each) => each.owner.kind === "module") &&
          declarations.some((each) => each.owner.kind === "app")
        ) {
          return [];
        }

        const prelude =
          first.kind === "function" &&
          PRELUDE_FUNCTIONS.has(
            first.name.slice(first.name.indexOf(".") + 1).replace(/\/\d+$/, ""),
          );

        return declarations
          .slice(1)
          .map((each) => ({
            message: prelude
              ? `${each.file}: the function ${first.name.replace(/\/\d+$/, "")} belongs to the prelude file (${first.file}). Delete this copy, or run \`better-supabase upgrade\` if the file is a block module.`
              : `${each.file}: the ${each.kind} ${each.name} is also declared in ${first.file}. Declare it once.`,
            target: each.file,
            location: { file: each.file, line: each.line },
          }));
      });
    },
  },
  {
    code: "BS372",
    severity: "warning",
    title: "A do block in an app file creates objects",
    description:
      "A `do` block that runs `create` or `execute` builds objects at run time, so a schema diff can't see them and reports them missing. Write the statements out, with the choice the block makes made when you write the file. Reads the app's schema files.",
    check(context) {
      const files = schemaFiles(context);
      const model = buildModel(files);

      return files.flatMap((file) =>
        ownerOf(file.path, file.text).kind === "app"
          ? (model.files.get(file.path)?.doBlocks ?? []).map(
              (line): FindingInput => ({
                message: `${file.path}:${String(line)}: this do block creates objects at run time. Write them as plain statements.`,
                target: file.path,
                location: { file: file.path, line },
              }),
            )
          : [],
      );
    },
  },
  {
    code: "BS373",
    severity: "warning",
    title: "An app file creates an object with if not exists",
    description:
      "`create table if not exists` and `create index if not exists` skip the statement when an object of that name exists, so a changed definition never applies and a schema diff reads a file that doesn't say what the database holds. Write `create table` and let the diff change the table. Reads the app's schema files.",
    check(context) {
      const files = schemaFiles(context);
      const model = buildModel(files);

      return files.flatMap((file) =>
        ownerOf(file.path, file.text).kind === "app"
          ? (model.files.get(file.path)?.objects ?? [])
              .filter(
                (object) =>
                  object.ifNotExists &&
                  (object.kind === "table" ||
                    object.kind === "index" ||
                    object.kind === "view" ||
                    object.kind === "type" ||
                    object.kind === "sequence" ||
                    object.kind === "function"),
              )
              .map((object): FindingInput => ({
                message: `${file.path}:${String(object.line)}: remove \`if not exists\` from the ${object.kind} ${object.name}.`,
                target: file.path,
                location: { file: file.path, line: object.line },
              }))
          : [],
      );
    },
  },
  {
    code: "BS374",
    severity: "warning",
    title: "A block module file inserts rows",
    description:
      "A schema diff reads tables, not rows, so a top-level `insert` in a block module file never reaches the database from the sync. Rows belong in the module's data file, which `upgrade` writes into a migration. The generator writes none; this finds a hand edit. Reads every schema file.",
    check(context) {
      const files = schemaFiles(context);
      const model = buildModel(files);

      return files.flatMap((file) =>
        ownerOf(file.path, file.text).kind === "module"
          ? (model.files.get(file.path)?.inserts ?? []).map(
              (line): FindingInput => ({
                message: `${file.path}:${String(line)}: move this insert to the module's data file.`,
                target: file.path,
                location: { file: file.path, line },
              }),
            )
          : [],
      );
    },
  },
  {
    code: "BS375",
    severity: "warning",
    title: "Two policies decide the same way",
    description:
      "Two policies on one table with the same command, roles and expressions under different names. Postgres ORs permissive policies, so the second adds nothing, and a restrictive pair checks the same condition twice. Delete one. Reads every schema file.",
    check: (context) =>
      duplicatePolicies(buildModel(schemaFiles(context))).map(
        (group): FindingInput => ({
          message: `${group.table}: the policies ${group.names.join(" and ")} decide the same way (${group.files.map((entry) => `${entry.file}:${String(entry.line)}`).join(", ")}). Keep one.`,
          target: group.table,
          location: { file: group.files[0]!.file, line: group.files[0]!.line },
        }),
      ),
  },
  {
    code: "BS378",
    severity: "warning",
    title: "A trigger aimed at a view",
    description:
      "A `before` or `after` trigger on a view never fires for the rows of the table under it, and Postgres only accepts `instead of` triggers on a view. Put the trigger on the table the view selects from, or make it an `instead of` trigger that writes that table. Reads every schema file.",
    check(context) {
      const files = schemaFiles(context);

      const views = new Set(
        [...buildModel(files).objects.values()]
          .flat()
          .filter((object) => object.kind === "view")
          .map((object) => bare(object.name)),
      );

      return files.flatMap((file) =>
        splitStatements(file.text).flatMap((statement): FindingInput[] => {
          const match = TRIGGER.exec(statement.text.replaceAll(/\s+/g, " "));

          return match !== null &&
            match[1]!.toLowerCase() !== "instead of" &&
            views.has(plain(match[2]!))
            ? [
                {
                  message: `${file.path}:${String(statement.line)}: the ${match[1]!.toLowerCase()} trigger is aimed at the view ${plain(match[2]!)}. Aim it at the table under the view, or use \`instead of\`.`,
                  target: file.path,
                  location: { file: file.path, line: statement.line },
                },
              ]
            : [];
        }),
      );
    },
  },
  {
    code: "BS380",
    severity: "warning",
    title: "A check constraint mixes between with and or or",
    description:
      "Postgres rewrites `x between a and b` into two comparisons, so a check that joins a `between` to other conditions with `and` or `or` reads back from the database in another shape than the file declares, and the next diff proposes the same constraint again. Write the two comparisons out, or put the `between` alone in its own check. Reads the app's schema files.",
    check: (context) =>
      schemaFiles(context).flatMap((file) =>
        ownerOf(file.path, file.text).kind === "app"
          ? splitStatements(file.text).flatMap((statement): FindingInput[] =>
              checkBodies(statement.text)
                .filter(mixesBetween)
                .map(() => ({
                  message: `${file.path}:${String(statement.line)}: a check constraint joins a between to other conditions. Write the comparisons out.`,
                  target: file.path,
                  location: { file: file.path, line: statement.line },
                })),
            )
          : [],
      ),
  },
  {
    code: "BS376",
    severity: "warning",
    title: "A migration creates an object no schema file declares",
    description:
      "Under pg-delta, `supabase db schema declarative sync --strict-coverage` fails for an object the migration history creates and the schema files don't, because the next diff would drop it. Declare the table, view, type or function in `supabase/schemas`, or drop it in a migration. Reads the migrations and every schema file.",
    check: (context) =>
      workflowOf(context) === "pg-delta"
        ? coverage(context).migrationOnly.map((object): FindingInput => ({
            message: `${object.file}:${String(object.line)}: the ${object.kind} ${object.name.replace(/\/\d+$/, "")} is created here and declared in no schema file.`,
            target: object.file,
            location: { file: object.file, line: object.line },
          }))
        : [],
  },
  {
    code: "BS377",
    severity: "warning",
    title: "A schema file declares an object no migration creates",
    description:
      "Under pg-delta, a table, view, type or function in `supabase/schemas` that no migration creates is a change the sync has not turned into a migration yet. Run `supabase db schema declarative sync` and review the migration it writes. Reads the migrations and every schema file.",
    check: (context) =>
      workflowOf(context) === "pg-delta"
        ? coverage(context).fileOnly.map((object): FindingInput => ({
            message: `${object.file}:${String(object.line)}: the ${object.kind} ${object.name.replace(/\/\d+$/, "")} has no migration yet. Run the schema sync.`,
            target: object.file,
            location: { file: object.file, line: object.line },
          }))
        : [],
  },
];
