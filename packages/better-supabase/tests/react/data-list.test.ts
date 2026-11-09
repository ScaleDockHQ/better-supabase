import { describe, expect, it, vi } from "vitest";

import type { AsyncResult } from "../../src/core/result.ts";
import type { ClientLike } from "../../src/react/hooks.ts";

import {
  defineInfiniteListHook,
  defineOneHook,
} from "../../src/react/data-hooks.ts";
import { BetterSupabaseProvider } from "../../src/react/hooks.ts";
import { renderHook } from "../fixtures/hook-runtime.ts";
import { flush, resolved } from "../fixtures/ports.ts";

vi.mock(import("react"), async (original) => ({
  ...(await original()),
  // SAFETY: hook-runtime stands in for the hooks the data controllers use.
  ...((await import("../fixtures/hook-runtime.ts")).reactHooks as object),
}));

interface Page {
  readonly items: readonly { id: string }[];
  readonly nextCursor: string | null;
  readonly hasMore: boolean;
}

interface Tickets {
  page(args: {
    readonly size: number;
    readonly after: string | null;
  }): AsyncResult<Page>;
  get(id: string): AsyncResult<{ id: string }>;
}

describe("data hooks", () => {
  it("throws without the provider", () => {
    const useOne = defineOneHook(
      "tickets",
      (db: { tickets: Tickets }) => db.tickets,
    );

    expect(() => renderHook(() => useOne("t1"), undefined)).toThrow(
      /BetterSupabaseProvider/,
    );
  });

  it("pages until the cursor runs out and reads one record", async () => {
    const pages: Page[] = [
      { items: [{ id: "a" }], nextCursor: "c1", hasMore: true },
      { items: [{ id: "b" }], nextCursor: null, hasMore: false },
    ];

    let pageCalls = 0;

    const tickets: Tickets = {
      page: () => {
        const page = pages[Math.min(pageCalls, pages.length - 1)]!;
        pageCalls += 1;

        return resolved(page);
      },
      get: (id) => resolved({ id }),
    };

    const client = {
      auth: {
        current: () => ({ status: "signed-out" }),
        subscribe: () => () => undefined,
      },
      tenant: "org-1",
      db: { tickets },
    } as unknown as ClientLike;

    const useInfinite = defineInfiniteListHook(
      "tickets",
      (db: { tickets: Tickets }) => db.tickets,
    );

    const useOne = defineOneHook(
      "tickets",
      (db: { tickets: Tickets }) => db.tickets,
    );

    const firstPage: number = 10;

    const view = renderHook((size: number) => {
      void BetterSupabaseProvider({ client });

      return { page: useInfinite({ size }), one: useOne("a") };
    }, firstPage);

    await flush();
    expect(view.result.page.items).toEqual([{ id: "a" }]);
    expect(view.result.page.hasMore).toBe(true);
    expect(view.result.page.isPending).toBe(false);
    expect(view.result.one).toMatchObject({ data: { id: "a" } });

    view.result.page.fetchNextPage();
    await flush();
    expect(view.result.page.items).toEqual([{ id: "a" }, { id: "b" }]);
    expect(view.result.page.hasMore).toBe(false);
    view.result.page.fetchNextPage();

    view.rerender(20);
    await flush();
    expect(view.result.page.items).toEqual([{ id: "b" }]);
    view.unmount();
  });

  it("ignores a page that is not a cursor payload", async () => {
    const tickets = {
      page: () => resolved({ items: "nope" }),
      get: () => resolved(null),
    };

    const client = {
      auth: {
        current: () => ({ status: "signed-out" }),
        subscribe: () => () => undefined,
      },
      tenant: "org-1",
      db: { tickets },
    } as unknown as ClientLike;

    const useInfinite = defineInfiniteListHook(
      "tickets",
      (db: { tickets: { page: () => AsyncResult<unknown> } }) => db.tickets,
    );

    const view = renderHook(() => {
      void BetterSupabaseProvider({ client });

      return useInfinite({ size: 1 });
    }, undefined);

    await flush();
    expect(view.result.items).toEqual([]);
    expect(view.result.error).toBeUndefined();
    view.unmount();
  });
});
