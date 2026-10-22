import { describe, expect, it } from "vitest";

import {
  createSavedViews,
  defaultView,
  displayStateOf,
  queryFromUrlState,
  SAVED_VIEW_KINDS,
  SAVED_VIEW_SCOPES,
  sameDisplayState,
  sameQuery,
  savedViewIssues,
  savedViewStateSchema,
  urlStateFromQuery,
} from "../../../src/blocks/saved-views/index.ts";
import { defineSupabase } from "../../../src/core/define.ts";
import { defineListQuery } from "../../../src/list/index.ts";
import {
  SAVED_VIEW_KINDS as SQL_KINDS,
  SAVED_VIEW_SCOPES as SQL_SCOPES,
} from "../../../src/sql/modules/saved-views.ts";
import { schema } from "../../fixtures/generated-camel.ts";

const tasks = defineListQuery(defineSupabase(schema), "customers", {
  search: ["name"],
  facets: { status: "status" },
  sorts: { newest: { createdAt: "desc" }, name: { name: "asc" } },
  defaultSort: "newest",
});

function transport(results: Record<string, unknown>) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];

  return {
    calls,
    call(schema: string, fn: string, args: Record<string, unknown>) {
      expect(schema).toBe("app");
      calls.push({ fn, args });

      return Promise.resolve(results[fn]);
    },
  };
}

describe("saved views client", () => {
  it("keeps the SQL module's kinds and scopes", () => {
    expect(SAVED_VIEW_KINDS).toEqual(SQL_KINDS);
    expect(SAVED_VIEW_SCOPES).toEqual(SQL_SCOPES);
  });

  it("saves a checked state without the page", async () => {
    const fake = transport({ save_view: { id: "v1", rank: "V" } });

    const views = createSavedViews({
      transport: fake,
      schema: "app",
      lists: { tasks },
    });

    const saved = await views
      .upsert({
        organizationId: "org",
        list: "tasks",
        name: "Open",
        state: {
          query: { facets: { status: ["active"] }, page: 3 } as never,
          density: "compact",
        },
      })
      .orThrow();

    expect(saved).toEqual({ id: "v1", rank: "V", fields: {} });
    expect(fake.calls[0]).toEqual({
      fn: "save_view",
      args: {
        tenant: "org",
        list: "tasks",
        name: "Open",
        kind: "table",
        scope: "user",
        team: null,
        state: {
          query: { facets: { status: ["active"] } },
          density: "compact",
        },
        view_id: null,
      },
    });
  });

  it("refuses a query the list rejects, without a call", async () => {
    const fake = transport({});

    const views = createSavedViews({
      transport: fake,
      schema: "app",
      lists: { tasks },
    });

    const result = await views.upsert({
      organizationId: "org",
      list: "tasks",
      name: "Bad",
      state: { query: { sort: "nope" } },
    });

    expect(result.ok).toBe(false);
    expect(result.ok ? undefined : result.error.kind).toBe("validation");
    expect(fake.calls).toEqual([]);
  });

  it("lists, reorders, defaults and deletes", async () => {
    const fake = transport({
      list_views: [
        {
          id: "v1",
          list: "tasks",
          scope: "tenant",
          ownerId: null,
          teamId: null,
          name: "All",
          kind: "board",
          state: { density: "compact" },
          rank: "V",
          isDefault: true,
        },
      ],
      rank_view: true,
      set_default_view: true,
      delete_view: true,
    });

    const views = createSavedViews({ transport: fake, schema: "app" });
    const [view] = await views.list("org", "tasks").orThrow();
    expect(view).toMatchObject({
      scope: "tenant",
      kind: "board",
      preference: { isDefault: false, hidden: false, pinned: false },
    });
    expect(await views.reorder("v1", { previous: "V" }).orThrow()).toBe("k");
    expect(await views.setDefault("v1").orThrow()).toBe(true);
    expect(await views.delete("v1").orThrow()).toBe(true);
    expect(fake.calls.map((call) => call.fn)).toEqual([
      "list_views",
      "rank_view",
      "set_default_view",
      "delete_view",
    ]);
  });

  it("reads the caller's preference from a listed view", async () => {
    const fake = transport({
      list_views: [
        {
          id: "v1",
          list: "tasks",
          scope: "tenant",
          name: "All",
          kind: "table",
          state: {},
          rank: "V",
          isDefault: false,
          preference: { isDefault: true, hidden: false, pinned: true },
        },
      ],
    });

    const views = createSavedViews({ transport: fake, schema: "app" });
    const [view] = await views.list("org", "tasks").orThrow();
    expect(view?.preference).toEqual({
      isDefault: true,
      hidden: false,
      pinned: true,
    });
  });

  it("sets a preference, passing null for the flags it keeps", async () => {
    const fake = transport({
      set_view_preference: {
        viewId: "v1",
        isDefault: true,
        hidden: false,
        pinned: false,
      },
    });

    const views = createSavedViews({ transport: fake, schema: "app" });
    expect(
      await views.setPreference("v1", { isDefault: true }).orThrow(),
    ).toEqual({ isDefault: true, hidden: false, pinned: false });
    expect(fake.calls[0]).toEqual({
      fn: "set_view_preference",
      args: { view_id: "v1", make_default: true, hide: null, pin: null },
    });
  });

  it("duplicates a view as a personal copy by default", async () => {
    const fake = transport({ duplicate_view: { id: "v2", rank: "k" } });
    const views = createSavedViews({ transport: fake, schema: "app" });
    expect(await views.duplicate("v1").orThrow()).toEqual({
      id: "v2",
      rank: "k",
      fields: {},
    });
    await views
      .duplicate("v1", { name: "Team copy", scope: "team", teamId: "t1" })
      .orThrow();
    expect(fake.calls.map((call) => call.args)).toEqual([
      { view_id: "v1", scope: "user", name: null, team: null },
      { view_id: "v1", scope: "team", name: "Team copy", team: "t1" },
    ]);
  });
});

describe("saved view state", () => {
  it("names each invalid part", () => {
    expect(
      savedViewIssues({
        columns: { visible: [1], sizes: { a: "x" }, pinned: { left: 2 } },
        grouping: "status",
        density: "huge",
        layout: [],
        query: "x",
      }).map((issue) => issue.path?.join(".")),
    ).toEqual([
      "columns.visible",
      "columns.sizes",
      "columns.pinned",
      "grouping",
      "density",
      "layout",
      "query",
    ]);
    expect(savedViewIssues([])).toEqual([
      { message: "state must be an object" },
    ]);
    expect(savedViewIssues({ columns: [] })[0]?.path).toEqual(["columns"]);
  });

  it("prefixes the list's issues with query", () => {
    const issues = savedViewIssues({ query: { sort: "nope" } }, tasks);
    expect(issues[0]?.path?.[0]).toBe("query");
  });

  it("puts the list's schema under query", () => {
    const schema = savedViewStateSchema(tasks) as {
      properties: { query: unknown };
    };

    expect(schema.properties.query).toBe(tasks.jsonSchema);
    expect(
      (savedViewStateSchema() as { properties: { query: unknown } }).properties
        .query,
    ).toEqual({ type: "object" });
  });

  it("opens the user's default before a team's and the tenant's", () => {
    const views = [
      { id: "t", scope: "tenant", isDefault: true },
      { id: "m", scope: "team", isDefault: true },
      { id: "u", scope: "user", isDefault: true },
    ] as const;

    expect(defaultView(views)?.id).toBe("u");
    expect(defaultView(views.slice(0, 2))?.id).toBe("m");
    expect(
      defaultView([{ id: "x", scope: "user", isDefault: false }])?.id,
    ).toBe("x");
    const none: (typeof views)[number][] = [];
    expect(defaultView(none)).toBeUndefined();
  });

  it("opens the caller's preferred view first and skips hidden ones", () => {
    const views = [
      { id: "u", scope: "user", isDefault: true },
      {
        id: "t",
        scope: "tenant",
        isDefault: false,
        preference: { isDefault: true },
      },
    ] as const;

    expect(defaultView(views)?.id).toBe("t");
    expect(
      defaultView([
        {
          id: "u",
          scope: "user",
          isDefault: true,
          preference: { hidden: true },
        },
        { id: "m", scope: "team", isDefault: true },
      ])?.id,
    ).toBe("m");
    expect(
      defaultView([
        {
          id: "h",
          scope: "tenant",
          isDefault: false,
          preference: { hidden: true },
        },
      ]),
    ).toBeUndefined();
  });
});

describe("display state", () => {
  it("drops the query and compares the rest", () => {
    expect(displayStateOf({ query: { q: "x" }, density: "compact" })).toEqual({
      density: "compact",
    });
    expect(
      sameDisplayState(
        { query: { q: "x" }, columns: { order: ["b", "a"] }, grouping: [] },
        { grouping: [], columns: { order: ["b", "a"] } },
      ),
    ).toBe(true);
    expect(
      sameDisplayState(
        { columns: { order: ["a", "b"] } },
        { columns: { order: ["b", "a"] } },
      ),
    ).toBe(false);
    expect(sameDisplayState(undefined, {})).toBe(true);
  });
});

describe("URL state", () => {
  it("reads nuqs values into a stored query", () => {
    expect(
      queryFromUrlState({
        q: "bug",
        sort: "title",
        page: 2,
        after: null,
        size: 50,
        filter: { kind: "group", op: "and", rules: [] },
        status: ["open"],
        assignee: [],
      }),
    ).toEqual({
      q: "bug",
      sort: "title",
      size: 50,
      filter: { kind: "group", op: "and", rules: [] },
      facets: { status: ["open"] },
    });
    expect(queryFromUrlState({ q: "", sort: null })).toEqual({});
  });

  it("writes every key, clearing what the query leaves out", () => {
    expect(
      urlStateFromQuery({ sort: "title", facets: { status: ["done"] } }, [
        "q",
        "sort",
        "page",
        "after",
        "size",
        "filter",
        "status",
        "assignee",
      ]),
    ).toEqual({
      q: null,
      sort: "title",
      page: null,
      after: null,
      size: null,
      filter: null,
      status: ["done"],
      assignee: null,
    });
    expect(urlStateFromQuery(undefined, ["q"])).toEqual({ q: null });
  });

  it("compares queries without the page, key order or empty facets", () => {
    expect(
      sameQuery(
        { sort: "title", facets: { status: ["open"], a: [] }, page: 2 },
        { facets: { status: ["open"] }, sort: "title" },
      ),
    ).toBe(true);
    expect(sameQuery(undefined, { facets: {} })).toBe(true);
    expect(sameQuery({ q: "a" }, { q: "b" })).toBe(false);
  });
});
