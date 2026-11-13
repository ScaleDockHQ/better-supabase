import type { BlockHooks } from "./block-hooks.ts";
import type { Logger } from "./logger.ts";

/**
 * Starts a block's processing pass right after a successful write, instead of
 * waiting for the next cron or drain call. The cron stays the fallback.
 *
 * ```ts
 * const inbox = createWebhookInbox({
 *   ...options,
 *   kick: { waitUntil: bsb.waitUntil, run: () => inbox.process(handle) },
 * });
 * ```
 */
export interface Kick<K extends string = string> {
  /**
   * Keeps the pass alive after the response: `bsb.waitUntil` in Next, a Workers
   * `ctx.waitUntil`, or `EdgeRuntime.waitUntil`.
   */
  readonly waitUntil: (work: Promise<unknown>) => void;
  /**
   * The pass: `inbox.process(handler)`, `outbox.relay(...)` or, for a queue,
   * `queue.drain({ queue, handler })` for the queue that got the job.
   */
  readonly run: (key: K) => PromiseLike<unknown>;
}

/**
 * A function that schedules `kick.run(key)`. Writes made while a pass for the
 * same key waits to start share it; a write made while a pass runs queues one
 * more, so a row that pass missed still gets processed. A throwing pass is
 * logged.
 */
export function kicker<K extends string>(
  kick: Kick<K>,
  logger: Logger,
  block: string,
): (key: K) => void {
  const waiting = new Set<K>();
  const tails = new Map<K, Promise<void>>();

  const keepAlive = (work: Promise<void>): void => {
    try {
      kick.waitUntil(work);
    } catch (cause) {
      logger.warn(`${block} kick: waitUntil is unavailable`, { cause });
    }
  };

  return (key) => {
    const tail = tails.get(key);

    if (tail && waiting.has(key)) {
      keepAlive(tail);

      return;
    }

    waiting.add(key);

    const next = (tail ?? Promise.resolve()).then(async () => {
      waiting.delete(key);

      try {
        await kick.run(key);
      } catch (cause) {
        logger.error(`${block} kick failed`, { cause });
      }
    });

    tails.set(key, next);
    void next.then(() => {
      if (tails.get(key) === next) {
        tails.delete(key);
      }
    });
    keepAlive(next);
  };
}

/**
 * `after` hooks that call `fire` on each successful call of `methods`, keyed by
 * `keyOf` of the call's arguments. Undefined without `fire`.
 */
export function kickHooks<C extends object, K extends string>(
  fire: ((key: K) => void) | undefined,
  methods: readonly (keyof BlockHooks<C>)[],
  keyOf: (args: readonly unknown[]) => K,
): BlockHooks<C> | undefined {
  if (fire === undefined) {
    return undefined;
  }

  const after = {
    after: (result: { readonly ok: boolean }, args: readonly unknown[]) => {
      if (result.ok) {
        fire(keyOf(args));
      }
    },
  };

  const hooks: Record<string, unknown> = Object.fromEntries(
    methods.map((method) => [method, after]),
  );

  // SAFETY: each hook only reads `ok` from the result and passes the arguments
  // to keyOf, so it fits every method's hook type.
  return hooks as BlockHooks<C>;
}
