import type { Codemod, CodemodProject } from "./codemod.ts";
import type { PlannedFile } from "./core/files.ts";

import { withTableTag } from "./codemod-extra-columns.ts";
import { withoutConfigPaths } from "./codemod-prune.ts";
import { declarationsOfText, primeSchemaFacts } from "./sql-facts.ts";

/** One table fact the config holds, as the tag line that replaces it. */
interface Move {
  readonly table: string;
  readonly tag: string;
  readonly line: string;
  /** The config path to drop, or the audit entry to cut from the list. */
  readonly remove:
    | { readonly path: string; readonly alt?: string }
    | { readonly exempt: string };
}

const isRecord = (item: unknown): item is Record<string, unknown> =>
  typeof item === "object" && item !== null && !Array.isArray(item);

const WORD = /^[\w.-]+$/u;

const value = (text: string): string =>
  WORD.test(text) ? text : `"${text.replaceAll('"', String.raw`\"`)}"`;

const ALL = ["select", "insert", "update", "delete"];

const tableOf = (key: string): string =>
  key.includes(".") ? key : `public.${key}`;

/** The config's table facts that a comment can hold, as tag lines. */
export function tableFactMoves(config: CodemodProject["config"]): {
  readonly moves: readonly Move[];
  readonly review: readonly { readonly message: string }[];
} {
  const moves: Move[] = [];
  const review: { message: string }[] = [];

  const exempt: unknown = config.blocks["audit"]?.options?.["exempt"];

  for (const entry of Array.isArray(exempt) ? exempt : []) {
    const table: unknown = isRecord(entry) ? entry["table"] : entry;
    const reason: unknown = isRecord(entry) ? entry["reason"] : undefined;

    if (
      typeof table !== "string" ||
      table.includes("*") ||
      !table.includes(".")
    ) {
      continue;
    }

    moves.push({
      table,
      tag: "audit-exempt",
      line:
        typeof reason === "string" && reason.trim() !== ""
          ? `@bsb audit-exempt reason=${value(reason.trim())}`
          : "@bsb audit-exempt",
      remove: { exempt: table },
    });
  }

  const tables: unknown = config.blocks["data-lifecycle"]?.options?.["tables"];

  if (isRecord(tables)) {
    for (const [key, entry] of Object.entries(tables)) {
      const path = `blocks.data-lifecycle.options.tables.${key}`;

      if (
        key.split(".").length > 1 ||
        !isRecord(entry) ||
        Object.keys(entry).some(
          (name) =>
            !["user", "tenant", "export", "purge", "omit"].includes(name),
        )
      ) {
        review.push({
          message: `${path} stays in the config: it is not a plain public table with user, tenant, export, purge or omit.`,
        });
        continue;
      }

      const parts = Object.entries(entry).flatMap(([name, item]): string[] => {
        if (Array.isArray(item)) {
          return [`${name}=${value(item.join(","))}`];
        }

        return typeof item === "string" || typeof item === "boolean"
          ? [`${name}=${value(String(item))}`]
          : [];
      });

      moves.push({
        table: tableOf(key),
        tag: "data-lifecycle",
        line: `@bsb data-lifecycle ${parts.join(" ")}`.trimEnd(),
        remove: { path },
      });
    }
  }

  for (const [key, grants] of Object.entries(config.expose)) {
    if (key.includes(".")) {
      review.push({
        message: `expose.${key} stays in the config: the codemod cannot cut a dotted key from the file.`,
      });
      continue;
    }

    const roles = [
      ["anon", grants.anon],
      ["authenticated", grants.authenticated],
      [
        "service-role",
        grants.serviceRole.length === ALL.length &&
        ALL.every((privilege) =>
          grants.serviceRole.some((granted) => granted === privilege),
        )
          ? []
          : grants.serviceRole,
      ],
    ] as const;

    const parts = roles
      .filter(([, privileges]) => privileges.length > 0)
      .map(([role, privileges]) => `${role}=${value(privileges.join(","))}`);

    moves.push({
      table: tableOf(key),
      tag: "grant",
      line: `@bsb grant ${parts.join(" ")}`.trimEnd(),
      remove: { path: `database.expose.${key}`, alt: `expose.${key}` },
    });
  }

  return { moves, review };
}

/** `text` without the `exempt` list element for `table`, or undefined. */
export function withoutExemptEntry(
  text: string,
  table: string,
): string | undefined {
  const list = /\bexempt\s*:\s*\[/u.exec(text);

  if (list === null) {
    return undefined;
  }

  const open = list.index + list[0].length - 1;
  let depth = 0;
  let close = -1;

  for (let at = open; at < text.length; at += 1) {
    depth += text[at] === "[" ? 1 : text[at] === "]" ? -1 : 0;

    if (depth === 0) {
      close = at;
      break;
    }
  }

  if (close === -1) {
    return undefined;
  }

  const escaped = table.replaceAll(/[.*+?^${}()|[\]\\]/gu, String.raw`\$&`);

  const quoted = (group: number): string =>
    `(["'])${escaped}\\${String(group)}`;

  const element = new RegExp(
    String.raw`[ \t]*(?:\{[^{}]*\btable\s*:\s*${quoted(1)}[^{}]*\}|${quoted(2)})[ \t]*,?[ \t]*\n?`,
    "u",
  );

  const body = text.slice(open + 1, close);
  const next = body.replace(element, "");

  return next === body
    ? undefined
    : text.slice(0, open + 1) + next + text.slice(close);
}

/**
 * The files that move the config's audit exemptions, `data-lifecycle` tables
 * and `expose` entries into `comment on table` tags, and drop the entries.
 */
export function tableTagFiles(project: CodemodProject): {
  readonly files: readonly PlannedFile[];
  readonly review: readonly { readonly message: string }[];
} {
  const { moves, review } = tableFactMoves(project.config);
  const edited = new Map<string, string>();
  const moved: Move[] = [];
  const out = [...review];

  for (const move of moves) {
    const creator = project.sql.find(
      (file) =>
        !/[\\/]migrations[\\/]/u.test(file.path) &&
        declarationsOfText(file.text).creates.some(
          (each) => each.table === move.table,
        ),
    );

    if (creator === undefined) {
      out.push({
        message: `${move.table}: no schema file creates the table, so its ${move.tag} stays in the config.`,
      });
      continue;
    }

    const current = edited.get(creator.path) ?? creator.text;

    if (new RegExp(String.raw`@bsb[^']*\b${move.tag}\b`, "u").test(current)) {
      out.push({
        message: `${move.table}: a comment already holds ${move.tag}; remove the config entry by hand.`,
      });
      continue;
    }

    edited.set(creator.path, withTableTag(current, move.table, move.line));
    moved.push(move);
  }

  const files: PlannedFile[] = [...edited].map(([path, contents]) => ({
    path,
    contents,
    policy: "edit",
  }));

  if (project.configFile !== undefined && project.configText !== undefined) {
    let text = project.configText;

    const missed: string[] = [];

    for (const move of moved) {
      if (!("path" in move.remove)) {
        continue;
      }

      let cut = withoutConfigPaths(text, [move.remove.path]);

      if (cut.missed.length > 0 && move.remove.alt !== undefined) {
        cut = withoutConfigPaths(text, [move.remove.alt]);
      }

      text = cut.text;
      missed.push(...cut.missed);
    }

    for (const path of missed) {
      out.push({
        message: `${path} moved to a comment, but the codemod could not find it in ${project.configFile}; remove it by hand.`,
      });
    }

    for (const move of moved) {
      if ("exempt" in move.remove) {
        const next = withoutExemptEntry(text, move.remove.exempt);

        if (next === undefined) {
          out.push({
            message: `${move.table} moved to a comment, but the codemod could not find its exempt entry in ${project.configFile}; remove it by hand.`,
          });
        } else {
          text = next;
        }
      }
    }

    if (text !== project.configText) {
      files.push({ path: project.configFile, contents: text, policy: "edit" });
    }
  } else if (moved.length > 0) {
    out.push({
      message: "No config file was found; remove the moved entries by hand.",
    });
  }

  return { files, review: out };
}

/** The `table-tags` codemod: move table facts from the config into comments. */
export function tableTagsCodemod(): Codemod {
  return {
    name: "table-tags",
    description:
      "Move audit exemptions, data-lifecycle tables and expose entries into comment on table tags",
    project: async (project: CodemodProject) => {
      // A pgTAP file with psql commands (\gset) does not parse; it is skipped and reported.
      const unread = await primeSchemaFacts(project.sql, project.config.root, {
        lenient: true,
      });

      const result = tableTagFiles(project);

      return {
        ...result,
        review: [
          ...result.review,
          ...unread.map((error) => ({
            message: `${error.path}:${String(error.line)}: ${error.message}; the codemod did not read this file.`,
          })),
        ],
      };
    },
  };
}
