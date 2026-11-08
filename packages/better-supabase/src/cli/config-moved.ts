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

const TABLES_REMOVED =
  "removed in 0.28: tables are SQL in `supabase/schemas` with `@bsb` tags in the table comment; run `better-supabase migrate schema-first`";

/** `sql` keys that moved before 0.15, with where they went. */
const MOVED_SQL_KEYS: readonly (readonly [string, string])[] = [
  [
    "modules",
    "moved to the top-level `blocks` key in 0.9; upgrade to 0.53 with that release first",
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
    "removed in 0.15: the updated-at, created-by, trash and memberships blocks carry these columns now; upgrade to 0.53 with that release first",
  ],
  ["scaffold", SCAFFOLD_REMOVED],
  ["tables", TABLES_REMOVED],
  ["appTables", TABLES_REMOVED],
  [
    "records",
    "renamed to `recordTypes` (it was `subjects` before 0.54); rename the key. A table's subject now comes from `@bsb subject` in its comment",
  ],
]);

/**
 * Config keys renamed with ADR 0386, as `path` (dots) and the key that replaces
 * it. They have no alias, so a config that still has one is refused.
 */
const RENAMED_INPUT_KEYS: readonly (readonly [path: string, to: string])[] = [
  ["subjects", "recordTypes"],
  ["integrations", "adapters"],
  ["organization", "auth.tenant"],
  ["gen.output", "gen.file"],
  ["gen.recordTypes", "gen.records"],
  ["database.seed.output", "database.seed.file"],
  ["database.seed.sample.output", "database.seed.sample.file"],
  ["database.realtime.policies.output", "database.realtime.policies.file"],
  ["tooling.env.output", "tooling.env.file"],
  ["tooling.keys.output", "tooling.keys.file"],
  ["tooling.doctor.output", "tooling.doctor.file"],
];

/** The value at a dotted `path` of `block`, and whether every step exists. */
function hasPath(block: unknown, path: string): boolean {
  let at: unknown = block;

  for (const key of path.split(".")) {
    if (!isRecord(at) || !(key in at)) {
      return false;
    }

    at = at[key];
  }

  return true;
}

/** `api.specs.outputs[].output` of one config block. */
function specOutputIssues(prefix: string, block: unknown): string[] {
  const api = isRecord(block) ? block["api"] : undefined;
  const specs = isRecord(api) ? api["specs"] : undefined;
  const outputs = isRecord(specs) ? specs["outputs"] : undefined;

  return Array.isArray(outputs)
    ? outputs.flatMap((entry: unknown, index: number) =>
        isRecord(entry) && "output" in entry
          ? [
              `${prefix}api.specs.outputs.${String(index)}.output: renamed to \`file\` in 0.54; rename the key`,
            ]
          : [],
      )
    : [];
}

/** Keys of one config block that ADR 0386 renamed. */
function renamedInputIssues(prefix: string, block: unknown): string[] {
  return [
    ...RENAMED_INPUT_KEYS.filter(([path]) => hasPath(block, path)).map(
      ([path, to]) =>
        `${prefix}${path}: renamed to \`${to}\` in 0.54; rename the key, or run \`better-supabase codemod naming\``,
    ),
    ...specOutputIssues(prefix, block),
  ];
}

const RECORD_TYPES_MOVED =
  "renamed to `gen.records`; rename the key (it was `gen.recordTypes` from 0.15 to 0.53)";

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
          `${prefix}${key}: moved to \`${moved}\` in 0.15; upgrade to 0.53 with that release first`,
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
    ...blocks.flatMap(([prefix, block]) => renamedInputIssues(prefix, block)),
  ];
}
