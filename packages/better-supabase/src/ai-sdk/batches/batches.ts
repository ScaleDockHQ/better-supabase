import type {
  Experimental_BatchItemResult,
  Experimental_BatchProvider,
  Experimental_BatchReference,
  Experimental_BatchStatus,
  Experimental_StartBatchOptions,
  Experimental_StartBatchResult,
} from "ai";

import {
  experimental_cancelBatch,
  experimental_getBatchResults,
  experimental_getBatchStatus,
  experimental_startBatch,
} from "ai";

import type {
  AiBatch,
  AiBatchCounts,
  AiBatchItem,
  AiBatchItemInput,
  AiProviders,
} from "../../blocks/ai-providers/ai-providers.ts";
import type { JobHandler } from "../../blocks/jobs/queue.ts";

import { errorText } from "../../blocks/shared.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import { nowInstant } from "../../core/temporal.ts";

/** The AI SDK batch calls, replaceable in tests. */
export interface BatchApi {
  start(
    options: Experimental_StartBatchOptions,
  ): PromiseLike<Experimental_StartBatchResult>;
  status(options: {
    provider?: Experimental_BatchProvider;
    batch: Experimental_BatchReference;
  }): PromiseLike<Experimental_BatchStatus>;
  results(options: {
    provider?: Experimental_BatchProvider;
    batch: Experimental_BatchReference;
  }): AsyncIterable<Experimental_BatchItemResult>;
  cancel(options: {
    provider?: Experimental_BatchProvider;
    batch: Experimental_BatchReference;
  }): PromiseLike<unknown>;
}

const DEFAULT_API: BatchApi = {
  start: (options) => experimental_startBatch(options),
  status: (options) => experimental_getBatchStatus(options),
  results: (options) => experimental_getBatchResults(options),
  cancel: (options) => experimental_cancelBatch(options),
};

export interface AiBatchesOptions {
  /** The providers block: a user transport for `start`, a service one for polling. */
  readonly providers: Pick<AiProviders, "batches">;
  /**
   * The batch provider, or a function that picks one for a stored reference.
   * Defaults to the global provider, or the AI Gateway.
   */
  readonly provider?:
    | Experimental_BatchProvider
    | ((
        reference: Experimental_BatchReference,
      ) => Experimental_BatchProvider | undefined);
  /** Seconds between two polls of a pending batch. Default 60. */
  readonly pollEvery?: number;
  /** Changes what is stored for an item, such as moving images to Storage first. */
  readonly onItem?: (
    item: Experimental_BatchItemResult,
    batch: AiBatch,
  ) => AiBatchItemInput | Promise<AiBatchItemInput>;
  /** Called once a batch's results are saved, or it failed. */
  readonly onDone?: (batch: AiBatch) => unknown;
  readonly api?: Partial<BatchApi>;
}

export interface AiBatches {
  /** Starts a batch and records it for the tenant, as the caller. */
  start(
    context: { readonly organizationId: string; readonly userId?: string },
    options: Experimental_StartBatchOptions & {
      readonly metadata?: Readonly<Record<string, unknown>>;
    },
  ): AsyncResult<AiBatch>;
  /** The stored batch, as the caller. */
  status(batchId: string): AsyncResult<AiBatch | undefined>;
  /** The stored results, as the caller, after `requestId` `after`. */
  results(
    batchId: string,
    options?: { readonly after?: string; readonly limit?: number },
  ): AsyncResult<readonly AiBatchItem[]>;
  /** Asks the provider for the batch's status and stores it (service role). */
  refresh(batch: AiBatch): AsyncResult<AiBatch>;
  /** Streams a finished batch's results into the table (service role). Returns how many. */
  collect(batch: AiBatch): AsyncResult<number>;
  cancel(batch: AiBatch): AsyncResult<AiBatch>;
  /** Claims due batches, refreshes them and collects finished ones. Returns how many it polled. */
  poll(options?: { readonly batch?: number }): AsyncResult<number>;
  /** A job handler that runs `poll`; schedule it every minute. */
  pollJob(options?: { readonly batch?: number }): JobHandler<unknown>;
}

const PAGE = 100;

function referenceOf(batch: AiBatch): Experimental_BatchReference | undefined {
  const reference = batch.reference;
  return reference["version"] === 2 &&
    typeof reference["id"] === "string" &&
    typeof reference["provider"] === "string"
    ? { version: 2, id: reference["id"], provider: reference["provider"] }
    : undefined;
}

function countsOf(status: Experimental_BatchStatus): AiBatchCounts | undefined {
  return status.requestCounts === undefined
    ? undefined
    : { ...status.requestCounts };
}

function jsonOf(value: unknown): unknown {
  return value === undefined ? undefined : JSON.parse(JSON.stringify(value));
}

/** What is stored for one result by default. */
export function batchItemOf(
  item: Experimental_BatchItemResult,
): AiBatchItemInput {
  if (item.status !== "succeeded") {
    return {
      requestId: item.id,
      status: item.status,
      ...(item.error === undefined ? {} : { error: item.error.message }),
    };
  }
  if (item.type === "text") {
    return {
      requestId: item.id,
      status: "succeeded",
      output: jsonOf({
        text: item.text,
        content: item.content,
        finishReason: item.finishReason,
        response: item.response,
      }),
      usage: jsonOf(item.usage),
    };
  }
  return {
    requestId: item.id,
    status: "succeeded",
    output: {
      images: item.images.map((image) => ({
        mediaType: image.mediaType,
        base64: image.base64,
      })),
    },
    usage: jsonOf(item.usage),
  };
}

/**
 * Batch jobs over the AI SDK's batch API, recorded in the providers block:
 * `start` records the batch, the poll job asks the provider for its status
 * until it finishes and then saves its results, which `results` pages.
 */
export function aiBatches(options: AiBatchesOptions): AiBatches {
  const api: BatchApi = { ...DEFAULT_API, ...options.api };
  const store = options.providers.batches;
  const pollEvery = options.pollEvery ?? 60;
  const providerFor = (
    reference: Experimental_BatchReference,
  ): { provider?: Experimental_BatchProvider } => {
    const chosen =
      typeof options.provider === "function"
        ? options.provider(reference)
        : options.provider;
    return chosen === undefined ? {} : { provider: chosen };
  };
  const nextPoll = (): Temporal.Instant =>
    nowInstant().add({ seconds: pollEvery });

  const call = <T>(run: () => PromiseLike<T>): AsyncResult<T> =>
    AsyncResult.from(async () => {
      try {
        return ok(await run());
      } catch (cause) {
        return err(
          dbError("network", errorText(cause), { hint: "AI_BATCH_PROVIDER" }),
        );
      }
    });

  const withReference = (
    batch: AiBatch,
  ): AsyncResult<Experimental_BatchReference> => {
    const reference = referenceOf(batch);
    return reference === undefined
      ? AsyncResult.err(
          dbError("invalid_input", `batch ${batch.id} has no batch reference`, {
            hint: "AI_BATCH_INVALID",
          }),
        )
      : AsyncResult.ok(reference);
  };

  const refresh = (batch: AiBatch): AsyncResult<AiBatch> =>
    withReference(batch).andThen((reference) =>
      call(() =>
        api.status({ ...providerFor(reference), batch: reference }),
      ).andThen((status) => {
        const counts = countsOf(status);
        return store.update(batch.id, {
          status: status.status,
          ...(status.rawStatus === undefined
            ? {}
            : { rawStatus: status.rawStatus }),
          ...(counts === undefined ? {} : { counts }),
          ...(status.error === undefined
            ? {}
            : { error: status.error.message }),
          ...(status.expiresAt === undefined
            ? {}
            : { expiresAt: temporal().Instant.from(status.expiresAt) }),
          nextPollAt: nextPoll(),
        });
      }),
    );

  const collect = (batch: AiBatch): AsyncResult<number> =>
    withReference(batch).andThen((reference) =>
      AsyncResult.from(async () => {
        let saved = 0;
        let page: AiBatchItemInput[] = [];
        const flush = async () => {
          if (page.length === 0) return ok(0);
          const written = await store.saveItems(batch.id, page);
          page = [];
          return written;
        };
        try {
          for await (const item of api.results({
            ...providerFor(reference),
            batch: reference,
          })) {
            page.push(
              options.onItem === undefined
                ? batchItemOf(item)
                : await options.onItem(item, batch),
            );
            if (page.length >= PAGE) {
              const written = await flush();
              if (!written.ok) return written;
              saved += written.data;
            }
          }
        } catch (cause) {
          return err(
            dbError("network", errorText(cause), {
              hint: "AI_BATCH_PROVIDER",
            }),
          );
        }
        const written = await flush();
        if (!written.ok) return written;
        saved += written.data;
        const done = await store.update(batch.id, {
          resultsSaved: true,
          nextPollAt: null,
        });
        if (!done.ok) return done;
        await options.onDone?.(done.data);
        return ok(saved);
      }),
    );

  const pollOne = (batch: AiBatch): AsyncResult<AiBatch> => {
    if (batch.status !== "pending") {
      return collect(batch).map(() => batch);
    }
    return refresh(batch).andThen((fresh) =>
      fresh.status === "pending"
        ? AsyncResult.ok(fresh)
        : collect(fresh).map(() => fresh),
    );
  };

  const poll = (pollOptions: { readonly batch?: number } = {}) =>
    store.due(pollOptions).andThen((due) =>
      AsyncResult.from(async () => {
        for (const batch of due) {
          const polled = await pollOne(batch);
          if (!polled.ok) {
            const noted = await store.update(batch.id, {
              error: polled.error.message,
            });
            if (!noted.ok) return noted;
          }
        }
        return ok(due.length);
      }),
    );

  return {
    start: (context, startOptions) => {
      const { metadata, ...batchOptions } = startOptions;
      return call(() => api.start(batchOptions)).andThen((started) =>
        store.record(context.organizationId, {
          provider: started.provider,
          reference: {
            version: started.version,
            id: started.id,
            provider: started.provider,
          },
          itemCount: batchOptions.requests.length,
          status: started.status,
          ...(context.userId === undefined ? {} : { userId: context.userId }),
          ...(metadata === undefined ? {} : { metadata }),
          ...(started.rawStatus === undefined
            ? {}
            : { rawStatus: started.rawStatus }),
          ...(started.requestCounts === undefined
            ? {}
            : { counts: { ...started.requestCounts } }),
          ...(started.expiresAt === undefined
            ? {}
            : { expiresAt: temporal().Instant.from(started.expiresAt) }),
        }),
      );
    },
    status: (batchId) => store.get(batchId),
    results: (batchId, resultOptions) => store.items(batchId, resultOptions),
    refresh,
    collect,
    cancel: (batch) =>
      withReference(batch).andThen((reference) =>
        call(() =>
          api.cancel({ ...providerFor(reference), batch: reference }),
        ).andThen(() => store.update(batch.id, { status: "cancelled" })),
      ),
    poll,
    pollJob: (jobOptions) => async () => poll(jobOptions).orThrow(),
  };
}
