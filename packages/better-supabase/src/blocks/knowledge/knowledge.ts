import type { BlockTransport } from "../../core/block-transport.ts";
import type { DbError, ErrorMapper } from "../../core/errors.ts";
import type { Result } from "../../core/result.ts";
import type { AiFile, AiFiles } from "../ai-files/ai-files.ts";
import type { JobHandler } from "../jobs/queue.ts";

import { DbException, dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { vectorLiteral as pgVector } from "../../core/search.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  errorText,
  isRecord,
  optionalText,
  recordOf,
  recordOrEmpty,
  recordsOf,
  run,
  textOf,
  toInstant,
} from "../shared.ts";

/**
 * Turns texts into vectors. `model` is stored with each document, so a
 * document embedded by another model can be found and embedded again.
 */
export interface Embedder {
  readonly model: string;
  embed(
    values: readonly string[],
    options?: { readonly signal?: AbortSignal },
  ): Promise<readonly (readonly number[])[]>;
}

export type KnowledgeScope =
  | "organization"
  | "agent"
  | "project"
  | "chat"
  | "user";
export type KnowledgeStatus = "pending" | "ready" | "failed";

export interface KnowledgeDocument {
  readonly id: string;
  readonly organizationId: string;
  readonly ownerId: string;
  readonly scope: KnowledgeScope;
  /** The agent, project, chat or user the document belongs to; none for organization scope. */
  readonly scopeId: string | undefined;
  readonly fileId: string | undefined;
  readonly title: string;
  readonly source: string | undefined;
  readonly metadata: Readonly<Record<string, unknown>>;
  readonly status: KnowledgeStatus;
  readonly error: string | undefined;
  readonly chunkCount: number;
  readonly embeddingModel: string | undefined;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface NewKnowledgeDocument {
  readonly title: string;
  /** Default `user`, scoped to the caller. */
  readonly scope?: KnowledgeScope;
  readonly scopeId?: string;
  readonly fileId?: string;
  /** Where the text came from: a URL, a file name or a table. */
  readonly source?: string;
  readonly metadata?: Readonly<Record<string, unknown>>;
  /** The service role only: the user the document belongs to. */
  readonly ownerId?: string;
}

export interface KnowledgeChunk {
  readonly content: string;
  /** An estimate of the tokens in `content`. */
  readonly tokens?: number;
  readonly metadata?: Readonly<Record<string, unknown>>;
}

export interface KnowledgeHit {
  readonly documentId: string;
  readonly index: number;
  readonly content: string;
  readonly metadata: Readonly<Record<string, unknown>>;
  readonly title: string;
  /** The fused reciprocal rank score; higher is better. */
  readonly score: number;
}

export interface KnowledgeQuery {
  /** Searched as full text, and embedded when the block has an embedder. */
  readonly text?: string;
  /** An embedding of the query, used instead of embedding `text`. */
  readonly embedding?: readonly number[];
}

export interface KnowledgeSearchOptions {
  /** The scopes to search, each with an optional id; every scope when unset. */
  readonly scopes?: readonly {
    readonly scope: KnowledgeScope;
    readonly id?: string;
  }[];
  /** How many chunks to return. Default 8, at most 100. */
  readonly k?: number;
  /** Matches documents whose metadata contains this object. */
  readonly filter?: Readonly<Record<string, unknown>>;
  readonly signal?: AbortSignal;
}

export interface ChunkOptions {
  /** The most characters in a chunk. Default 2000. */
  readonly size?: number;
  /** Characters repeated from the end of the previous chunk. Default 200, or a tenth of a smaller `size`. */
  readonly overlap?: number;
}

export interface KnowledgeOptions extends BlockTemporalOptions {
  /** Calls as the user: `rpcTransport(supabase)`. */
  readonly transport: BlockTransport;
  /** Calls as the service role, for `process`, `drain` and `reembed`. */
  readonly service?: BlockTransport;
  /** The module schema (`sql.modules.knowledge.schema`), default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /** Embeds chunks and queries; without one, search is full text only. */
  readonly embedder?: Embedder;
  /** The ai-files block, for `ingest.file`. */
  readonly files?: AiFiles;
  /**
   * The text of a file. The default decodes `text/*`, JSON, XML and YAML
   * as UTF-8 and fails with `KNOWLEDGE_UNSUPPORTED` for anything else.
   */
  readonly extract?: (file: AiFile, data: Uint8Array) => Promise<string>;
  readonly chunking?: ChunkOptions;
  /** Chunks per embedding call. Default 64. */
  readonly batchSize?: number;
}

export interface Knowledge {
  readonly documents: {
    create(
      organizationId: string,
      document: NewKnowledgeDocument,
    ): AsyncResult<KnowledgeDocument>;
    get(documentId: string): AsyncResult<KnowledgeDocument>;
    list(
      organizationId: string,
      options?: {
        readonly scope?: KnowledgeScope;
        readonly scopeId?: string;
        readonly limit?: number;
      },
    ): AsyncResult<readonly KnowledgeDocument[]>;
    /** Replaces the chunks; unchanged chunks keep their embedding. */
    write(
      documentId: string,
      chunks: readonly KnowledgeChunk[],
    ): AsyncResult<KnowledgeDocument>;
    remove(documentId: string): AsyncResult<boolean>;
  };
  readonly ingest: {
    /** Creates a document from text and writes its chunks. */
    text(
      organizationId: string,
      document: NewKnowledgeDocument & { readonly text: string },
    ): AsyncResult<KnowledgeDocument>;
    /** Creates a document from a ready ai-files file and writes its chunks. */
    file(
      organizationId: string,
      fileId: string,
      document?: Partial<NewKnowledgeDocument>,
    ): AsyncResult<KnowledgeDocument>;
  };
  /**
   * Embeds a document's pending chunks (service role). Returns how many
   * still wait, 0 once the document is ready.
   */
  process(
    documentId: string,
    options?: { readonly signal?: AbortSignal | undefined },
  ): AsyncResult<number>;
  /**
   * The handler for the `knowledge_embed` queue. The last attempt marks
   * the document failed with the error.
   */
  embedJob(): JobHandler<{ readonly document_id: string }>;
  /**
   * Processes pending documents without a queue (service role). Returns how
   * many. A document is marked failed only after `attempts` (default 3)
   * tries fail, and never when the signal aborted it.
   */
  drain(options?: {
    readonly batch?: number;
    readonly attempts?: number;
    readonly signal?: AbortSignal;
  }): AsyncResult<number>;
  search(
    organizationId: string,
    query: string | KnowledgeQuery,
    options?: KnowledgeSearchOptions,
  ): AsyncResult<readonly KnowledgeHit[]>;
  /**
   * Marks documents embedded by another model (or every document when
   * `model` is unset) pending again (service role). Returns how many.
   */
  reembed(options?: {
    readonly organizationId?: string;
    readonly model?: string;
  }): AsyncResult<number>;
}

const SCOPES: ReadonlySet<string> = new Set([
  "organization",
  "agent",
  "project",
  "chat",
  "user",
]);
const STATUSES: ReadonlySet<string> = new Set(["pending", "ready", "failed"]);
const BREAKS = ["\n\n", "\n", ". ", " "] as const;
const TEXT_TYPES =
  /^(text\/|application\/(json|xml|yaml|x-yaml|ld\+json|x-ndjson)\b)/;

/**
 * Splits text into chunks of at most `size` characters, preferring a
 * paragraph, line, sentence or word break in the second half of each
 * chunk, and repeating `overlap` characters of the previous one.
 */
export function chunk(
  text: string,
  options: ChunkOptions = {},
): readonly KnowledgeChunk[] {
  const size = options.size ?? 2000;
  const overlap = options.overlap ?? Math.min(200, Math.floor(size / 10));
  if (!Number.isInteger(size) || size < 1) {
    throw new RangeError("chunk size must be a positive whole number");
  }
  if (!Number.isInteger(overlap) || overlap < 0 || overlap >= size) {
    throw new RangeError("chunk overlap must be at least 0 and below size");
  }
  const clean = text.replaceAll(/\r\n?/g, "\n").trim();
  const chunks: KnowledgeChunk[] = [];
  let start = 0;
  while (start < clean.length) {
    let end = Math.min(start + size, clean.length);
    if (end < clean.length) {
      const window = clean.slice(start, end);
      for (const mark of BREAKS) {
        const at = window.lastIndexOf(mark);
        if (at >= window.length / 2) {
          end = start + at + mark.length;
          break;
        }
      }
    }
    const content = clean.slice(start, end).trim();
    if (content !== "") {
      chunks.push({ content, tokens: Math.ceil(content.length / 4) });
    }
    if (end >= clean.length) break;
    const back = Math.max(end - overlap, start + 1);
    const word = /\s/.test(clean.charAt(back - 1))
      ? back - 1
      : clean.indexOf(" ", back);
    start = overlap > 0 && word >= back - 1 && word < end ? word + 1 : back;
  }
  return chunks;
}

/**
 * A vector in pgvector's text form, which both transports pass through.
 *
 * @deprecated The block formats embeddings itself; removed in 0.8.
 */
export const vectorLiteral = (values: readonly number[]): string =>
  `[${values.join(",")}]`;

/**
 * An `invalid_input` error unless the embedder returned `count` vectors of
 * one non-zero length with finite numbers.
 */
export function checkVectors(
  vectors: readonly (readonly number[])[],
  count: number,
): DbError | undefined {
  const invalid = (message: string): DbError =>
    dbError("invalid_input", message, { hint: "EMBEDDING_INVALID" });
  if (vectors.length !== count) {
    return invalid(
      `The embedder returned ${vectors.length} vectors for ${count} values`,
    );
  }
  const size = vectors[0]?.length ?? 0;
  for (const vector of vectors) {
    if (vector.length === 0 || vector.length !== size) {
      return invalid(
        "The embedder returned vectors of different or zero length",
      );
    }
    if (!vector.every(Number.isFinite)) {
      return invalid("The embedder returned a vector with a non-finite number");
    }
  }
  return undefined;
}

const scopeOf = (value: unknown): KnowledgeScope => {
  const text = textOf(value);
  // SAFETY: SCOPES holds exactly the KnowledgeScope members.
  return SCOPES.has(text) ? (text as KnowledgeScope) : "user";
};

const statusOf = (value: unknown): KnowledgeStatus => {
  const text = textOf(value);
  // SAFETY: STATUSES holds exactly the KnowledgeStatus members.
  return STATUSES.has(text) ? (text as KnowledgeStatus) : "failed";
};

const instant = (value: unknown): Temporal.Instant =>
  value instanceof Date ? toInstant(value) : toInstant(textOf(value));

function documentOf(value: unknown): KnowledgeDocument {
  const row = recordOf(value, "knowledge_documents");
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organization_id"]),
    ownerId: textOf(row["owner_id"]),
    scope: scopeOf(row["scope"]),
    scopeId: optionalText(row["scope_id"]),
    fileId: optionalText(row["file_id"]),
    title: textOf(row["title"]),
    source: optionalText(row["source"]),
    metadata: recordOrEmpty(row["metadata"]),
    status: statusOf(row["status"]),
    error: optionalText(row["error"]),
    chunkCount: Number(row["chunk_count"] ?? 0),
    embeddingModel: optionalText(row["embedding_model"]),
    createdAt: instant(row["created_at"]),
    updatedAt: instant(row["updated_at"]),
  };
}

function hitOf(value: unknown): KnowledgeHit {
  const row = recordOf(value, "knowledge_search");
  return {
    documentId: textOf(row["document_id"]),
    index: Number(row["idx"]),
    content: textOf(row["content"]),
    metadata: recordOrEmpty(row["metadata"]),
    title: textOf(row["title"]),
    score: Number(row["score"]),
  };
}

const notFound = (): DbError =>
  dbError("not_found", "No knowledge document you can see has this id", {
    hint: "KNOWLEDGE_NOT_FOUND",
  });

const decoder = new TextDecoder("utf-8", { fatal: true });

function defaultExtract(file: AiFile, data: Uint8Array): Promise<string> {
  if (!TEXT_TYPES.test(file.mediaType)) {
    return Promise.reject(
      new TypeError(
        `No text extractor for ${file.mediaType}; pass extract to createKnowledge`,
      ),
    );
  }
  return Promise.resolve(decoder.decode(data));
}

const unsupported = (cause: unknown): DbError =>
  dbError("invalid_request", errorText(cause), {
    hint: "KNOWLEDGE_UNSUPPORTED",
  });

/** Documents, chunks and hybrid search for retrieval. */
export function createKnowledge(options: KnowledgeOptions): Knowledge {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const service = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );
  const batchSize = options.batchSize ?? 64;
  const extract = options.extract ?? defaultExtract;
  const embedder = options.embedder;

  const found = (value: unknown): AsyncResult<KnowledgeDocument> =>
    isRecord(value)
      ? AsyncResult.ok(documentOf(value))
      : AsyncResult.err(notFound());

  const create = (
    organizationId: string,
    document: NewKnowledgeDocument,
  ): AsyncResult<KnowledgeDocument> =>
    call(
      "create_knowledge_document",
      {
        tenant: organizationId,
        title: document.title,
        scope: document.scope,
        scope_id: document.scopeId,
        file_id: document.fileId,
        source: document.source,
        metadata: document.metadata,
        owner: document.ownerId,
      },
      documentOf,
    );

  const write = (
    documentId: string,
    chunks: readonly KnowledgeChunk[],
  ): AsyncResult<KnowledgeDocument> =>
    call(
      "write_knowledge_chunks",
      {
        document_id: documentId,
        chunks: { items: chunks },
        model: embedder?.model,
      },
      (value) => value,
    ).andThen(found);

  const fromText = (
    organizationId: string,
    document: NewKnowledgeDocument,
    text: string,
  ): AsyncResult<KnowledgeDocument> =>
    run(() => Promise.resolve(chunk(text, options.chunking))).andThen(
      (chunks) =>
        create(organizationId, document).andThen((created) =>
          write(created.id, chunks),
        ),
    );

  const embed = (
    values: readonly string[],
    signal: AbortSignal | undefined,
  ): AsyncResult<readonly (readonly number[])[]> =>
    embedder
      ? run(() =>
          embedder.embed(values, signal === undefined ? undefined : { signal }),
        )
      : AsyncResult.err(
          dbError("invalid_request", "createKnowledge has no embedder", {
            hint: "KNOWLEDGE_NO_EMBEDDER",
          }),
        );

  const process = (
    documentId: string,
    processOptions: { readonly signal?: AbortSignal | undefined } = {},
  ): AsyncResult<number> =>
    AsyncResult.from(async (): Promise<Result<number>> => {
      let before = Number.POSITIVE_INFINITY;
      for (;;) {
        const pending = await service(
          "pending_knowledge_chunks",
          { document_id: documentId, batch: batchSize },
          (value) => recordsOf(value, "pending_knowledge_chunks"),
        );
        if (!pending.ok) return pending;
        if (pending.data.length === 0) return ok(0);
        const vectors = await embed(
          pending.data.map((row) => textOf(row["content"])),
          processOptions.signal,
        );
        if (!vectors.ok) return vectors;
        const invalid = checkVectors(vectors.data, pending.data.length);
        if (invalid) return err(invalid);
        const remaining = await service(
          "set_knowledge_embeddings",
          {
            document_id: documentId,
            embeddings: {
              items: pending.data.map((row, index) => ({
                idx: Number(row["idx"]),
                hash: row["hash"],
                embedding: pgVector(vectors.data[index] ?? []),
              })),
            },
            model: embedder?.model,
          },
          Number,
        );
        if (!remaining.ok || remaining.data === 0) return remaining;
        if (processOptions.signal?.aborted) return ok(remaining.data);
        // Chunks rewritten while they were embedded stay pending; stop when a
        // round makes no progress instead of embedding them in a loop.
        if (remaining.data >= before) return ok(remaining.data);
        before = remaining.data;
      }
    });

  return {
    documents: {
      create,
      get: (documentId) =>
        call(
          "get_knowledge_document",
          { document_id: documentId },
          (value) => value,
        ).andThen(found),
      list: (organizationId, listOptions = {}) =>
        call(
          "list_knowledge_documents",
          {
            tenant: organizationId,
            scope: listOptions.scope,
            scope_id: listOptions.scopeId,
            max_rows: listOptions.limit,
          },
          (value) =>
            recordsOf(value, "list_knowledge_documents").map(documentOf),
        ),
      write,
      remove: (documentId) =>
        call(
          "delete_knowledge_document",
          { document_id: documentId },
          (value) => value === true,
        ),
    },
    ingest: {
      text: (organizationId, { text, ...document }) =>
        fromText(organizationId, document, text),
      file: (organizationId, fileId, document = {}) => {
        const files = options.files;
        if (!files) {
          return AsyncResult.err(
            dbError("invalid_request", "createKnowledge has no files block", {
              hint: "KNOWLEDGE_NO_FILES",
            }),
          );
        }
        return files.files.read(fileId).andThen(({ file, data }) =>
          AsyncResult.from(async () => {
            try {
              return ok(await extract(file, data));
            } catch (cause) {
              return err(unsupported(cause));
            }
          }).andThen((text) =>
            fromText(
              organizationId,
              {
                ...document,
                title: document.title ?? file.filename,
                fileId: file.id,
                source: document.source ?? file.filename,
              },
              text,
            ),
          ),
        );
      },
    },
    process,
    embedJob: () => async (payload, job, signal) => {
      const result = await process(payload.document_id, { signal });
      if (result.ok) return;
      if (job.attempts >= job.maxAttempts) {
        await service(
          "fail_knowledge_document",
          { document_id: payload.document_id, error: result.error.message },
          (value) => value,
        );
      }
      throw new DbException(result.error);
    },
    drain: (drainOptions = {}) =>
      service(
        "pending_knowledge_documents",
        { batch: drainOptions.batch },
        (value) => (Array.isArray(value) ? value.map(textOf) : []),
      ).andThen((ids) =>
        AsyncResult.from(async () => {
          const attempts = Math.max(1, drainOptions.attempts ?? 3);
          let done = 0;
          for (const id of ids) {
            if (drainOptions.signal?.aborted) break;
            let result = await process(id, drainOptions);
            for (
              let attempt = 1;
              !result.ok && attempt < attempts && !drainOptions.signal?.aborted;
              attempt += 1
            ) {
              result = await process(id, drainOptions);
            }
            if (result.ok) {
              done += 1;
            } else if (!drainOptions.signal?.aborted) {
              await service(
                "fail_knowledge_document",
                { document_id: id, error: result.error.message },
                (value) => value,
              );
            }
          }
          return ok(done);
        }),
      ),
    search: (organizationId, query, searchOptions = {}) => {
      const { text, embedding } =
        typeof query === "string"
          ? { text: query, embedding: undefined }
          : query;
      const embeds =
        embedding === undefined &&
        embedder !== undefined &&
        text !== undefined &&
        text !== "";
      const vector: AsyncResult<readonly number[] | undefined> = embeds
        ? embed([text], searchOptions.signal).map((vectors) => vectors[0])
        : AsyncResult.ok(embedding);
      return vector.andThen((value) =>
        call(
          "knowledge_search",
          {
            tenant: organizationId,
            query_embedding: value === undefined ? undefined : pgVector(value),
            query_text: text === "" ? undefined : text,
            scopes:
              searchOptions.scopes === undefined
                ? undefined
                : { items: searchOptions.scopes },
            k: searchOptions.k,
            filter: searchOptions.filter,
          },
          (rows) => recordsOf(rows, "knowledge_search").map(hitOf),
        ),
      );
    },
    reembed: (reembedOptions = {}) =>
      service(
        "reembed_knowledge",
        { tenant: reembedOptions.organizationId, model: reembedOptions.model },
        Number,
      ),
  };
}
