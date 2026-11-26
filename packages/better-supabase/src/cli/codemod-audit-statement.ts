import type { CodemodProject } from "./codemod.ts";
import type { PlannedFile } from "./core/files.ts";
import type { SqlStatement } from "./schema-reader/statements.ts";

import { auditStatementTriggers } from "../sql/row-audit.ts";
import { factsOf, statementsOf } from "./schema-reader/index.ts";
import { primeSchemaTexts } from "./sql-facts.ts";

const NAMED = [
  "category",
  "event_prefix",
  "target_type",
  "tenant_column",
  "label_column",
  "archive_column",
  "archive_value",
] as const;

/** `schema.table` with quotes removed and unquoted parts folded. */
export function auditTableName(name: string): string {
  const parts = name.match(/"(?:[^"]|"")*"|[^.]+/g) ?? [];

  const names = parts.map((part) =>
    part.startsWith('"')
      ? part.slice(1, -1).replaceAll('""', '"')
      : part.trim().toLowerCase(),
  );

  return names.length === 1 ? `public.${names[0]!}` : names.join(".");
}

interface ReadSettings {
  readonly settings: Readonly<Record<string, unknown>>;
  readonly deferred: boolean;
  readonly tenantPath: boolean;
}

/** The settings a row trigger or an `audit()` call carries, or why not. */
function settingsOf(text: string): ReadSettings | string {
  const deferred =
    /\bconstraint\s+trigger\b/i.test(text) || /\bdeferrable\b/i.test(text);

  const namedPath =
    /\btenant_path\s*=>\s*(?!null\b)\S/i.test(text) ||
    /\btenant_function\s*=>\s*(?!null\b)\S/i.test(text);

  const trigger = /audit_row_change\(\s*'((?:[^']|'')*)'/s.exec(text);

  if (trigger !== null) {
    try {
      const parsed: unknown = JSON.parse(trigger[1]!.replaceAll("''", "'"));

      if (
        typeof parsed !== "object" ||
        parsed === null ||
        Array.isArray(parsed)
      ) {
        return "its settings are not an object";
      }

      // SAFETY: the check above keeps only a plain object.
      const record = parsed as Record<string, unknown>;

      return {
        settings: record,
        deferred,
        tenantPath:
          namedPath ||
          (record["tenant_path"] !== undefined &&
            record["tenant_path"] !== null) ||
          (record["tenant_function"] !== undefined &&
            record["tenant_function"] !== null),
      };
    } catch {
      return "its settings are not JSON";
    }
  }

  const settings: Record<string, unknown> = { ignore: [], redact: [] };

  for (const key of NAMED) {
    const match = new RegExp(
      String.raw`\b${key}\s*=>\s*'((?:[^']|'')*)'`,
      "i",
    ).exec(text);

    if (match !== null) {
      settings[key] = match[1]!.replaceAll("''", "'");
    }
  }

  for (const key of ["ignore", "redact"] as const) {
    const list = new RegExp(
      String.raw`\b${key}\s*=>\s*'\{([^}]*)\}'`,
      "i",
    ).exec(text);

    if (list !== null) {
      settings[key] = list[1]!
        .split(",")
        .map((name) => name.trim().replace(/^"(.*)"$/, "$1"))
        .filter((name) => name !== "");
    } else if (new RegExp(String.raw`\b${key}\s*=>`, "i").test(text)) {
      return `its ${key} argument is not a '{...}' literal`;
    }
  }

  return { settings, deferred, tenantPath: namedPath };
}

/** The statement whose text is `trigger`, when the reader kept it. */
function statementFor(
  statements: readonly SqlStatement[],
  trigger: string,
): SqlStatement | undefined {
  const folded = trigger.replaceAll(/\s+/g, " ").trim();

  return statements.find(
    (statement) => statement.text.replaceAll(/\s+/g, " ").trim() === folded,
  );
}

interface Edit {
  readonly files: readonly PlannedFile[];
  readonly review: readonly { readonly message: string }[];
}

/**
 * Rewrites each named table's `bsb_audit` row trigger, or its `select
 * better_supabase.audit(...)` call, into the three static statement triggers. A
 * table without a primary key, or one that uses `deferred`, `tenant_path` or
 * `tenant_function`, is left as it is and named in `review`.
 */
export async function auditStatementEdits(
  sources: readonly { readonly path: string; readonly text: string }[],
  tables: readonly string[],
): Promise<Edit> {
  const wanted = new Set(tables.map(auditTableName));

  const schema = sources.filter(
    (file) => !/(?:^|[\\/])migrations[\\/]/.test(file.path),
  );

  await primeSchemaTexts(schema.map((file) => file.text));

  const keys = new Map<string, readonly string[]>();

  for (const file of schema) {
    for (const table of factsOf(file.text).tables) {
      if (table.primaryKey.length > 0) {
        keys.set(auditTableName(table.name), table.primaryKey);
      }
    }
  }

  const review: { message: string }[] = [];
  const found = new Set<string>();
  const files: PlannedFile[] = [];

  for (const file of schema) {
    const facts = factsOf(file.text);
    const statements = statementsOf(file.text);
    let next = file.text;

    const triggers = facts.triggers.filter(
      (trigger) =>
        wanted.has(auditTableName(trigger.table)) &&
        (trigger.name === "bsb_audit" || trigger.name === "bsb_audit_update") &&
        trigger.function.endsWith("audit_row_change"),
    );

    const calls = statements.filter((statement) => {
      const target = /better_supabase\.audit\s*\(\s*'((?:[^']|'')*)'/i.exec(
        statement.text,
      );

      return (
        target !== null &&
        wanted.has(auditTableName(target[1]!.replaceAll("''", "'")))
      );
    });

    const byTable = new Map<string, { text: string; update: boolean }[]>();

    for (const trigger of triggers) {
      const statement = statementFor(statements, trigger.text);
      const table = auditTableName(trigger.table);

      found.add(table);

      if (statement === undefined) {
        review.push({
          message: `${table} in ${file.path} could not be rewritten: the trigger statement was not found as written.`,
        });

        continue;
      }

      const list = byTable.get(table) ?? [];

      list.push({
        text: statement.text,
        update: trigger.name === "bsb_audit_update",
      });
      byTable.set(table, list);
    }

    for (const statement of calls) {
      const target = /better_supabase\.audit\s*\(\s*'((?:[^']|'')*)'/i.exec(
        statement.text,
      )!;

      const table = auditTableName(target[1]!.replaceAll("''", "'"));

      found.add(table);

      if (byTable.has(table)) {
        // The trigger is the registration the schema diff keeps. Drop the call.
        const from = `${statement.text};`;

        if (next.includes(from)) {
          next = next.replace(from, "");
        }

        continue;
      }

      const list = byTable.get(table) ?? [];

      list.push({ text: statement.text, update: false });
      byTable.set(table, list);
    }

    for (const [table, hits] of byTable) {
      const main = hits.find((hit) => !hit.update) ?? hits[0];

      if (main === undefined) {
        continue;
      }

      const read = settingsOf(main.text);

      if (typeof read === "string") {
        review.push({ message: `${table} was left on row triggers: ${read}.` });

        continue;
      }

      if (read.deferred) {
        review.push({
          message: `${table} audits with a deferred trigger, and statement mode does not combine with deferred.`,
        });

        continue;
      }

      if (read.tenantPath) {
        review.push({
          message: `${table} audits with tenant_path or tenant_function, and statement mode does not combine with either.`,
        });

        continue;
      }

      const key = keys.get(table);

      if (key === undefined || key.length === 0) {
        review.push({
          message: `${table} has no primary key in the schema files, and statement mode needs one.`,
        });

        continue;
      }

      const settings = {
        ...read.settings,
        ...(Array.isArray(read.settings["key_columns"])
          ? {}
          : { key_columns: [...key] }),
      };

      const created = auditStatementTriggers(table, settings);

      let wrote = false;

      for (const hit of hits) {
        const from = `${hit.text};`;

        if (!next.includes(from)) {
          review.push({
            message: `${table} in ${file.path} could not be rewritten: the statement was not found as written.`,
          });

          wrote = true;

          break;
        }

        next = next.replace(from, wrote || hit.update ? "" : created);
        wrote = true;
      }
    }

    if (next !== file.text) {
      files.push({ path: file.path, contents: next, policy: "edit" });
    }
  }

  for (const table of wanted) {
    if (
      !found.has(table) &&
      !review.some((line) => line.message.startsWith(`${table} `))
    ) {
      review.push({
        message: `${table} has no bsb_audit trigger and no better_supabase.audit() call in the schema files.`,
      });
    }
  }

  return { files, review };
}

/** The `audit-statement` codemod: static statement triggers for named tables. */
export function auditStatementCodemod(
  project: CodemodProject,
): Promise<{
  readonly files: readonly PlannedFile[];
  readonly review: readonly { readonly message: string }[];
}> {
  return auditStatementEdits(project.sql, project.tables ?? []);
}
