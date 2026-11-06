import type { Declaration } from "../../sql/index.ts";
import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { buildModel, conflicts } from "../../sql/index.ts";

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
];
