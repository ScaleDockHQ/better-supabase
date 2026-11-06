import type { Declaration } from "../../sql/index.ts";
import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import {
  BLOCK_OVERLAPS,
  buildModel,
  conflicts,
  ownerOf,
  PRELUDE_FUNCTIONS,
} from "../../sql/index.ts";

/** Schema files, not migrations or data files. */
const schemaFiles = (
  context: DoctorContext,
): readonly { readonly path: string; readonly text: string }[] =>
  (context.sqlFiles ?? []).filter(
    (file) =>
      !file.path.includes("migrations/") &&
      !file.path.includes("better-supabase-data/"),
  );

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
      return conflicts(buildModel(schemaFiles(context)))
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
            .filter((each) => each.owner.kind === "app")
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

      return conflicts(model).flatMap(
        ({ key, declarations }): FindingInput[] => {
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
            (shared &&
              declarations.some((each) => each.owner.kind === "module") &&
              declarations.some((each) => each.owner.kind === "app")) ||
            (declarations.every((each) => each.owner.kind === "module") &&
              BLOCK_OVERLAPS.has(key))
          ) {
            return [];
          }

          const prelude =
            first.kind === "function" &&
            PRELUDE_FUNCTIONS.has(
              first.name
                .slice(first.name.indexOf(".") + 1)
                .replace(/\/\d+$/, ""),
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
        },
      );
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
];
