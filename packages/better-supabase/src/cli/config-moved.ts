import { CONFIG_GROUPS, RENAMED_CONFIG_KEYS } from "../config/index.ts";
import { isRecord } from "./guards.ts";

/** Where each top-level key of a 0.14 config moved in 0.15. */
const MOVED_KEYS: ReadonlyMap<string, string> = new Map([
  ...Object.entries(CONFIG_GROUPS).flatMap(([group, keys]) =>
    keys
      .filter((key) => key !== "tables")
      .map((key): [string, string] => [key, `${group}.${key}`]),
  ),
  ...RENAMED_CONFIG_KEYS.map(([grouped, flat]): [string, string] => [
    flat,
    grouped,
  ]),
]);

/** `sql` keys that moved before 0.15, with where they went. */
const MOVED_SQL_KEYS: readonly (readonly [string, string])[] = [
  [
    "modules",
    "moved to the top-level `blocks` key in 0.9; run `better-supabase codemod 0.9`",
  ],
  [
    "naming",
    "`sql.naming.tenant` moved to `blocks.memberships.names.organization`",
  ],
];

/** Moved `sql` keys in one config block, under `sql` or `database.sql`. */
function movedSqlIssues(prefix: string, block: unknown): string[] {
  if (!isRecord(block)) {
    return [];
  }

  const database = block["database"];

  const places: [string, unknown][] = [
    ["sql", block["sql"]],
    ["database.sql", isRecord(database) ? database["sql"] : undefined],
  ];

  return places.flatMap(([path, sql]) =>
    isRecord(sql)
      ? MOVED_SQL_KEYS.filter(([key]) => key in sql).map(
          ([key, message]) => `${prefix}${path}.${key}: ${message}`,
        )
      : [],
  );
}

const SCAFFOLD_REMOVED =
  "removed in 0.15 with `better-supabase scaffold api`; delete it. `defineApi` includes every table and block instance, and `createOrpc(betterSupabase).router(api)` serves it: https://bettersupabase.com/docs/frameworks/orpc#serve-the-api";

/** Top-level keys 0.15 removed, with what replaces them. */
const REMOVED_KEYS: ReadonlyMap<string, string> = new Map([
  [
    "plugins",
    "removed in 0.15: the updated-at, created-by, trash and memberships blocks carry these columns now; run `better-supabase codemod 0.15`",
  ],
  ["scaffold", SCAFFOLD_REMOVED],
]);

const RECORD_TYPES_MOVED =
  "renamed to `gen.recordTypes` in 0.15; run `better-supabase codemod 0.15`";

/** Keys of the flat 0.14 config in one config block. */
function movedGroupIssues(prefix: string, block: unknown): string[] {
  if (!isRecord(block)) {
    return [];
  }

  const gen = block["gen"];
  const tooling = block["tooling"];

  const genIssues =
    isRecord(gen) && "generateFeatures" in gen
      ? [`${prefix}gen.generateFeatures: ${RECORD_TYPES_MOVED}`]
      : [];

  const toolingIssues =
    isRecord(tooling) && "scaffold" in tooling
      ? [`${prefix}tooling.scaffold: ${SCAFFOLD_REMOVED}`]
      : [];

  return Object.keys(block).flatMap((key) => {
    if (key === "generateFeatures") {
      return [`${prefix}${key}: ${RECORD_TYPES_MOVED}`];
    }

    if (key === "gen") {
      return genIssues;
    }

    if (key === "tooling") {
      return toolingIssues;
    }

    const removed = REMOVED_KEYS.get(key);

    if (removed !== undefined) {
      return [`${prefix}${key}: ${removed}`];
    }

    const moved = MOVED_KEYS.get(key);

    return moved === undefined
      ? []
      : [
          `${prefix}${key}: moved to \`${moved}\` in 0.15; run \`better-supabase codemod 0.15\``,
        ];
  });
}

/**
 * Keys of the flat 0.14 config, and `sql` keys moved before it, in the config
 * or one of its environment blocks, each as `path: message`.
 */
export function movedKeyIssues(value: unknown): string[] {
  if (!isRecord(value)) {
    return [];
  }

  const blocks: [string, unknown][] = [["", value]];

  for (const [key, block] of Object.entries(value)) {
    if (key === "$env" && isRecord(block)) {
      for (const [name, env] of Object.entries(block)) {
        blocks.push([`$env.${name}.`, env]);
      }
    } else if (key.startsWith("$")) {
      blocks.push([`${key}.`, block]);
    }
  }

  return [
    ...blocks.flatMap(([prefix, block]) => movedSqlIssues(prefix, block)),
    ...blocks.flatMap(([prefix, block]) => movedGroupIssues(prefix, block)),
  ];
}
