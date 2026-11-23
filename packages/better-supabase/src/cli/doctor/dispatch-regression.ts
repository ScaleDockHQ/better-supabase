import type { CodeToken } from "../schema-reader/index.ts";
import type { DoctorContext, FindingInput, Rule, TextFile } from "./rules.ts";

import { codeStatementsOf, nameAt, wordsAt } from "../schema-reader/index.ts";

const ARM_NAME = /^[a-z0-9_]+$/iu;

/** The `when '<entity>' then` arms of one statement, in source order. */
function dispatchArms(tokens: readonly CodeToken[]): readonly string[] {
  return tokens.flatMap((_token, at): string[] =>
    wordsAt(tokens, at, "when") &&
    tokens[at + 1]?.kind === "string" &&
    wordsAt(tokens, at + 2, "then") &&
    ARM_NAME.test(tokens[at + 1]!.value)
      ? [tokens[at + 1]!.value]
      : [],
  );
}

/** The unqualified, lowercased function name a `create function` declares. */
function createdFunction(tokens: readonly CodeToken[]): string | undefined {
  const at = wordsAt(tokens, 0, "create", "or", "replace", "function")
    ? 4
    : wordsAt(tokens, 0, "create", "function")
      ? 2
      : -1;

  return at === -1
    ? undefined
    : nameAt(tokens, at)?.parts.at(-1)?.toLowerCase();
}

/** Dispatch arms per function, last statement of a name winning. */
function armsByFunction(
  files: readonly TextFile[],
): Map<string, readonly string[]> {
  const found = new Map<string, readonly string[]>();

  for (const file of files) {
    for (const statement of codeStatementsOf(file.text)) {
      const name = createdFunction(statement.tokens);
      const arms = name === undefined ? [] : dispatchArms(statement.tokens);

      if (name !== undefined && arms.length > 0) {
        found.set(name, arms);
      }
    }
  }

  return found;
}

const migrationFiles = (files: readonly TextFile[]): readonly TextFile[] =>
  files
    .filter((file) => file.path.includes("/migrations/"))
    .toSorted((left, right) => left.path.localeCompare(right.path));

const schemaFiles = (files: readonly TextFile[]): readonly TextFile[] =>
  files.filter((file) => !file.path.includes("/migrations/"));

/**
 * Configured import target names, when `blocks.imports.options.targets` is a
 * map.
 */
function configuredImportEntities(context: DoctorContext): readonly string[] {
  const imports = context.config.blocks["imports"];
  const targets = imports?.options?.["targets"];

  if (
    typeof targets !== "object" ||
    targets === null ||
    Array.isArray(targets)
  ) {
    return [];
  }

  return Object.keys(targets).toSorted();
}

/**
 * A schema function whose `when` arms a later migration dropped, and an
 * `import_apply_batch` override that omits an entity the config declares.
 */
export function dispatchRegressions(
  files: readonly TextFile[],
  entities: readonly string[],
): FindingInput[] {
  const schema = armsByFunction(schemaFiles(files));
  const migrations = armsByFunction(migrationFiles(files));
  const findings: FindingInput[] = [];

  for (const [name, arms] of schema) {
    const shipped = migrations.get(name);

    if (shipped === undefined) {
      continue;
    }

    const present = new Set(shipped);
    const missing = arms.filter((arm) => !present.has(arm));

    if (missing.length > 0) {
      findings.push({
        message: `The newest migration of ${name} drops dispatch arms the schema file still has: ${missing.join(", ")}.`,
        target: name,
      });
    }
  }

  const override = schema.get("import_apply_batch");

  if (override !== undefined && entities.length > 0) {
    const present = new Set(override);
    const missing = entities.filter((entity) => !present.has(entity));

    if (missing.length > 0) {
      findings.push({
        message: `import_apply_batch does not dispatch every configured import entity: ${missing.join(", ")}.`,
        target: "import_apply_batch",
      });
    }
  }

  return findings;
}

/** The newest migration of a dispatched function must keep the schema's arms. */
export const DISPATCH_REGRESSION_RULES: readonly Rule[] = [
  {
    code: "BS629",
    severity: "warning",
    title: "A migration drops import dispatch arms",
    description:
      "The newest migration that defines a function must contain every `when '<entity>' then` arm the schema file contains. An `import_apply_batch` in a schema file must also dispatch every entity in `blocks.imports.options.targets`. A regenerated migration that replaces the whole function from an older body drops targets the schema still calls, and those rows finish as applied without being written. Sync the migration with the schema file.",
    check(context) {
      return dispatchRegressions(
        context.sqlFiles ?? [],
        configuredImportEntities(context),
      );
    },
  },
];
