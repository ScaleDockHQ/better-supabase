import type { BlockOptions } from "../../core/block-helpers.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult } from "../../core/result.ts";
import {
  blockCall,
  nullableText,
  optionalInstant,
  recordsOf,
  run,
  textOf,
} from "../shared.ts";

export interface SearchOptions extends Pick<
  BlockOptions,
  "transport" | "service" | "schema" | "mappers"
> {
  /** `withBlockHooks` hooks around the methods. */
  readonly hooks?: BlockHooks<Search>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

/** One match, with the title and URL from `config.subjects`. */
export interface SearchHit {
  readonly organizationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly title: string | null;
  readonly url: string | null;
  /** A fragment of the body around the match, without markup. */
  readonly snippet: string | null;
  readonly score: number;
}

export interface SearchQuery {
  /** Subject types to search. Default: every type with a `search` entry. */
  readonly types?: readonly string[];
  /** One tenant. Default: every tenant the caller can read. */
  readonly organizationId?: string | null;
  /** At most 100. Default 20. */
  readonly limit?: number;
  /**
   * The query's embedding, when the index keeps embeddings
   * (`blocks.search.options.dimensions` and `vector-search`): the
   * results fuse full-text and nearest-neighbour ranks.
   */
  readonly embedding?: readonly number[] | null;
}

/** A subject the caller opened or starred (the share-links per-user state). */
export interface SearchUserItem {
  readonly subjectType: string;
  readonly subjectId: string;
  readonly title: string | null;
  readonly url: string | null;
  readonly openedAt: Temporal.Instant | undefined;
  readonly starredAt: Temporal.Instant | undefined;
}

export interface SearchListOptions {
  /** At most 100. Default 10. */
  readonly limit?: number;
  readonly types?: readonly string[];
}

/** A document whose text has no embedding yet. */
export interface PendingEmbedding {
  readonly subjectType: string;
  readonly subjectId: string;
  /** Pass it back to `setEmbedding`, which skips text that changed since. */
  readonly contentHash: string;
  /** The title and body to embed. */
  readonly text: string;
}

/** Embeds texts in order, one vector per text: an AI SDK `embedMany` call. */
export type Embedder = (
  texts: readonly string[],
) => Promise<readonly (readonly number[])[]>;

export interface Search {
  /**
   * Searches as the caller: `websearch_to_tsquery` syntax (`"exact phrase"`,
   * `-word`, `or`), prefixes for typeahead and trigram matches for typos.
   * Rows the caller can't read, and trashed rows, are left out.
   */
  search(q: string, query?: SearchQuery): AsyncResult<readonly SearchHit[]>;
  /** The caller's recently opened subjects, newest first. */
  recents(options?: SearchListOptions): AsyncResult<readonly SearchUserItem[]>;
  /** The caller's starred subjects, newest first. */
  favorites(
    options?: SearchListOptions,
  ): AsyncResult<readonly SearchUserItem[]>;
  /** Records that the caller opened a subject, for `recents`. */
  touch(subjectType: string, subjectId: string): AsyncResult<boolean>;
  /** Stars or unstars a subject for the caller, for `favorites`. */
  star(
    subjectType: string,
    subjectId: string,
    starred?: boolean,
  ): AsyncResult<boolean>;
  /** Reads one row into the index again. Service only. */
  refresh(subjectType: string, subjectId: string): AsyncResult<boolean>;
  /** Drops one subject from the index. Service only. */
  remove(subjectType: string, subjectId: string): AsyncResult<boolean>;
  /** Indexes every row of one type, or of all of them. Service only. */
  reindex(subjectType?: string): AsyncResult<number>;
  /** Documents without an embedding, oldest first. Service only. */
  pendingEmbeddings(limit?: number): AsyncResult<readonly PendingEmbedding[]>;
  /** Stores an embedding unless the text changed. Service only. */
  setEmbedding(
    document: Pick<
      PendingEmbedding,
      "subjectType" | "subjectId" | "contentHash"
    >,
    embedding: readonly number[],
  ): AsyncResult<boolean>;
  /**
   * Embeds up to `limit` pending documents with `embed` and stores them.
   * Run it from a job or cron. Service only. Resolves to the number stored.
   */
  embedPending(embed: Embedder, limit?: number): AsyncResult<number>;
}

const vectorArg = (values: readonly number[]): AsyncResult<string> =>
  run(() => Promise.resolve().then(() => vectorText(values)));

const vectorText = (values: readonly number[]): string => {
  if (!values.every(Number.isFinite)) {
    throw new TypeError("an embedding holds finite numbers only");
  }

  return `[${values.join(",")}]`;
};

function hitOf(row: Record<string, unknown>): SearchHit {
  return {
    organizationId: textOf(row["organizationId"]),
    subjectType: textOf(row["subjectType"]),
    subjectId: textOf(row["subjectId"]),
    title: nullableText(row["title"]),
    url: nullableText(row["url"]),
    snippet: nullableText(row["snippet"]),
    score: Number(row["score"] ?? 0),
  };
}

function userItemOf(row: Record<string, unknown>): SearchUserItem {
  return {
    subjectType: textOf(row["subjectType"]),
    subjectId: textOf(row["subjectId"]),
    title: nullableText(row["title"]),
    url: nullableText(row["url"]),
    openedAt: optionalInstant(row["openedAt"]),
    starredAt: optionalInstant(row["starredAt"]),
  };
}

function pendingOf(row: Record<string, unknown>): PendingEmbedding {
  return {
    subjectType: textOf(row["subjectType"]),
    subjectId: textOf(row["subjectId"]),
    contentHash: textOf(row["contentHash"]),
    text: textOf(row["text"]),
  };
}

/**
 * The `search` SQL module as typed calls. Build it with the caller's
 * transport for `search`, `recents` and `favorites`, and pass `service` for
 * the index maintenance methods.
 */
export function createSearch(options: SearchOptions): Search {
  const call = blockCall(options.transport, options.schema, options.mappers);

  const service = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );

  const list =
    (fn: "search_recents" | "search_favorites") =>
    (list: SearchListOptions = {}) =>
      call(
        fn,
        { max_results: list.limit ?? 10, types: list.types ?? null },
        (value) => recordsOf(value, fn).map(userItemOf),
      );

  const pendingEmbeddings: Search["pendingEmbeddings"] = (limit = 100) =>
    service("search_pending_embeddings", { max_results: limit }, (value) =>
      recordsOf(value, "search_pending_embeddings").map(pendingOf),
    );

  const setEmbedding: Search["setEmbedding"] = (entry, embedding) =>
    vectorArg(embedding).andThen((vector) =>
      service(
        "search_set_embedding",
        {
          subject_type: entry.subjectType,
          subject_id: entry.subjectId,
          content_hash: entry.contentHash,
          embedding: vector,
        },
        (value) => value === true,
      ),
    );

  const client: Search = {
    search: (q, query = {}) =>
      (query.embedding === undefined || query.embedding === null
        ? AsyncResult.ok({})
        : vectorArg(query.embedding).map((vector) => ({
            query_embedding: vector,
          }))
      ).andThen((embedding) =>
        call(
          "search",
          {
            q,
            types: query.types ?? null,
            tenant: query.organizationId ?? null,
            max_results: query.limit ?? 20,
            ...embedding,
          },
          (value) => recordsOf(value, "search").map(hitOf),
        ),
      ),
    recents: list("search_recents"),
    favorites: list("search_favorites"),
    touch: (subjectType, subjectId) =>
      call(
        "search_touch",
        { subject_type: subjectType, subject_id: subjectId },
        (value) => value === true,
      ),
    star: (subjectType, subjectId, starred = true) =>
      call(
        "search_star",
        { subject_type: subjectType, subject_id: subjectId, starred },
        (value) => value === true,
      ),
    refresh: (subjectType, subjectId) =>
      service(
        "search_refresh",
        { subject_type: subjectType, subject_id: subjectId },
        (value) => value === true,
      ),
    remove: (subjectType, subjectId) =>
      service(
        "search_remove",
        { subject_type: subjectType, subject_id: subjectId },
        (value) => value === true,
      ),
    reindex: (subjectType) =>
      service("search_reindex", { subject_type: subjectType ?? null }, Number),
    pendingEmbeddings,
    setEmbedding,
    embedPending: (embed, limit = 100) =>
      pendingEmbeddings(limit).andThen((pending) =>
        run(async () => {
          if (pending.length === 0) {
            return 0;
          }

          const vectors = await embed(pending.map((item) => item.text));

          if (vectors.length !== pending.length) {
            throw new TypeError(
              `embed returned ${String(vectors.length)} vectors for ${String(pending.length)} texts`,
            );
          }

          return service(
            "search_set_embeddings",
            {
              subject_types: pending.map((item) => item.subjectType),
              subject_ids: pending.map((item) => item.subjectId),
              content_hashes: pending.map((item) => item.contentHash),
              embeddings: vectors.map(vectorText),
            },
            Number,
          ).orThrow();
        }),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "search",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
