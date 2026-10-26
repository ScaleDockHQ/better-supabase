import type {
  ResolvedConfig,
  SubjectConfig,
  VectorDistance,
} from "../../config/index.ts";
import type { Snapshot } from "../introspect/types.ts";

import { parseBsbComment } from "../../sql/index.ts";

const DISTANCES: ReadonlySet<string> = new Set([
  "cosine",
  "l2",
  "inner_product",
]);

function isDistance(value: string): value is VectorDistance {
  return DISTANCES.has(value);
}

function text(value: string | true | undefined): string | undefined {
  return typeof value === "string" ? value : undefined;
}

/**
 * `config` with the per-table features the schema's `@bsb` table comments turn
 * on (ADR 0102): `subject`, `realtime` and `vector-search`. A key the config
 * sets itself wins, so a project can move to tags one table at a time. Tables
 * outside `config.schemas` are ignored.
 */
export function withTableTags(
  config: ResolvedConfig,
  snapshot: Snapshot,
): ResolvedConfig {
  const subjects: Record<string, SubjectConfig> = { ...config.subjects };
  const realtimeTables = [...config.realtime.tables];
  const realtimeGlobal = [...config.realtime.global];
  const realtimeUsers = { ...config.realtime.users };
  const vectorSearch = [...config.vectorSearch];
  let changed = false;

  for (const table of snapshot.generator.tables) {
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

        if (subjects[type] === undefined) {
          const title = text(tag.args["title"]);
          const url = text(tag.args["url"]);
          const tenant = text(tag.args["tenant"]);

          subjects[type] = {
            table: short,
            ...(title === undefined ? {} : { title }),
            ...(url === undefined ? {} : { url }),
            ...(tenant === undefined ? {} : { tenant }),
          };

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

  return changed
    ? {
        ...config,
        subjects,
        vectorSearch,
        realtime: {
          ...config.realtime,
          tables: realtimeTables,
          global: realtimeGlobal,
          users: realtimeUsers,
        },
      }
    : config;
}
