import { QueryClient } from "@tanstack/query-core";
import { beforeEach, describe, expect, it, vi } from "vitest";

import type { AsyncResult } from "../../src/core/result.ts";

import {
  useBlockMutation,
  useBlockQuery,
} from "../../src/next/offline/index.ts";
import { blockControllerEngine } from "../../src/query/blocks.ts";
import { renderHook } from "../fixtures/hook-runtime.ts";
import { flush, resolved } from "../fixtures/ports.ts";

const mocks = vi.hoisted(() => ({ offline: false }));

vi.mock(import("next/navigation.js"), () => ({
  // SAFETY: the offline hooks never touch the router.
  useRouter: () =>
    ({ push: () => undefined, refresh: () => undefined }) as never,
}));

vi.mock(import("next/offline.js"), () => ({ useOffline: () => mocks.offline }));

vi.mock(import("react"), async (original) => ({
  ...(await original()),
  // SAFETY: hook-runtime stands in for the hooks the controllers use.
  ...((await import("../fixtures/hook-runtime.ts")).reactHooks as object),
}));

const calls: string[] = [];

const tasks = {
  list(): AsyncResult<readonly string[]> {
    calls.push("list");

    return resolved(["a"]);
  },
  rename(id: string): AsyncResult<string> {
    calls.push(`rename:${id}`);

    return resolved(id);
  },
};

beforeEach(() => {
  calls.length = 0;
  mocks.offline = false;
});

describe("next/client offline block hooks", () => {
  it("reads as usual while online", async () => {
    const view = renderHook(() => useBlockQuery(tasks, "list", []), undefined);
    await flush();

    expect(calls).toEqual(["list"]);
    expect(view.result.data).toEqual(["a"]);
    expect(view.result.offline).toBeUndefined();
    view.unmount();
  });

  it("pauses the read and shows offline instead of an error when offline", async () => {
    mocks.offline = true;

    const view = renderHook(() => useBlockQuery(tasks, "list", []), undefined);
    await flush();

    expect(calls).toEqual([]);
    expect(view.result).toMatchObject({ offline: true, error: undefined });

    mocks.offline = false;
    view.rerender(undefined);
    await flush();

    expect(calls).toEqual(["list"]);
    expect(view.result).toMatchObject({ data: ["a"], offline: false });
    view.unmount();
  });

  it("queues a write while offline and sends it on reconnect", async () => {
    mocks.offline = true;

    const view = renderHook(() => useBlockMutation(tasks, "rename"), undefined);

    const pending = view.result.mutate("t1");
    expect(calls).toEqual([]);

    mocks.offline = false;
    view.rerender(undefined);

    const result = await pending;

    expect(result.ok && result.data).toBe("t1");
    expect(calls).toEqual(["rename:t1"]);
    view.unmount();
  });

  it("runs a double effect once", async () => {
    mocks.offline = true;
    const view = renderHook(() => useBlockQuery(tasks, "list", []), undefined);
    view.rerender(undefined);
    view.rerender(undefined);
    await flush();

    expect(calls).toEqual([]);
    view.unmount();
  });

  it("keeps reads and writes in a data engine when given one", async () => {
    const engine = blockControllerEngine(new QueryClient());
    const options = { engine, instance: "tasks" } as const;

    const read = renderHook(
      () => useBlockQuery(tasks, "list", [], options),
      undefined,
    );

    await flush();
    expect(read.result.data).toEqual(["a"]);
    read.unmount();

    const write = renderHook(
      () => useBlockMutation(tasks, "rename", options),
      undefined,
    );

    const result = await write.result.mutate("t2");
    expect(result.ok && result.data).toBe("t2");
    write.unmount();
  });
});
