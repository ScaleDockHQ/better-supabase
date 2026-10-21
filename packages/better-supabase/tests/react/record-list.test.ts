import type * as ReactModule from "react";

import { useState } from "react";
import { describe, expect, it, vi } from "vitest";

import type { ParserSpec } from "../../src/list/list-query.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { defineListQuery } from "../../src/list/index.ts";
import { useRecordListState } from "../../src/react/record-list.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { renderHook } from "../fixtures/hook-runtime.ts";

// vi.mock factories run before the imports above, so they load modules themselves.
vi.mock("react", async (importOriginal) => ({
  ...(await importOriginal<typeof ReactModule>()),
  ...(await import("../fixtures/hook-runtime.ts")).reactHooks,
}));

const betterSupabase = defineSupabase(schema);

const offset = defineListQuery(betterSupabase, "customers", {
  search: ["name"],
  facets: { status: "status" },
  sorts: {
    name: { name: "asc" },
    newest: [{ createdAt: "desc" }, { id: "asc" }],
  },
  defaultSort: "name",
  pagination: "offset",
});

const cursor = defineListQuery(betterSupabase, "customers", {
  search: ["name"],
  sorts: { name: [{ name: "asc" }, { id: "asc" }] },
  defaultSort: "name",
});

type Parser = ParserSpec<unknown>;

function fakeNuqs(initial: Readonly<Record<string, unknown>>) {
  const writes: Record<string, unknown>[] = [];

  return {
    writes,
    nuqs: {
      useQueryStates(parsers: Readonly<Record<string, Parser>>) {
        const [state, setState] = useState<Readonly<Record<string, unknown>>>(
          () =>
            Object.fromEntries(
              Object.keys(parsers).map((key) => [key, initial[key] ?? null]),
            ),
        );

        return [
          state,
          (patch: Readonly<Record<string, unknown>>) => {
            writes.push({ ...patch });
            setState((current) => ({ ...current, ...patch }));
          },
        ] as const;
      },
    },
  };
}

describe("useRecordListState", () => {
  it("turns the URL state into query params, defaults left out", () => {
    const { nuqs } = fakeNuqs({ q: "acme", sort: "name", page: 2 });

    const view = renderHook(
      () =>
        useRecordListState(
          offset,
          nuqs.useQueryStates(offset.nuqs((spec: Parser) => spec)),
        ),
      undefined,
    );

    expect(view.result.state["q"]).toBe("acme");
    expect(view.result.searchParams.toString()).toBe("q=acme&page=2");
    expect(view.result.query).toMatchObject({ q: "acme", page: 2 });
  });

  it("falls back to the defaults when the list refuses the URL state", () => {
    const { nuqs } = fakeNuqs({ sort: "oldest", status: ["active"] });

    const view = renderHook(
      () =>
        useRecordListState(
          offset,
          nuqs.useQueryStates(offset.nuqs((spec: Parser) => spec)),
        ),
      undefined,
    );

    expect(view.result.query).toEqual(offset.defaults);
  });

  it("resets the page on a change and sets or clears it on demand", () => {
    const { nuqs, writes } = fakeNuqs({ page: 3 });

    const view = renderHook(
      () =>
        useRecordListState(
          offset,
          nuqs.useQueryStates(offset.nuqs((spec: Parser) => spec)),
        ),
      undefined,
    );

    view.result.set({ sort: "newest" });
    expect(writes.at(-1)).toEqual({ sort: "newest", page: null, after: null });
    expect(view.result.searchParams.toString()).toBe("sort=newest");

    view.result.setPage(4);
    expect(writes.at(-1)).toEqual({ page: 4, after: null });

    view.result.reset();
    expect(
      Object.values(writes.at(-1) ?? {}).every((value) => value === null),
    ).toBe(true);
    expect(view.result.searchParams.toString()).toBe("");
  });

  it("pages a cursor list through `after`", () => {
    const { nuqs, writes } = fakeNuqs({});

    const view = renderHook(
      () =>
        useRecordListState(
          cursor,
          nuqs.useQueryStates(cursor.nuqs((spec: Parser) => spec)),
        ),
      undefined,
    );

    view.result.setPage("abc");
    expect(writes.at(-1)).toEqual({ page: null, after: "abc" });

    view.result.set({ q: "x" });
    expect(writes.at(-1)).toEqual({ q: "x", page: null, after: null });
  });
});
