import type {
  Adapter,
  AdapterPostableMessage,
  ScheduledMessage,
  StateAdapter,
} from "chat";

import { ChatError } from "chat";

import type { ChatLike } from "./channels.ts";

/** A message waiting in a `ChatScheduler` for its time. */
export interface ScheduledPost {
  readonly id: string;
  /** The adapter's name, looked up with `chat.getAdapter` when it is due. */
  readonly adapter: string;
  readonly threadId: string;
  readonly message: AdapterPostableMessage;
  /** An ISO 8601 instant. */
  readonly postAt: string;
  /** Failed posts so far. */
  readonly attempts: number;
}

export interface ScheduleInput {
  readonly adapter: Adapter;
  readonly threadId: string;
  readonly message: AdapterPostableMessage;
  readonly postAt: Date;
}

export interface PublishDueOptions {
  /** Defaults to the current time. */
  readonly now?: Date;
  /** The most posts one call sends. Defaults to 100. */
  readonly limit?: number;
}

export interface PublishDueResult {
  readonly published: number;
  /** Posts that failed and wait for the next call. */
  readonly failed: number;
  /** Posts whose adapter is gone or that failed `maxAttempts` times. */
  readonly dropped: number;
}

/**
 * Holds messages for later and posts the due ones. `scheduledAdapter` gives an
 * adapter `scheduleMessage` through it, so `thread.schedule()` works on
 * adapters without native scheduling.
 */
export interface ChatScheduler {
  schedule(input: ScheduleInput): Promise<ScheduledMessage<ScheduledPost>>;
  /** The waiting posts, soonest first. */
  pending(): Promise<readonly ScheduledPost[]>;
  /** `false` when the post was already sent or cancelled. */
  cancel(id: string): Promise<boolean>;
  /**
   * Posts what is due through each post's adapter. Run it from a cron job or
   * `maintain`. A post goes out at most once unless its adapter throws; then it
   * waits for the next call.
   */
  publishDue(
    chat: Pick<ChatLike, "getAdapter">,
    options?: PublishDueOptions,
  ): Promise<PublishDueResult>;
}

export interface StateSchedulerOptions {
  /** The state key the waiting posts live under. Defaults to `chat:scheduled`. */
  readonly key?: string;
  /** Attempts before a failing post is dropped. Defaults to 3. */
  readonly maxAttempts?: number;
  /** How long to wait for the schedule's lock, in milliseconds. Defaults to 2000. */
  readonly lockWaitMs?: number;
}

const LOCK_TTL_MS = 10_000;
const LOCK_POLL_MS = 25;

const sleep = (ms: number): Promise<void> =>
  new Promise((resolve) => {
    setTimeout(resolve, ms);
  });

const byPostAt = (a: ScheduledPost, b: ScheduledPost): number =>
  Date.parse(a.postAt) - Date.parse(b.postAt);

/**
 * A `ChatScheduler` on a Chat SDK `StateAdapter`, such as
 * `createSupabaseState(...)`. The waiting posts are one value under `key`,
 * changed under the state's lock, so it suits hundreds of posts, not millions.
 */
export function stateScheduler(
  state: StateAdapter,
  options: StateSchedulerOptions = {},
): ChatScheduler {
  const key = options.key ?? "chat:scheduled";
  const maxAttempts = options.maxAttempts ?? 3;
  const lockWait = options.lockWaitMs ?? 2000;

  const read = async (): Promise<ScheduledPost[]> =>
    (await state.get<ScheduledPost[]>(key)) ?? [];

  const locked = async <T>(work: () => Promise<T>): Promise<T> => {
    const deadline = Date.now() + lockWait;

    for (;;) {
      const lock = await state.acquireLock(key, LOCK_TTL_MS);

      if (lock) {
        try {
          return await work();
        } finally {
          await state.releaseLock(lock);
        }
      }

      if (Date.now() >= deadline) {
        throw new ChatError(`stateScheduler: "${key}" stayed locked`, "LOCKED");
      }

      await sleep(LOCK_POLL_MS);
    }
  };

  const cancel = (id: string): Promise<boolean> =>
    locked(async () => {
      const posts = await read();
      const rest = posts.filter((post) => post.id !== id);

      if (rest.length === posts.length) {
        return false;
      }

      await state.set(key, rest);

      return true;
    });

  return {
    schedule: async ({ adapter, threadId, message, postAt }) => {
      if (Number.isNaN(postAt.getTime()) || postAt.getTime() <= Date.now()) {
        throw new ChatError("postAt must be in the future", "VALIDATION_ERROR");
      }

      const post: ScheduledPost = {
        id: crypto.randomUUID(),
        adapter: adapter.name,
        threadId,
        message,
        postAt: postAt.toISOString(),
        attempts: 0,
      };

      await locked(async () => {
        await state.set(key, [...(await read()), post]);
      });

      return {
        scheduledMessageId: post.id,
        channelId: adapter.channelIdFromThreadId(threadId),
        postAt,
        raw: post,
        cancel: async () => {
          await cancel(post.id);
        },
      };
    },
    pending: async () => (await read()).toSorted(byPostAt),
    cancel,
    publishDue: async (chat, publishOptions = {}) => {
      const now = (publishOptions.now ?? new Date()).getTime();
      const limit = publishOptions.limit ?? 100;

      const due = await locked(async () => {
        const posts = await read();

        const taken = posts
          .filter((post) => Date.parse(post.postAt) <= now)
          .toSorted(byPostAt)
          .slice(0, limit);

        if (taken.length > 0) {
          const ids = new Set(taken.map((post) => post.id));
          await state.set(
            key,
            posts.filter((post) => !ids.has(post.id)),
          );
        }

        return taken;
      });

      let published = 0;
      let dropped = 0;
      const retry: ScheduledPost[] = [];

      for (const post of due) {
        const adapter = chat.getAdapter(post.adapter);

        if (!adapter) {
          dropped += 1;
          continue;
        }

        try {
          await adapter.postMessage(post.threadId, post.message);
          published += 1;
        } catch {
          if (post.attempts + 1 >= maxAttempts) {
            dropped += 1;
          } else {
            retry.push({ ...post, attempts: post.attempts + 1 });
          }
        }
      }

      if (retry.length > 0) {
        await locked(async () => {
          await state.set(key, [...(await read()), ...retry]);
        });
      }

      return { published, failed: retry.length, dropped };
    },
  };
}

/** An adapter with `scheduleMessage` from a `ChatScheduler`. */
export interface ScheduledAdapter {
  scheduleMessage(
    threadId: string,
    message: AdapterPostableMessage,
    options: { readonly postAt: Date },
  ): Promise<ScheduledMessage<ScheduledPost>>;
}

/**
 * Gives `adapter` a `scheduleMessage` that holds the message in `scheduler`,
 * replacing a native one, and returns the same adapter. It changes the adapter
 * in place because Chat SDK hands threads the instance the adapter's webhook
 * passes along, not a wrapper.
 */
export function scheduledAdapter<A extends Adapter>(
  adapter: A,
  scheduler: ChatScheduler,
): Omit<A, "scheduleMessage"> & ScheduledAdapter {
  const scheduleMessage: ScheduledAdapter["scheduleMessage"] = (
    threadId,
    message,
    { postAt },
  ) => scheduler.schedule({ adapter, threadId, message, postAt });

  return Object.assign(adapter, { scheduleMessage });
}
