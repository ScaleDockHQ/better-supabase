import { isDeepStrictEqual } from "node:util";

import type { ResolvedConfig } from "../config/index.ts";
import type { Codemod, CodemodProject } from "./codemod.ts";
import type { PlannedFile } from "./core/files.ts";

import { withTableTag } from "./codemod-extra-columns.ts";
import {
  broadcastTriggerReview,
  featureMoves,
} from "./codemod-feature-tags.ts";
import { withoutConfigPaths } from "./codemod-prune.ts";
import { projectSameTenantMoves } from "./codemod-same-tenant.ts";
import { withTableTags } from "./gen/table-tags.ts";
import { factsOf } from "./schema-reader/index.ts";
import { declarationsOfText, primeSchemaFacts } from "./sql-facts.ts";

/** One table fact the config holds, as the tag line that replaces it. */
export interface Move {
  readonly table: string;
  readonly tag: string;
  readonly line: string;
  /** The config path to drop, or the audit entry to cut from the list. */
  readonly remove:
    | { readonly path: string; readonly alt?: string }
    | { readonly paths: readonly string[] }
    | { readonly exempt: string };
  /**
   * Where the tag reaches. `doctor` means only doctor reads it. A function
   * answers whether the tag, read the way `gen` and the render read it, gives
   * the value the config entry holds.
   */
  readonly reaches: "doctor" | ((config: ResolvedConfig) => boolean);
}

/** The config with its own entry for `key` left out, as the tag would find it. */
function lifecycleReaches(
  key: string,
  entry: unknown,
  line: string,
): (config: ResolvedConfig) => boolean {
  return (config) => {
    const current = config.blocks["data-lifecycle"];
    const tables: unknown = current?.options?.["tables"];

    const others = isRecord(tables)
      ? Object.fromEntries(
          Object.entries(tables).filter(([each]) => each !== key),
        )
      : {};

    const bare: ResolvedConfig = {
      ...config,
      blocks: {
        ...config.blocks,
        "data-lifecycle": {
          ...current,
          options: { ...current?.options, tables: others },
        },
      },
    };

    const tagged = withTableTags(bare, [
      { schema: "public", name: key, comment: line },
    ]).blocks["data-lifecycle"]?.options?.["tables"];

    return isRecord(tagged) && isDeepStrictEqual(tagged[key], entry);
  };
}

function grantReaches(
  key: string,
  line: string,
): (config: ResolvedConfig) => boolean {
  return (config) => {
    const { [key]: entry, ...others } = config.expose;

    const tagged = withTableTags({ ...config, expose: others }, [
      { schema: "public", name: key, comment: line },
    ]);

    return isDeepStrictEqual(tagged.expose[key], entry);
  };
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
      reaches: "doctor",
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

      const line = `@bsb data-lifecycle ${parts.join(" ")}`.trimEnd();

      moves.push({
        table: tableOf(key),
        tag: "data-lifecycle",
        line,
        remove: { path },
        reaches: lifecycleReaches(key, entry, line),
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

    const line = `@bsb grant ${parts.join(" ")}`.trimEnd();

    moves.push({
      table: tableOf(key),
      tag: "grant",
      line,
      remove: { path: `database.expose.${key}`, alt: `expose.${key}` },
      reaches: grantReaches(key, line),
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
export async function tableTagFiles(project: CodemodProject): Promise<{
  readonly files: readonly PlannedFile[];
  readonly review: readonly { readonly message: string }[];
  /** One line per entry that moves: the tag, and where it reaches. */
  readonly explain: readonly string[];
}> {
  const facts = tableFactMoves(project.config);
  const features = featureMoves(project.config, project.configText);
  const moves = [...facts.moves, ...features.moves];

  const review = [
    ...facts.review,
    ...features.review,
    ...broadcastTriggerReview(project.sql),
  ];

  const edited = new Map<string, string>();
  const moved: Move[] = [];
  const out = [...review];

  for (const move of moves) {
    if (move.reaches !== "doctor" && !move.reaches(project.config)) {
      out.push({
        message: `${move.table}: the ${move.tag} tag would not give the config's value in the render, so the entry stays in the config.`,
      });
      continue;
    }

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

    await primeSchemaFacts(
      [{ path: creator.path, text: current }],
      project.config.root,
      { lenient: true },
    );

    if (
      factsOf(current).comments.some(
        (comment) =>
          comment.target === "table" &&
          comment.name === move.table &&
          new RegExp(String.raw`@bsb[\s\S]*\b${move.tag}\b`, "u").test(
            comment.text,
          ),
      )
    ) {
      out.push({
        message: `${move.table}: a comment already holds ${move.tag}; remove the config entry by hand.`,
      });
      continue;
    }

    edited.set(
      creator.path,
      await withTableTag(current, project.config.root, move.table, move.line),
    );
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

    // Removing a list element moves the ones after it up, so each index drops
    // by the number of earlier elements already cut from the same list.
    const cutFrom = new Map<string, number[]>();

    const shifted = (path: string): string => {
      const match = /^(.*)\[(\d+)\]$/u.exec(path);

      if (match?.[1] === undefined || match[2] === undefined) {
        return path;
      }

      const index = Number(match[2]);
      const before = cutFrom.get(match[1]) ?? [];

      cutFrom.set(match[1], [...before, index]);

      return `${match[1]}[${String(index - before.filter((each) => each < index).length)}]`;
    };

    for (const move of moved) {
      if (!("path" in move.remove || "paths" in move.remove)) {
        continue;
      }

      let cut =
        "paths" in move.remove
          ? withoutConfigPaths(text, move.remove.paths.map(shifted))
          : withoutConfigPaths(text, [move.remove.path]);

      if (
        "path" in move.remove &&
        cut.missed.length > 0 &&
        move.remove.alt !== undefined
      ) {
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

  const explain = moved.map(
    (move) =>
      `${move.table}: ${move.line} replaces its config entry. ${
        move.reaches === "doctor"
          ? "Only doctor reads this tag; the render does not change."
          : "The config read through the tag gives the same value, so the render stays the same."
      }`,
  );

  return { files, review: out, explain };
}

/** The `table-tags` codemod: move table facts from the config into comments. */
export function tableTagsCodemod(): Codemod {
  return {
    name: "table-tags",
    description:
      "Move audit exemptions, data-lifecycle tables, expose entries, record types, realtime tables, vector search entries and same-tenant entries into comment tags",
    project: async (project: CodemodProject) => {
      // A pgTAP file with psql commands (\gset) does not parse; it is skipped and reported.
      const unread = await primeSchemaFacts(project.sql, project.config.root, {
        lenient: true,
      });

      const result = await tableTagFiles(project);

      // The same-tenant step reads the files and the config the first step
      // wrote, so a table tag and a column tag land in the same text.
      const written = new Map(result.files.map((file) => [file.path, file]));

      const sameTenant = await projectSameTenantMoves({
        ...project,
        sql: project.sql.map((file) => ({
          ...file,
          text: written.get(file.path)?.contents ?? file.text,
        })),
        ...(project.configFile === undefined
          ? {}
          : {
              configText:
                written.get(project.configFile)?.contents ?? project.configText,
            }),
      });

      for (const file of sameTenant.files) {
        written.set(file.path, file);
      }

      if (project.explain === true) {
        return {
          files: [],
          review: [
            ...result.explain.map((message) => ({
              message: `explain: ${message}`,
            })),
            ...(sameTenant.moved === 0
              ? []
              : [
                  {
                    message: `explain: ${String(sameTenant.moved)} sameTenant entries move into @bsb same-tenant column tags; each renders the same trigger statement.`,
                  },
                ]),
            ...result.review,
            ...sameTenant.review,
          ],
        };
      }

      return {
        files: [...written.values()],
        review: [
          ...result.review,
          ...sameTenant.review,
          ...unread.map((error) => ({
            message: `${error.path}:${String(error.line)}: ${error.message}; the codemod did not read this file.`,
          })),
        ],
      };
    },
  };
}
