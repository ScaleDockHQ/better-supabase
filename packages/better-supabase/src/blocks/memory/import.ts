import type { AsyncResult as AsyncResultType } from "../../core/result.ts";
import type { Memory, MemoryNamespace } from "./types.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { sqlIdent } from "../../core/template.ts";

/** What `importMemories` reads rows with: a `pg` pool or `createPostgres()`. */
export interface ImportMemoriesSource {
  queryRaw<T = Record<string, unknown>>(
    text: string,
    params?: unknown[],
  ): Promise<T[]>;
}

export interface ImportMemoriesOptions {
  /** `createMemory` on a service transport. */
  readonly memory: Memory;
  /** The client of the database that holds the old table. */
  readonly source: ImportMemoriesSource;
  /** The old table, `memories` or `legacy.agent_memories`. */
  readonly table: string;
  /** The tenant the imported memories belong to. */
  readonly organizationId: string | null;
  readonly ns?: MemoryNamespace | undefined;
  /**
   * The old table's column names. `id` orders the import and has to be unique
   * and sortable; `embedding` is a `vector` or `halfvec` column (for example
   * `halfvec(1536)`) whose values are kept as they are.
   */
  readonly columns?: {
    readonly id?: string;
    readonly content?: string;
    readonly embedding?: string | null;
    readonly category?: string | null;
    readonly confidence?: string | null;
  };
  /** The model that made the old embeddings, stored with each memory. */
  readonly embeddingModel?: string;
  /** Rows per query. Defaults to 200. */
  readonly batch?: number;
  /** Continues after this id, from an earlier result's `lastId`. */
  readonly after?: string;
  /** Stops after this many rows, to import in slices. */
  readonly limit?: number;
}

export interface ImportMemoriesResult {
  /** Memories stored. */
  readonly imported: number;
  /** Rows without content, which are not stored. */
  readonly skipped: number;
  /** The id of the last row read; pass it as `after` to continue. */
  readonly lastId: string | undefined;
}

const NAME = /^[a-z_][a-z0-9_]*$/;

const identifier = (value: string): string | undefined =>
  NAME.test(value) ? sqlIdent(value) : undefined;

function tableOf(table: string): string | undefined {
  const parts = table.split(".");

  if (parts.length > 2) {
    return undefined;
  }

  const idents = parts.map((part) => identifier(part));

  return idents.every((part) => part !== undefined)
    ? idents.join(".")
    : undefined;
}

/**
 * Copies rows of an existing table into the memory block as archival memories,
 * with the embeddings they already have, so a large history needs no new
 * embedding calls. The embedding is read as text and stored through
 * `archival.upsert({ embedding })`; its length has to match the memory block's
 * embedding column (`halfvec(1536)` by default).
 *
 * Reads in id order and returns `lastId`, so a failed or sliced run continues
 * with `after`. Memories are not deduplicated: continue from `lastId` instead
 * of running the same range twice.
 */
export function importMemories(
  options: ImportMemoriesOptions,
): AsyncResultType<ImportMemoriesResult> {
  return AsyncResult.from(async () => {
    const names = {
      id: options.columns?.id ?? "id",
      content: options.columns?.content ?? "content",
      embedding:
        options.columns?.embedding === undefined
          ? "embedding"
          : options.columns.embedding,
      category:
        options.columns?.category === undefined
          ? null
          : options.columns.category,
      confidence:
        options.columns?.confidence === undefined
          ? null
          : options.columns.confidence,
    };

    const table = tableOf(options.table);

    const idents = {
      id: identifier(names.id),
      content: identifier(names.content),
      embedding: names.embedding === null ? null : identifier(names.embedding),
      category: names.category === null ? null : identifier(names.category),
      confidence:
        names.confidence === null ? null : identifier(names.confidence),
    };

    if (
      table === undefined ||
      idents.id === undefined ||
      idents.content === undefined ||
      idents.embedding === undefined ||
      idents.category === undefined ||
      idents.confidence === undefined
    ) {
      return err(
        dbError(
          "invalid_input",
          "importMemories needs plain table and column names such as legacy.agent_memories",
        ),
      );
    }

    const batch = Math.min(Math.max(options.batch ?? 200, 1), 1000);
    const limit = options.limit ?? Number.POSITIVE_INFINITY;

    const select = [
      `${idents.id}::text as id`,
      `${idents.content} as content`,
      idents.embedding === null
        ? "null::text as embedding"
        : `${idents.embedding}::text as embedding`,
      idents.category === null
        ? "null::text as category"
        : `${idents.category}::text as category`,
      idents.confidence === null
        ? "null::real as confidence"
        : `${idents.confidence}::real as confidence`,
    ].join(", ");

    let after = options.after;
    let imported = 0;
    let skipped = 0;
    let read = 0;

    while (read < limit) {
      const rows = await options.source.queryRaw<{
        id: string;
        content: string | null;
        embedding: string | null;
        category: string | null;
        confidence: number | null;
      }>(
        `select ${select} from ${table}${after === undefined ? "" : ` where ${idents.id} > $1`} order by ${idents.id} limit ${String(Math.min(batch, limit - read))}`,
        after === undefined ? [] : [after],
      );

      if (rows.length === 0) {
        break;
      }

      for (const row of rows) {
        after = row.id;
        read += 1;

        if (row.content === null || row.content.trim().length === 0) {
          skipped += 1;
          continue;
        }

        const saved = await options.memory.archival.upsert({
          organizationId: options.organizationId,
          content: row.content,
          ns: options.ns,
          sourceMessageId: `import:${options.table}:${row.id}`.slice(0, 200),
          ...(row.category === null ? {} : { category: row.category }),
          ...(row.confidence === null ? {} : { confidence: row.confidence }),
          ...(row.embedding === null
            ? {}
            : {
                embedding: row.embedding,
                ...(options.embeddingModel === undefined
                  ? {}
                  : { embeddingModel: options.embeddingModel }),
              }),
        });

        if (!saved.ok) {
          return saved;
        }

        imported += 1;
      }

      if (rows.length < batch) {
        break;
      }
    }

    return ok({ imported, skipped, lastId: after });
  });
}
