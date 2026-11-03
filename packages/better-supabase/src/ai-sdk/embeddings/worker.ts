import type { Embedder } from "../../blocks/knowledge/knowledge.ts";

/** One queued row, as `process_embeddings` sends it. */
export interface EmbeddingJob {
  readonly msgId: number;
  readonly readCount: number;
  readonly id: string;
  readonly content: string;
  /**
   * The md5 of the content; the database stores the vector only while it
   * matches.
   */
  readonly hash: string;
}

export interface EmbeddingBatch {
  readonly queue: string;
  readonly table: string;
  readonly jobs: readonly EmbeddingJob[];
}

export interface EmbeddingWorkerOptions {
  readonly embedder: Embedder;
  /**
   * Stores one vector, such as `supabase.rpc("<table>_apply_embedding", {
   * row_id, embedding_json, content_hash, msg_id })` with the service role. It
   * returns `false` when the row changed meanwhile.
   */
  readonly apply: (
    batch: EmbeddingBatch,
    job: EmbeddingJob,
    embedding: readonly number[],
  ) => Promise<boolean>;
  /** The bearer token `process_embeddings` sends; the Vault `tokenSecret`. */
  readonly token: string;
  /** Jobs read this many times are dropped from the batch and reported. Default 5. */
  readonly maxReads?: number;
}

export interface EmbeddingDrainResult {
  readonly embedded: number;
  /** Rows that changed while the worker ran; the queue holds their new message. */
  readonly stale: number;
  readonly skipped: number;
}

const DEFAULT_MAX_READS = 5;

const isJob = (value: unknown): value is EmbeddingJob =>
  typeof value === "object" &&
  value !== null &&
  "msgId" in value &&
  typeof value.msgId === "number" &&
  "id" in value &&
  typeof value.id === "string" &&
  "content" in value &&
  typeof value.content === "string" &&
  "hash" in value &&
  typeof value.hash === "string";

function parseBatch(value: unknown): EmbeddingBatch | undefined {
  if (typeof value !== "object" || value === null) {
    return undefined;
  }

  // SAFETY: the value is a non-null object, and each field is checked below.
  const { queue, table, jobs } = value as Record<string, unknown>;

  if (
    typeof queue !== "string" ||
    typeof table !== "string" ||
    !Array.isArray(jobs)
  ) {
    return undefined;
  }

  return { queue, table, jobs: jobs.filter(isJob) };
}

function equal(a: string, b: string): boolean {
  if (a.length !== b.length) {
    return false;
  }

  let mismatches = 0;

  for (let index = 0; index < a.length; index += 1) {
    mismatches += a.codePointAt(index) === b.codePointAt(index) ? 0 : 1;
  }

  return mismatches === 0;
}

/**
 * Embeds one batch and stores each vector. Jobs with empty content are skipped
 * (their message is applied with the next change), and jobs read too often are
 * skipped so a poison row stops cycling through the queue.
 */
export async function drainEmbeddings(
  batch: EmbeddingBatch,
  options: Omit<EmbeddingWorkerOptions, "token">,
  signal?: AbortSignal,
): Promise<EmbeddingDrainResult> {
  const maxReads = options.maxReads ?? DEFAULT_MAX_READS;

  const jobs = batch.jobs.filter(
    (job) => job.content.trim() !== "" && job.readCount <= maxReads,
  );

  const skipped = batch.jobs.length - jobs.length;

  if (jobs.length === 0) {
    return { embedded: 0, stale: 0, skipped };
  }

  const result = await options.embedder.embed(
    jobs.map((job) => job.content),
    signal === undefined ? undefined : { signal },
  );

  const vectors = "embeddings" in result ? result.embeddings : result;
  let embedded = 0;
  let stale = 0;

  for (const [index, job] of jobs.entries()) {
    const vector = vectors[index];

    if (vector === undefined) {
      continue;
    }

    if (await options.apply(batch, job, vector)) {
      embedded += 1;
    } else {
      stale += 1;
    }
  }

  return { embedded, stale, skipped };
}

/**
 * A Fetch handler for the URL in the table's Vault `urlSecret`. It checks the
 * bearer token, embeds the batch `process_embeddings` posted and stores the
 * vectors. A failure answers 500, so the messages become visible again and the
 * next drain retries them.
 */
export function embeddingWorker(
  options: EmbeddingWorkerOptions,
): (request: Request) => Promise<Response> {
  return async (request) => {
    const header = request.headers.get("authorization") ?? "";

    if (!equal(header, `Bearer ${options.token}`)) {
      return Response.json({ error: "unauthorized" }, { status: 401 });
    }

    const batch = parseBatch(await request.json().catch(() => undefined));

    if (batch === undefined) {
      return Response.json({ error: "invalid_batch" }, { status: 400 });
    }

    try {
      return Response.json(
        await drainEmbeddings(batch, options, request.signal),
      );
    } catch {
      return Response.json({ error: "embedding_failed" }, { status: 500 });
    }
  };
}
