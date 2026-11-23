import { isDeepStrictEqual } from "node:util";

import type { ResolvedConfig } from "../config/index.ts";
import type { Move } from "./codemod-table-tags.ts";

import { formatBsbComment } from "../sql/index.ts";
import { ConfigDocument } from "./config-document/index.ts";
import { withTableTags } from "./gen/table-tags.ts";
import { subjectTagArgs } from "./subject-tag.ts";

const PUBLIC = "public.";

const shortOf = (table: string): string =>
  table.startsWith(PUBLIC) ? table.slice(PUBLIC.length) : table;

/**
 * A table the tag readers can name: one in `public`, written with or without
 * the schema.
 */
const plain = (table: string): boolean => !shortOf(table).includes(".");

/** `config` with the table's facts removed, then read back through `line`. */
function tagged(
  config: ResolvedConfig,
  table: string,
  line: string,
  without: (config: ResolvedConfig) => ResolvedConfig,
): ResolvedConfig | undefined {
  try {
    return withTableTags(without(config), [
      { schema: "public", name: shortOf(table), comment: line },
    ]);
  } catch {
    return undefined;
  }
}

function realtimeMoves(config: ResolvedConfig): {
  moves: Move[];
  review: { message: string }[];
} {
  const moves: Move[] = [];
  const review: { message: string }[] = [];
  const { tables, global, users } = config.realtime;

  for (const [index, table] of tables.entries()) {
    if (!plain(table)) {
      review.push({
        message: `realtime.tables[${String(index)}] (${table}) stays in the config: the tag reads only tables in public.`,
      });
      continue;
    }

    const globalAt = global.findIndex(
      (each) => shortOf(each) === shortOf(table),
    );

    const userKey = Object.keys(users).find(
      (each) => shortOf(each) === shortOf(table),
    );

    const user = userKey === undefined ? undefined : users[userKey];
    const short = shortOf(table);

    const line = formatBsbComment({
      text: "",
      tags: [
        {
          name: "realtime",
          args: {
            ...(globalAt === -1 ? {} : { global: true as const }),
            ...(user === undefined ? {} : { user }),
          },
        },
      ],
    });

    moves.push({
      table: `public.${short}`,
      tag: "realtime",
      line,
      remove: {
        paths: [
          `realtime.tables[${String(index)}]`,
          ...(globalAt === -1 ? [] : [`realtime.global[${String(globalAt)}]`]),
          ...(userKey === undefined ? [] : [`realtime.users.${userKey}`]),
        ],
      },
      reaches: (current) => {
        const result = tagged(current, table, line, (each) => ({
          ...each,
          realtime: {
            ...each.realtime,
            tables: each.realtime.tables.filter(
              (name) => shortOf(name) !== short,
            ),
            global: each.realtime.global.filter(
              (name) => shortOf(name) !== short,
            ),
            users: Object.fromEntries(
              Object.entries(each.realtime.users).filter(
                ([name]) => shortOf(name) !== short,
              ),
            ),
          },
        }));

        return (
          result !== undefined &&
          result.realtime.tables.some((name) => shortOf(name) === short) &&
          result.realtime.global.some((name) => shortOf(name) === short) ===
            (globalAt !== -1) &&
          (result.realtime.users[short] ?? undefined) === user
        );
      },
    });
  }

  return { moves, review };
}

function vectorMoves(config: ResolvedConfig): {
  moves: Move[];
  review: { message: string }[];
} {
  const moves: Move[] = [];
  const review: { message: string }[] = [];

  for (const entry of config.vectorSearch) {
    const extra = Object.keys(entry).filter(
      (key) => !["table", "column", "distance"].includes(key),
    );

    if (
      !plain(entry.table) ||
      entry.table.startsWith(PUBLIC) ||
      extra.length > 0
    ) {
      review.push({
        message: `vectorSearch.${entry.table} stays in the config: ${
          extra.length > 0
            ? `${extra.join(", ")} has no word in the tag`
            : "the tag reads only tables in public, written without the schema"
        }.`,
      });
      continue;
    }

    const line = formatBsbComment({
      text: "",
      tags: [
        {
          name: "vector-search",
          args: { column: entry.column, distance: entry.distance },
        },
      ],
    });

    moves.push({
      table: `public.${entry.table}`,
      tag: "vector-search",
      line,
      remove: { path: `vectorSearch.${entry.table}` },
      reaches: (current) => {
        const result = tagged(current, entry.table, line, (each) => ({
          ...each,
          vectorSearch: each.vectorSearch.filter(
            (other) => other.table !== entry.table,
          ),
        }));

        return (
          result?.vectorSearch.some((other) =>
            isDeepStrictEqual(other, entry),
          ) === true
        );
      },
    });
  }

  return { moves, review };
}

function subjectMoves(
  config: ResolvedConfig,
  configText: string | undefined,
): { moves: Move[]; review: { message: string }[] } {
  const moves: Move[] = [];
  const review: { message: string }[] = [];

  if (configText === undefined) {
    return { moves, review };
  }

  const document = ConfigDocument.parse(configText);

  for (const [type, subject] of Object.entries(config.subjects)) {
    if (document.locate(["recordTypes", type]) === undefined) {
      continue;
    }

    const short = shortOf(subject.table);

    const args = plain(subject.table)
      ? subjectTagArgs(type, subject, short)
      : undefined;

    if (args === undefined) {
      review.push({
        message: `recordTypes.${type} stays in the config: the subject tag has no word for one of its options, or the table is outside public.`,
      });
      continue;
    }

    const line = formatBsbComment({
      text: "",
      tags: [{ name: "subject", args }],
    });

    moves.push({
      table: `public.${short}`,
      tag: "subject",
      line,
      remove: { path: `recordTypes.${type}` },
      reaches: (current) => {
        const { [type]: _own, ...others } = current.subjects;

        const result = tagged(current, short, line, (each) => ({
          ...each,
          subjects: others,
        }));

        return isDeepStrictEqual(result?.subjects[type], subject);
      },
    });
  }

  return { moves, review };
}

/**
 * The `subject`, `realtime` and `vector-search` entries of the config, as tag
 * moves.
 */
export function featureMoves(
  config: ResolvedConfig,
  configText: string | undefined,
): { moves: Move[]; review: { message: string }[] } {
  const parts = [
    subjectMoves(config, configText),
    realtimeMoves(config),
    vectorMoves(config),
  ];

  return {
    moves: parts.flatMap((part) => part.moves),
    review: parts.flatMap((part) => part.review),
  };
}

const BROADCAST_TRIGGER =
  /create\s+(?:or\s+replace\s+)?trigger\s+("?[\w]+"?)[^;]*?\bon\s+([\w."]+)[^;]*?execute\s+(?:function|procedure)\s+better_supabase\.broadcast_topic\s*\(/giu;

/**
 * A review line for each trigger the app's schema files write by hand that
 * calls `better_supabase.broadcast_topic()`. `realtime.triggers` declares the
 * same trigger, and `upgrade` writes it, so the hand-written one is a second
 * copy that the codemod does not remove.
 */
export function broadcastTriggerReview(
  files: readonly { readonly path: string; readonly text: string }[],
): { message: string }[] {
  return files
    .filter((file) => !/[\\/]migrations[\\/]/u.test(file.path))
    .flatMap((file) =>
      [...file.text.matchAll(BROADCAST_TRIGGER)].map((match) => ({
        message: `${file.path}: trigger ${match[1] ?? ""} on ${match[2] ?? ""} calls better_supabase.broadcast_topic(); declare it in realtime.triggers and drop the hand-written trigger, then run upgrade.`,
      })),
    );
}
