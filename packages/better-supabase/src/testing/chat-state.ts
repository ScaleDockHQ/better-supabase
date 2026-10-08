import type { Message, StateAdapter } from "chat";

import { type ConformanceReport, conform, expect } from "./conformance.ts";

export interface TestChatStateOptions {
  /** Builds a queued message, e.g. `createTestMessage(id, text)` from `@chat-adapter/tests`. */
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
 * Runs the Chat SDK `StateAdapter` contract against `state`: subscriptions,
 * one lock holder at a time with token-checked release and extension, lock
 * and cache TTLs, `setIfNotExists`, list trimming, and a per-thread queue
 * that keeps the newest entries, reports its depth and drops expired ones.
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
        expect(
          (await state.acquireLock(thread, 10_000)) !== null,
          "forceReleaseLock left the lock held",
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
        for (const value of ["a", "b", "c", "d"])
          await state.appendToList(key, value, { maxLength: 3 });
        const list = await state.getList<string>(key);
        expect(list.join() === "b,c,d", `list is ${list.join()}`);
        expect(
          (await state.getList(fresh())).length === 0,
          "missing list is not empty",
        );
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
        for (const text of ["one", "two", "three"])
          depth = await state.enqueue(thread, entry(thread, text), 2);
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
        expect(
          (await state.dequeue(thread)) === null,
          "an expired entry dequeued",
        );
      },
    ],
  ]);
}
