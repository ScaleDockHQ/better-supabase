import { describe, expect, it, vi } from "vitest";

import type { DataSource } from "../../src/bindings/data-hooks.ts";

import { defineListHook as solidList } from "../../src/solid/data-hooks.ts";
import { defineListHook as svelteList } from "../../src/svelte/data-hooks.ts";
import { defineOneHook as vueOne } from "../../src/vue/data-hooks.ts";

const registered: object[] = [];

const unread = (): never => {
  throw new Error("not read");
};

const source = { list: unread, get: unread } as unknown as DataSource;

const client = {
  db: {},
  table: (table: object) => {
    registered.push(table);

    return source;
  },
};

const context = {
  client,
  queryClient: undefined,
  auth: { value: {} },
  session: undefined,
};

vi.mock(import("../../src/vue/context.ts"), async (original) => ({
  ...(await original()),
  useContext: (() => context) as never,
}));

vi.mock(import("../../src/solid/context.ts"), async (original) => ({
  ...(await original()),
  useContext: (() => context) as never,
}));

vi.mock(import("svelte"), async (original) => ({
  ...(await original()),
  getContext: (() => context) as never,
}));

vi.mock(import("../../src/blocks/vue-bind.ts"), () => ({
  bindVueController: ((controller: unknown) => controller) as never,
}));

vi.mock(import("../../src/blocks/solid-bind.ts"), () => ({
  bindSolidController: ((controller: unknown) => controller) as never,
}));

vi.mock(import("../../src/blocks/svelte-bind.ts"), () => ({
  bindSvelteController: ((controller: unknown) => controller) as never,
}));

describe("the data hooks of every framework take a table module", () => {
  const tableModule = { key: "tickets" };

  const select = (): DataSource => {
    throw new Error("db.<table> was read");
  };

  it("reads Vue composables through client.table", () => {
    registered.length = 0;
    vueOne("tickets", select, tableModule)("t1" as never);

    expect(registered).toEqual([tableModule]);
  });

  it("reads Solid primitives through client.table", () => {
    registered.length = 0;
    solidList("tickets", select, tableModule)();

    expect(registered).toEqual([tableModule]);
  });

  it("reads Svelte stores through client.table", () => {
    registered.length = 0;
    svelteList("tickets", select, tableModule)();

    expect(registered).toEqual([tableModule]);
  });
});
