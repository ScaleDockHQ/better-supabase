import type { StreamStore } from "./store.ts";
import type { TeeToStoreOptions } from "./tee.ts";

import { teeToStore, writeToStore } from "./tee.ts";

/**
 * The context `resumable-stream` returns from `createResumableStreamContext`,
 * typed structurally so the package stays optional. The AI SDK's
 * `consumeSseStream` and resume routes call these methods. It matches the
 * package: `resumeExistingStream` resolves `undefined` for a stream that was
 * never created and `null` for one that finished.
 */
export interface ResumableStreamContext {
  /**
   * Creates the stream and returns it, or resumes the one under `streamId`.
   * Resolves `null` when it already finished.
   */
  resumableStream(
    streamId: string,
    makeStream: () => ReadableStream<string>,
    skipCharacters?: number,
  ): Promise<ReadableStream<string> | null>;
  createNewResumableStream(
    streamId: string,
    makeStream: () => ReadableStream<string>,
    skipCharacters?: number,
  ): Promise<ReadableStream<string> | null>;
  resumeExistingStream(
    streamId: string,
    skipCharacters?: number,
  ): Promise<ReadableStream<string> | null | undefined>;
  hasExistingStream(streamId: string): Promise<null | true | "DONE">;
}

export interface ResumableStreamAdapterOptions extends TeeToStoreOptions {
  /**
   * Runs the promise that settles when every chunk is stored, so it outlives
   * the response: `waitUntil` or `after`.
   */
  readonly waitUntil?: (promise: Promise<unknown>) => void;
  /**
   * Replays a finished stream instead of resolving `null`, as versions before
   * 0.48 did: a client that reconnects after the end gets the whole text.
   * Default `false`, which is what `resumable-stream` does.
   */
  readonly replayFinished?: boolean;
}

/** Drops the first `count` characters of a text stream. */
function skipCharacters(
  source: ReadableStream<string>,
  count: number,
): ReadableStream<string> {
  if (count <= 0) {
    return source;
  }

  let left = count;

  return source.pipeThrough(
    new TransformStream<string, string>({
      transform(chunk, controller) {
        if (left <= 0) {
          controller.enqueue(chunk);

          return;
        }

        if (chunk.length <= left) {
          left -= chunk.length;

          return;
        }

        controller.enqueue(chunk.slice(left));
        left = 0;
      },
    }),
  );
}

/**
 * A `resumable-stream` context on a `StreamStore`, so the AI SDK's resume route
 * works without Redis. A new stream is teed into the store while the response
 * streams; a reconnect replays the stored text from the character offset the
 * client already has.
 */
export function resumableStreamContext(
  store: StreamStore,
  options: ResumableStreamAdapterOptions = {},
): ResumableStreamContext {
  const { waitUntil, replayFinished = false, ...tee } = options;

  const statusOf = async (streamId: string) => {
    const status = await store.status(streamId);

    if (!status.ok) {
      throw new Error(status.error.message);
    }

    return status.data;
  };

  const create: ResumableStreamContext["createNewResumableStream"] = (
    streamId,
    makeStream,
    skip = 0,
  ) => {
    const teed = teeToStore(store, streamId, makeStream(), tee);
    waitUntil?.(Promise.resolve(teed.persisted));

    return Promise.resolve(skipCharacters(teed.stream, skip));
  };

  const resume: ResumableStreamContext["resumeExistingStream"] = async (
    streamId,
    skip = 0,
  ) => {
    const status = await statusOf(streamId);

    if (status === undefined) {
      return;
    }

    if (status.closed && !replayFinished) {
      return null;
    }

    return skipCharacters(store.read(streamId, 0), skip);
  };

  return {
    createNewResumableStream: create,
    resumeExistingStream: resume,
    async resumableStream(streamId, makeStream, skip = 0) {
      const resumed = await resume(streamId, skip);

      return resumed === undefined
        ? create(streamId, makeStream, skip)
        : resumed;
    },
    async hasExistingStream(streamId) {
      const status = await statusOf(streamId);

      if (status === undefined) {
        return null;
      }

      return status.closed ? "DONE" : true;
    },
  };
}

export interface ConsumeSseStreamOptions extends TeeToStoreOptions {
  /** The id to store the stream under. Default: a random UUID. */
  readonly streamId?: string | (() => string);
  /**
   * Called with the id before the first chunk is stored, so the app can save it
   * (such as `conversations.setActiveStream`) for the resume route.
   */
  readonly onStreamId?: (streamId: string) => void | PromiseLike<void>;
  /** Keeps the copy alive after the response ends: `waitUntil` or `after`. */
  readonly waitUntil?: (promise: Promise<unknown>) => void;
}

/**
 * The `consumeSseStream` option of `createUIMessageStreamResponse` and
 * `toUIMessageStreamResponse`: it stores the response's SSE text in `store`, so
 * an app that doesn't use a resumable stream context can still serve
 * `resumeFromStore` after a disconnect.
 */
export function consumeSseStreamInto(
  store: StreamStore,
  options: ConsumeSseStreamOptions = {},
): (input: { readonly stream: ReadableStream<string> }) => Promise<void> {
  const { streamId, onStreamId, waitUntil, ...tee } = options;

  return async ({ stream }) => {
    const id =
      typeof streamId === "function"
        ? streamId()
        : (streamId ?? crypto.randomUUID());

    await onStreamId?.(id);

    const persisted = Promise.resolve(writeToStore(store, id, stream, tee));
    waitUntil?.(persisted);
    void persisted.catch(() => {});
  };
}
