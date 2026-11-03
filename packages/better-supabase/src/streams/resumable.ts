import type { StreamStore } from "./store.ts";
import type { TeeToStoreOptions } from "./tee.ts";

import { teeToStore } from "./tee.ts";

/**
 * The context `resumable-stream` returns from `createResumableStreamContext`,
 * typed structurally so the package stays optional. The AI SDK's
 * `consumeSseStream` and resume routes call these three methods.
 */
export interface ResumableStreamContext {
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
  const { waitUntil, ...tee } = options;

  return {
    createNewResumableStream(streamId, makeStream, skip = 0) {
      const teed = teeToStore(store, streamId, makeStream(), tee);
      const settled = Promise.resolve(teed.persisted);
      waitUntil?.(settled);

      return Promise.resolve(skipCharacters(teed.stream, skip));
    },
    async resumeExistingStream(streamId, skip = 0) {
      const status = await store.status(streamId);

      if (!status.ok) {
        throw new Error(status.error.message);
      }

      if (status.data === undefined) {
        return null;
      }

      return skipCharacters(store.read(streamId, 0), skip);
    },
    async hasExistingStream(streamId) {
      const status = await store.status(streamId);

      if (!status.ok) {
        throw new Error(status.error.message);
      }

      if (status.data === undefined) {
        return null;
      }

      return status.data.closed ? "DONE" : true;
    },
  };
}
