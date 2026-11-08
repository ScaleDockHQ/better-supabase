import type { ResolvedConfig } from "../config/index.ts";
import type { Codemod, CodemodProject } from "./codemod.ts";
import type { PlannedFile } from "./core/files.ts";

import { redundantNulls } from "../sql/index.ts";
import { codeRanges } from "./code-ranges.ts";
import { ownLayout } from "./sql-layout.ts";

/**
 * The config options the `config` codemod never edits (ADR 0324): each states a
 * choice the schema can't imply, such as a remap, a reserved slug, a bound or
 * an exemption. The codemod only removes `columns` entries, so a test keeps
 * this list in step with what it leaves alone, in both config shapes.
 */
export const PROTECTED_OPTIONS: readonly string[] = [
  "names",
  "functions",
  "permissions",
  "reservedSlugs",
  "slugPattern",
  "slugMinLength",
  "slugMaxLength",
  "onAccept",
  "previewColumns",
  "roles",
  "restricted",
  "ipHeader",
  "staffClaim",
  "subjectColumns",
  "exempt",
  "attachments",
  "api",
  "ownTablePolicies",
  "tenantColumn",
  "powersync",
  "sources",
];

/** A `blocks.<block>.columns.<table>.<column>` entry the render refuses. */
export interface ColumnEntry {
  readonly block: string;
  readonly table: string;
  readonly column: string;
  readonly why: string;
}

/** The `columns.<table>.tenant` entries that repeat `sql.tenantColumn`. */
export function tenantEntries(
  config: Pick<ResolvedConfig, "blocks" | "sql">,
): ColumnEntry[] {
  const tenant = config.sql.tenantColumn;

  if (tenant === undefined) {
    return [];
  }

  return Object.entries(config.blocks).flatMap(([block, entry]) =>
    Object.entries(entry?.columns ?? {}).flatMap(([table, columns]) =>
      columns?.["tenant"] === tenant
        ? [
            {
              block,
              table,
              column: "tenant",
              why: `repeats sql.tenantColumn "${tenant}"`,
            },
          ]
        : [],
    ),
  );
}

/**
 * The index of the `}` that closes the `{` at `open`, skipping strings and
 * comments.
 */
function closing(
  text: string,
  open: number,
  code: (index: number) => boolean,
): number {
  let depth = 0;

  for (let at = open; at < text.length; at += 1) {
    if (!code(at)) {
      continue;
    }

    depth += text[at] === "{" ? 1 : text[at] === "}" ? -1 : 0;

    if (depth === 0) {
      return at;
    }
  }

  return -1;
}

/**
 * `text` without the `<column>: ...` property of each entry, found under
 * `<block>: { columns: { <table>: { ... } } }`, with its comma and its line.
 * Only code counts: a name in a string or a comment stays.
 */
export function withoutColumnEntries(
  text: string,
  entries: readonly ColumnEntry[],
): string {
  let out = text;

  for (const entry of entries) {
    const ranges = codeRanges(out);

    const code = (index: number): boolean =>
      ranges.some(([start, end]) => index >= start && index < end);

    const block = new RegExp(
      `(?:^|[\\s,{])(?:"${entry.block}"|${entry.block})\\s*:\\s*\\{`,
      "g",
    );

    for (const found of out.matchAll(block)) {
      const open = found.index + found[0].length - 1;

      if (!code(open)) {
        continue;
      }

      const end = closing(out, open, code);
      const body = out.slice(open, end + 1);
      const columns = /\bcolumns\s*:\s*\{/.exec(body);

      if (columns === null) {
        continue;
      }

      const tables = open + columns.index + columns[0].length - 1;

      const tablesEnd = closing(out, tables, code);
      const inner = out.slice(tables, tablesEnd + 1);
      const table = new RegExp(`\\b${entry.table}\\s*:\\s*\\{`).exec(inner);

      if (table === null) {
        continue;
      }

      const tableOpen = tables + table.index + table[0].length - 1;
      const tableEnd = closing(out, tableOpen, code);
      const rows = out.slice(tableOpen, tableEnd + 1);

      const value = String.raw`(?:null|"[^"]*"|'[^']*')`;

      const property =
        new RegExp(
          String.raw`^[ \t]*${entry.column}\s*:\s*${value}\s*,?[ \t]*\n`,
          "m",
        ).exec(rows) ??
        new RegExp(String.raw`\b${entry.column}\s*:\s*${value}\s*,[ \t]*`).exec(
          rows,
        ) ??
        new RegExp(
          String.raw`\s*,\s*\b${entry.column}\s*:\s*${value}(?=\s*\})`,
        ).exec(rows) ??
        new RegExp(
          String.raw`\s*\b${entry.column}\s*:\s*${value}\s*(?=\})`,
        ).exec(rows);

      if (property === null) {
        continue;
      }

      const from = tableOpen + property.index;

      out = out.slice(0, from) + out.slice(from + property[0].length);
      break;
    }
  }

  return out;
}

/** The files that drop the config entries the render refuses. */
export function configFiles(
  entries: readonly ColumnEntry[],
  config: { readonly path: string; readonly text: string },
): readonly PlannedFile[] {
  const text = withoutColumnEntries(config.text, entries);

  return text === config.text
    ? []
    : [{ path: config.path, contents: text, policy: "edit" }];
}

/** The `config` codemod: drop the entries the catalog already implies. */
export function configCodemod(): Codemod {
  return {
    name: "config",
    description:
      "Remove the columns entries the render refuses: a null for a column the view lacks and a tenant that repeats sql.tenantColumn",
    project: async (project: CodemodProject) => {
      const { config } = project;

      let own: Awaited<ReturnType<typeof ownLayout>> | undefined;

      try {
        own = await ownLayout(config);
      } catch {
        // Without the project's tables only the static entries are found.
      }

      const nulls: ColumnEntry[] = [];

      for (const entry of redundantNulls({ modules: config.blocks, ...own })) {
        nulls.push({
          block: entry.block,
          table: entry.logical,
          column: entry.column,
          why: `${entry.view} has no "${entry.name}" column`,
        });
      }

      const entries = [...tenantEntries(config), ...nulls];

      if (project.configFile === undefined || entries.length === 0) {
        return {
          files: [],
          review: entries.map((entry) => ({
            message: `blocks.${entry.block}.columns.${entry.table}.${entry.column}: ${entry.why}; remove it from the config.`,
          })),
        };
      }

      return {
        files: configFiles(entries, {
          path: project.configFile,
          text: project.configText ?? "",
        }),
        review: [],
      };
    },
  };
}
