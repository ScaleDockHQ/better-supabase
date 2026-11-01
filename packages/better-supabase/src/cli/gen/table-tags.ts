import type {
  AnyBlocksConfig,
  AppColumnConfig,
  AppColumnType,
  AppTableConfig,
  AppTableEventKind,
  AppTableEvents,
  JsonTypeConfig,
  ResolvedConfig,
  SubjectConfig,
  VectorDistance,
} from "../../config/index.ts";

import {
  APP_COLUMN_TYPES,
  APP_TABLE_EVENT_KINDS,
  blockSubjectTypes,
} from "../../config/index.ts";
import { parseBsbComment } from "../../sql/index.ts";
import { subjectFromTag } from "../subject-tag.ts";

/** The part of a table a tag reader needs: its name and comment. */
export interface TableComment {
  readonly schema: string;
  readonly name: string;
  readonly comment: string | null;
}

const DISTANCES: ReadonlySet<string> = new Set([
  "cosine",
  "l2",
  "inner_product",
]);

function isDistance(value: string): value is VectorDistance {
  return DISTANCES.has(value);
}

const IMPORT_PREFIX = "import:";

function isColumnType(value: string): value is AppColumnType {
  return APP_COLUMN_TYPES.some((type) => type === value);
}

function isEventKind(value: string): value is AppTableEventKind {
  return APP_TABLE_EVENT_KINDS.some((kind) => kind === value);
}

function list(value: string | true | undefined): string[] {
  return typeof value === "string"
    ? value
        .split(",")
        .map((item) => item.trim())
        .filter((item) => item !== "")
    : [];
}

/** A `column=value` argument map of a tag, without bare flags. */
function textArgs(
  args: Readonly<Record<string, string | true>>,
): Record<string, string> {
  return Object.fromEntries(
    Object.entries(args).flatMap(([key, value]) =>
      typeof value === "string" ? [[key, value]] : [],
    ),
  );
}

/** The `on` object of block `name` with `entry` for `type`, unless it has one. */
function bindOn(
  blocks: AnyBlocksConfig,
  name: string,
  type: string,
  entry: Record<string, unknown>,
): AnyBlocksConfig {
  const current = blocks[name];
  const on = current?.on;

  const bound: Record<string, Record<string, unknown>> = Array.isArray(on)
    ? Object.fromEntries(on.map((each: unknown) => [String(each), {}]))
    : { ...(on === undefined ? {} : Object.fromEntries(Object.entries(on))) };

  if (current === undefined || type in bound) {
    return blocks;
  }

  return { ...blocks, [name]: { ...current, on: { ...bound, [type]: entry } } };
}

function text(value: string | true | undefined): string | undefined {
  return typeof value === "string" ? value : undefined;
}

/**
 * `config` with the per-table features the schema's `@bsb` table comments turn
 * on (ADR 0102): `subject`, `realtime`, `vector-search`, `json` (`column=Type`,
 * or `column=import:module#Name`), `encrypted` (`column=type`, a bare column is
 * text), `lookup` (bare encrypted columns) and `events` (`on`, `include`).
 * `audit`, `audit-reads` and `expose` change the table's SQL only, so `gen` has
 * nothing to read from them. A key the config sets itself wins, so a project
 * can move to tags one table at a time. Tables outside `config.schemas` are
 * ignored.
 */
export function withTableTags(
  config: ResolvedConfig,
  tables: readonly TableComment[],
): ResolvedConfig {
  const subjects: Record<string, SubjectConfig> = { ...config.subjects };
  const realtimeTables = [...config.realtime.tables];
  const realtimeGlobal = [...config.realtime.global];
  const realtimeUsers = { ...config.realtime.users };
  const vectorSearch = [...config.vectorSearch];
  const json: Record<string, JsonTypeConfig> = { ...config.json };
  const appTables: Record<string, AppTableConfig> = { ...config.appTables };
  const fromTags = new Set<string>();
  const eventTables = new Set<string>();

  let blocks = config.blocks;

  const pending: {
    table: string;
    tag: string;
    args: Record<string, string | true>;
  }[] = [];

  const blockTypes = new Map(
    config.blockNames.flatMap((module) =>
      blockSubjectTypes(module, config.blocks).map(
        (type) => [type, module] as const,
      ),
    ),
  );

  let changed = false;

  for (const table of tables) {
    if (!config.schemas.includes(table.schema)) {
      continue;
    }

    const { tags } = parseBsbComment(table.comment);

    if (tags.length === 0) {
      continue;
    }

    const qualified = `${table.schema}.${table.name}`;
    const short = table.schema === "public" ? table.name : qualified;
    const names = new Set([short, qualified]);

    for (const tag of tags) {
      if (tag.name === "subject") {
        const type = text(tag.args["type"]) ?? table.name;
        const block = blockTypes.get(type);

        if (block !== undefined) {
          throw new TypeError(
            `${qualified}: the @bsb subject tag declares "${type}", which the ${block} block registers itself; give the tag another type, or rename the block's entity in blocks.${block}.names`,
          );
        }

        if (subjects[type] === undefined) {
          subjects[type] = subjectFromTag(tag.args, short);
          changed = true;
        }
      } else if (
        tag.name === "realtime" &&
        !realtimeTables.some((each) => names.has(each))
      ) {
        realtimeTables.push(short);
        const user = text(tag.args["user"]);

        if (tag.args["global"] === true) {
          realtimeGlobal.push(short);
        }

        if (user !== undefined) {
          realtimeUsers[short] = user;
        }

        changed = true;
      } else if (tag.name === "json") {
        for (const [column, value] of Object.entries(tag.args)) {
          const key = `${short}.${column}`;

          const taken = [key, `${qualified}.${column}`].some(
            (each) => each in json,
          );

          if (typeof value === "string" && !taken) {
            json[key] = value.startsWith(IMPORT_PREFIX)
              ? { import: value.slice(IMPORT_PREFIX.length) }
              : { type: value };

            changed = true;
          }
        }
      } else if (tag.name === "encrypted" && table.schema === "public") {
        for (const [column, value] of Object.entries(tag.args)) {
          const type = value === true ? "text" : value;
          const own = appTables[table.name];

          const existing = own?.columns?.[column];

          const key = `${table.name}.${column}`;

          if (
            isColumnType(type) &&
            (existing === undefined || fromTags.has(key))
          ) {
            fromTags.add(key);

            const entry: AppColumnConfig = {
              ...existing,
              type,
              encrypted: true,
            };

            appTables[table.name] = {
              ...own,
              columns: { ...own?.columns, [column]: entry },
            };

            changed = true;
          }
        }
      } else if (tag.name === "lookup" && table.schema === "public") {
        for (const column of Object.keys(tag.args)) {
          const own = appTables[table.name];
          const existing = own?.columns?.[column];

          const key = `${table.name}.${column}`;

          if (existing === undefined || fromTags.has(key)) {
            fromTags.add(key);

            const entry: AppColumnConfig = {
              type: "text",
              ...existing,
              lookup: true,
            };

            appTables[table.name] = {
              ...own,
              columns: { ...own?.columns, [column]: entry },
            };

            changed = true;
          }
        }
      } else if (tag.name === "server" && table.schema === "public") {
        for (const column of Object.keys(tag.args)) {
          const own = appTables[table.name];
          const existing = own?.columns?.[column];

          const key = `${table.name}.${column}`;

          if (existing === undefined || fromTags.has(key)) {
            fromTags.add(key);

            const entry: AppColumnConfig = {
              type: "text",
              ...existing,
              access: "server",
            };

            appTables[table.name] = {
              ...own,
              columns: { ...own?.columns, [column]: entry },
            };

            changed = true;
          }
        }
      } else if (
        tag.name === "events" &&
        table.schema === "public" &&
        appTables[table.name]?.events === undefined
      ) {
        const on = list(tag.args["on"]).filter(isEventKind);
        const include = list(tag.args["include"]);

        const events: true | AppTableEvents =
          on.length === 0 && include.length === 0
            ? true
            : {
                ...(on.length === 0 ? {} : { on }),
                ...(include.length === 0 ? {} : { include }),
              };

        appTables[table.name] = { ...appTables[table.name], events };
        eventTables.add(table.name);
        changed = true;
      } else if (
        tag.name === "audit-reads" ||
        tag.name === "history" ||
        tag.name === "lifecycle"
      ) {
        pending.push({
          table: names.has(short) ? short : qualified,
          tag: tag.name,
          args: tag.args,
        });
      } else if (
        tag.name === "vector-search" &&
        !vectorSearch.some((each) => names.has(each.table))
      ) {
        const column = text(tag.args["column"]);
        const distance = text(tag.args["distance"]) ?? "cosine";

        if (column !== undefined && isDistance(distance)) {
          vectorSearch.push({ table: short, column, distance });
          changed = true;
        }
      }
    }
  }

  // The events are named after the subject type, as the table's trigger does.
  for (const name of eventTables) {
    const type = Object.entries(subjects).find(
      ([, subject]) =>
        subject.table === name || subject.table === `public.${name}`,
    )?.[0];

    if (type !== undefined) {
      appTables[name] = { ...appTables[name], subject: { type } };
    }
  }

  for (const { table, tag, args } of pending) {
    const type = Object.entries(subjects).find(
      ([, subject]) =>
        subject.table === table ||
        subject.table === `public.${table}` ||
        `public.${subject.table}` === table,
    )?.[0];

    if (type === undefined) {
      continue;
    }

    const subject = subjects[type];

    if (tag === "audit-reads" && subject !== undefined) {
      subjects[type] = { ...subject, auditReads: true };
      changed = true;
    } else if (tag === "history") {
      const fields = Object.keys(args).filter((key) => args[key] === true);
      const next = bindOn(blocks, "field-history", type, { fields });

      changed ||= next !== blocks && fields.length > 0;
      blocks = fields.length > 0 ? next : blocks;
    } else if (tag === "lifecycle") {
      const entry = textArgs(args);

      if (entry["stage"] !== undefined && entry["pipeline"] !== undefined) {
        const next = bindOn(blocks, "pipelines", type, entry);
        changed ||= next !== blocks;
        blocks = next;
      }
    }
  }

  return changed
    ? {
        ...config,
        blocks,
        subjects,
        vectorSearch,
        json,
        appTables,
        realtime: {
          ...config.realtime,
          tables: realtimeTables,
          global: realtimeGlobal,
          users: realtimeUsers,
        },
      }
    : config;
}
