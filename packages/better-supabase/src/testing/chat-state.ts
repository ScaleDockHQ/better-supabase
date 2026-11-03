import type { Message, StateAdapter } from "chat";

import type { ConformanceReport } from "./conformance.ts";

import { conform, expect } from "./conformance.ts";

export interface TestChatStateOptions {
  /**
   * Builds a queued message, e.g. `createTestMessage(id, text)` from
   * `@chat-adapter/tests`.
   */
  readonly message: (id: string, text: string) => Message;
  /** A fresh key or thread id per call. Defaults to `conformance-<uuid>`. */
  readonly id?: () => string;
  /** The TTL the expiry checks use, in milliseconds. Defaults to 300. */
  readonly ttlMs?: number;
}

const sleep = (ms: number): Promise<void> =>
  new Promise((resolve) => {
    setTimeout(resolve, ms);
  });

/**
 * Runs the Chat SDK `StateAdapter` contract against `state`: subscriptions, one
 * lock holder at a time with token-checked release and extension, lock and
 * cache TTLs, `setIfNotExists`, list trimming, and a per-thread queue that
 * keeps the newest entries, reports its depth and drops expired ones, and a
 * delete that clears lists.
 */
export function testChatState(
  state: StateAdapter,
  options: TestChatStateOptions,
): Promise<ConformanceReport> {
  const fresh = options.id ?? (() => `conformance-${crypto.randomUUID()}`);
  const ttl = options.ttlMs ?? 300;

  const entry = (thread: string, text: string, expiresIn = 60_000) => ({
    enqueuedAt: Date.now(),
    expiresAt: Date.now() + expiresIn,
    message: options.message(`${thread}-${text}`, text),
  });

  return conform("StateAdapter", [
    [
      "subscribes and unsubscribes a thread",
      async () => {
        const thread = fresh();
        expect(!(await state.isSubscribed(thread)), "new thread is subscribed");
        await state.subscribe(thread);
        await state.subscribe(thread);
        expect(await state.isSubscribed(thread), "subscribe did not stick");
        await state.unsubscribe(thread);
        expect(
          !(await state.isSubscribed(thread)),
          "unsubscribe did not stick",
        );
      },
    ],
    [
      "gives the lock to one holder at a time",
      async () => {
        const thread = fresh();

        const [a, b] = await Promise.all([
          state.acquireLock(thread, 10_000),
          state.acquireLock(thread, 10_000),
        ]);

        expect((a === null) !== (b === null), "both or neither got the lock");
        const held = a ?? b;
        expect(held !== null, "no lock");
        expect(held.threadId === thread, "lock names another thread");
        expect(held.expiresAt > Date.now(), "lock is already expired");
        await state.releaseLock({ ...held, token: "not-the-token" });
        expect(
          (await state.acquireLock(thread, 10_000)) === null,
          "a wrong token released the lock",
        );
        expect(await state.extendLock(held, 20_000), "extendLock failed");
        await state.releaseLock(held);
        const next = await state.acquireLock(thread, 10_000);
        expect(next !== null, "released lock was not free");
        await state.forceReleaseLock(thread);
        const taken = await state.acquireLock(thread, 10_000);
        expect(taken !== null, "forceReleaseLock left the lock held");
        await state.releaseLock(next);
        expect(
          !(await state.extendLock(next, 10_000)),
          "a force-released token extended the new lock",
        );
        expect(
          (await state.acquireLock(thread, 10_000)) === null,
          "a force-released token released the new lock",
        );
      },
    ],
    [
      "lets an expired lock go",
      async () => {
        const thread = fresh();
        const lock = await state.acquireLock(thread, ttl);
        expect(lock !== null, "no lock");
        await sleep(ttl + 100);
        expect(
          !(await state.extendLock(lock, 10_000)),
          "extended an expired lock",
        );
        expect(
          (await state.acquireLock(thread, 10_000)) !== null,
          "expired lock is still held",
        );
      },
    ],
    [
      "stores values with a TTL",
      async () => {
        const key = fresh();
        expect((await state.get(key)) === null, "missing key is not null");
        await state.set(key, { n: 1, list: ["a"] });
        const stored = await state.get<{ n: number; list: string[] }>(key);
        expect(stored?.n === 1 && stored.list[0] === "a", "value changed");
        await state.set(key, "text");
        expect((await state.get(key)) === "text", "a string value changed");
        await state.delete(key);
        expect((await state.get(key)) === null, "delete left the value");
        await state.set(key, 1, ttl);
        await sleep(ttl + 100);
        expect((await state.get(key)) === null, "value outlived its TTL");
      },
    ],
    [
      "sets a key only when it is missing",
      async () => {
        const key = fresh();
        expect(await state.setIfNotExists(key, "first"), "first set failed");
        expect(!(await state.setIfNotExists(key, "second")), "second set won");
        expect((await state.get(key)) === "first", "value was replaced");
        const short = fresh();
        await state.setIfNotExists(short, "old", ttl);
        await sleep(ttl + 100);
        expect(
          await state.setIfNotExists(short, "new"),
          "an expired key blocked the set",
        );
      },
    ],
    [
      "appends to a list and keeps the newest maxLength",
      async () => {
        const key = fresh();

        for (const value of ["a", "b", "c", "d"]) {
          await state.appendToList(key, value, { maxLength: 3 });
        }

        const list = await state.getList<string>(key);
        expect(list.join(",") === "b,c,d", `list is ${list.join(",")}`);
        expect(
          (await state.getList(fresh())).length === 0,
          "missing list is not empty",
        );
      },
    ],
    [
      "delete removes a list stored under the same key",
      async () => {
        const key = fresh();
        await state.appendToList(key, "a");
        await state.delete(key);
        expect((await state.getList(key)).length === 0, "delete kept a list");
      },
    ],
    [
      "refreshes the list TTL on append and keeps it when none is given",
      async () => {
        const refreshed = fresh();
        await state.appendToList(refreshed, "a", { ttlMs: ttl });
        await sleep(Math.ceil(ttl * 0.6));
        await state.appendToList(refreshed, "b", { ttlMs: ttl });
        await sleep(Math.ceil(ttl * 0.6));

        expect(
          (await state.getList(refreshed)).join(",") === "a,b",
          "an append did not refresh the list TTL",
        );

        const kept = fresh();
        await state.appendToList(kept, "a", { ttlMs: ttl });
        await state.appendToList(kept, "b");
        await sleep(ttl + 100);
        expect(
          (await state.getList(kept)).length === 0,
          "an append without a TTL cleared the list's expiry",
        );
      },
    ],
    [
      "keeps the order of more than two list entries and maxLength 1",
      async () => {
        const key = fresh();

        for (const value of ["a", "b", "c", "d", "e"]) {
          await state.appendToList(key, value);
        }

        expect(
          (await state.getList<string>(key)).join(",") === "a,b,c,d,e",
          "list order changed",
        );

        const single = fresh();
        await state.appendToList(single, "a", { maxLength: 1 });
        await state.appendToList(single, "b", { maxLength: 1 });
        expect(
          (await state.getList<string>(single)).join(",") === "b",
          "maxLength 1 kept more than the newest entry",
        );
      },
    ],
    [
      "lets one of many parallel setIfNotExists calls win",
      async () => {
        const key = fresh();

        const results = await Promise.all(
          Array.from({ length: 10 }, (_, index) =>
            state.setIfNotExists(key, index),
          ),
        );

        expect(results.filter(Boolean).length === 1, "not exactly one winner");
      },
    ],
    [
      "queues per thread, keeps the newest maxSize and reports the depth",
      async () => {
        const thread = fresh();
        expect(
          (await state.queueDepth(thread)) === 0,
          "new queue is not empty",
        );
        expect((await state.dequeue(thread)) === null, "empty queue dequeued");
        let depth = 0;

        for (const text of ["one", "two", "three"]) {
          depth = await state.enqueue(thread, entry(thread, text), 2);
        }

        expect(
          depth === 2,
          `depth after three with maxSize 2 is ${String(depth)}`,
        );
        expect((await state.queueDepth(thread)) === 2, "queueDepth disagrees");
        const first = await state.dequeue(thread);
        expect(
          first?.message.text === "two",
          "dequeue did not return the oldest kept entry",
        );
        expect(first.message.id === `${thread}-two`, "message id changed");
        expect(
          (await state.queueDepth(thread)) === 1,
          "dequeue did not remove it",
        );
        expect(
          (await state.queueDepth(fresh())) === 0,
          "another thread shares the queue",
        );
      },
    ],
    [
      "drops expired queue entries",
      async () => {
        const thread = fresh();
        await state.enqueue(thread, entry(thread, "stale", ttl), 10);
        await sleep(ttl + 100);
        expect(
          (await state.queueDepth(thread)) === 0,
          "an expired entry counts",
        );
        const dequeued = await state.dequeue(thread);

        // An adapter may return the expired entry for the SDK to report; it
        // must not return a live one.
        expect(
          dequeued === null || dequeued.expiresAt <= Date.now(),
          "an expired entry dequeued as live",
        );
      },
    ],
  ]);
}
