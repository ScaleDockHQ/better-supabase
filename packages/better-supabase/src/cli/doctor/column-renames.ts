import type { ResolvedConfig } from "../../config/index.ts";
import type { FindingInput, TextFile } from "./rules.ts";

import { SQL_MODULES } from "../../sql/index.ts";
import { NAMING_RENAMES } from "../codemod-naming.ts";
import { writtenByBlocks } from "../sql-layout.ts";

const ADD_COLUMN =
  /\balter\s+table\s+(?:if\s+exists\s+)?(?:only\s+)?((?:"?[\w$]+"?\s*\.\s*)?"?[\w$]+"?)\s+add\s+column\s+if\s+not\s+exists\s+("?[\w$]+"?)/gi;

const unquote = (value: string): string => value.replaceAll('"', "");

const qualified = (value: string): string => {
  const parts = value.split(".").map((part) => unquote(part.trim()));

  return parts.length === 1 ? `public.${parts[0]}` : parts.join(".");
};

/**
 * A `*.block-columns.sql` line that adds a column the config already pins to an
 * older name (BS625). The new column would sit beside the one the app has.
 */
export function shadowedBlockColumns(
  config: ResolvedConfig,
  files: readonly Pick<TextFile, "path" | "text">[],
): FindingInput[] {
  const added: { table: string; column: string }[] = [];

  for (const file of files) {
    if (!file.path.endsWith(".block-columns.sql")) {
      continue;
    }

    for (const match of file.text.matchAll(ADD_COLUMN)) {
      const table = match[1];
      const column = match[2];

      if (table !== undefined && column !== undefined) {
        added.push({ table: qualified(table), column: unquote(column) });
      }
    }
  }

  if (added.length === 0) {
    return [];
  }

  const schema = config.sql.blockDefaults?.schema ?? "better_supabase";
  const findings: FindingInput[] = [];

  const consider = (
    key: string,
    module: string,
    block: {
      readonly schema?: string | undefined;
      readonly tables?:
        | Readonly<Record<string, string | null | undefined>>
        | undefined;
      readonly columns?:
        | Readonly<
            Record<
              string,
              Readonly<Record<string, string | null | undefined>> | undefined
            >
          >
        | undefined;
    },
  ): void => {
    const names = SQL_MODULES[module]?.names;

    if (names === undefined) {
      return;
    }

    const blockSchema = block.schema ?? schema;

    for (const [logical, columns] of Object.entries(block.columns ?? {})) {
      const spec = names.tables[logical];

      if (spec === undefined || columns === undefined) {
        continue;
      }

      const mapped = block.tables?.[logical];

      const physical =
        typeof mapped === "string"
          ? mapped.includes(".")
            ? mapped
            : `${blockSchema}.${mapped}`
          : `${blockSchema}.${spec.name}`;

      for (const [logicalColumn, name] of Object.entries(columns)) {
        if (typeof name !== "string") {
          continue;
        }

        const standard = spec.columns[logicalColumn];

        if (standard === undefined || standard === name) {
          continue;
        }

        if (
          added.some(
            (entry) => entry.table === physical && entry.column === standard,
          )
        ) {
          findings.push({
            message: `${physical}.block-columns.sql adds ${standard}, and blocks.${key}.columns.${logical}.${logicalColumn} keeps the old name "${name}". Drop the add column, or the table gains both.`,
            target: `${physical}.${standard}`,
          });
        }
      }
    }
  };

  for (const [name, block] of Object.entries(config.blocks)) {
    if (block !== undefined) {
      consider(name, name, block);
    }
  }

  for (const instance of Object.values(config.instances)) {
    consider(instance.name, instance.block, instance.config);
  }

  return findings;
}

const AUDIT_CALL = /better_supabase\.audit\s*\(\s*'([^']*)'([\s\S]*?)\)\s*;/gi;

const ARRAY_ARG = /(ignore|redact)\s*=>\s*'\{([^}]*)\}'/gi;

const AUDIT_TRIGGER =
  /\btrigger\s[^;]*?\bon\s+((?:"?[\w$]+"?\s*\.\s*)?"?[\w$]+"?)[^;]*?\baudit_row_change\s*\(\s*'([^']*)'/gi;

/** The `ignore` and `redact` lists of an `audit_row_change` trigger argument. */
function triggerLists(json: string): [kind: string, names: string[]][] {
  let parsed: unknown;

  try {
    parsed = JSON.parse(json);
  } catch {
    return [];
  }

  if (typeof parsed !== "object" || parsed === null) {
    return [];
  }

  return (["ignore", "redact"] as const).map((kind) => {
    // SAFETY: `parsed` is a non-null object, checked above.
    const list: unknown = (parsed as Record<string, unknown>)[kind];

    return [
      kind,
      Array.isArray(list)
        ? list.filter((name): name is string => typeof name === "string")
        : [],
    ];
  });
}

/**
 * Old column names still passed to `audit` `ignore` or `redact`, and old `->>
 * '...'` keys in the app's own SQL (BS626). Block files are skipped: `upgrade`
 * rewrites those.
 */
export function staleRenameKeys(
  files: readonly Pick<TextFile, "path" | "text">[],
): FindingInput[] {
  const columns = NAMING_RENAMES.filter((rename) => rename.kind === "column");
  const findings: FindingInput[] = [];

  for (const file of files) {
    if (
      !file.path.endsWith(".sql") ||
      file.path.includes("migrations/") ||
      writtenByBlocks(file)
    ) {
      continue;
    }

    const lists: [table: string, kind: string, names: string[]][] = [];

    for (const match of file.text.matchAll(AUDIT_CALL)) {
      const table = (match[1] ?? "").replaceAll('"', "");

      for (const arg of (match[2] ?? "").matchAll(ARRAY_ARG)) {
        lists.push([
          table,
          arg[1] ?? "ignore",
          (arg[2] ?? "").split(",").map((part) => part.trim()),
        ]);
      }
    }

    for (const match of file.text.matchAll(AUDIT_TRIGGER)) {
      const table = (match[1] ?? "").replaceAll(/["\s]/g, "");

      for (const [kind, names] of triggerLists(match[2] ?? "")) {
        lists.push([table, kind, names]);
      }
    }

    for (const [table, kind, names] of lists) {
      for (const name of names) {
        const rename = columns.find(
          (candidate) =>
            candidate.from === name &&
            (candidate.table === table ||
              candidate.table?.endsWith(`.${table}`) === true ||
              table.endsWith(`.${candidate.table?.split(".").at(-1)}`)),
        );

        if (rename !== undefined) {
          findings.push({
            message: `${file.path} passes "${name}" to audit ${kind} for ${table}. 0.58 names that column "${rename.to}".`,
            target: `${file.path}:${name}`,
          });
        }
      }
    }

    for (const match of file.text.matchAll(/->>\s*'([^']+)'/g)) {
      const name = match[1];

      if (name === undefined || name === "organization_id") {
        continue;
      }

      const rename = columns.find((candidate) => candidate.from === name);

      if (rename !== undefined) {
        findings.push({
          message: `${file.path} reads ->> '${name}'. 0.58 names that column "${rename.to}".`,
          target: `${file.path}:${name}`,
        });
      }
    }
  }

  return findings;
}
