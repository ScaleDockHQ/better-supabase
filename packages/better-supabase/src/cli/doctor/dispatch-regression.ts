import type { DoctorContext, FindingInput, Rule, TextFile } from "./rules.ts";

import { splitStatements } from "../../sql/index.ts";

const ARM = /when\s+'([a-z0-9_]+)'\s+then/giu;

const FUNCTION_NAME =
  /^create\s+(?:or\s+replace\s+)?function\s+((?:"[^"]+"|[\w$]+)(?:\s*\.\s*(?:"[^"]+"|[\w$]+))?)/iu;

/** The `when '<entity>' then` arms of one statement, in source order. */
function dispatchArms(sql: string): readonly string[] {
  return [...sql.matchAll(ARM)].flatMap((match) =>
    match[1] === undefined ? [] : [match[1]],
  );
}

/** The unqualified function name a `create function` statement declares. */
function createdFunction(sql: string): string | undefined {
  const declared = FUNCTION_NAME.exec(sql.replaceAll(/\s+/g, " ").trim())?.[1];

  if (declared === undefined) {
    return undefined;
  }

  const bare = declared.split(".").at(-1) ?? declared;

  return bare.replaceAll('"', "").toLowerCase();
}

/** Dispatch arms per function, last statement of a name winning. */
function armsByFunction(
  files: readonly TextFile[],
): Map<string, readonly string[]> {
  const found = new Map<string, readonly string[]>();

  for (const file of files) {
    for (const statement of splitStatements(file.text)) {
      const name = createdFunction(statement.text);
      const arms = name === undefined ? [] : dispatchArms(statement.text);

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
