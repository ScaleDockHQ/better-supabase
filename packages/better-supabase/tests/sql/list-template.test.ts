import { describe, expect, it } from "vitest";

import type { ListTemplateOptions } from "../../src/sql/list-template.ts";

import {
  filterAny,
  filterFirst,
  filterFlag,
  filterSet,
  listBody,
  listDeclare,
} from "../../src/sql/list-template.ts";

const BASE: ListTemplateOptions = {
  name: "list_things",
  from: "things",
  alias: "x",
  where: ["x.tenant = list_things.tenant"],
  keys: [
    { expr: "x.created_at", dir: "desc", type: "timestamptz" },
    { expr: "x.id", dir: "asc", type: "uuid" },
  ],
  rowJson: "to_jsonb(x)",
  invalid: (message) => `raise exception '${message}';`,
};

const EXTENDED: ListTemplateOptions = {
  ...BASE,
  sorts: {
    title: [
      { expr: "x.title", dir: "asc", type: "text" },
      { expr: "x.id", dir: "asc", type: "uuid" },
    ],
  },
  facets: { status: "x.status", kind: "x.kind" },
};

describe("list template", () => {
  it("renders a plain list without sort, facet or count statements", () => {
    const sql = `${listDeclare(BASE)}\n${listBody(BASE)}`;

    expect(sql).not.toContain("v_sort");
    expect(sql).not.toContain("v_facet");
    expect(sql).not.toContain("v_count");
    expect(sql).toContain("limit v_limit + 1 offset v_offset");
  });

  it("reads each sort in both directions and keeps the default order", () => {
    const sql = listBody(EXTENDED);

    expect(sql).toContain(
      "if v_sort is null and coalesce(v_dir, 'desc') = 'desc'",
    );
    expect(sql).toContain("v_sort is null and coalesce(v_dir, 'desc') = 'asc'");
    expect(sql).toContain(
      "v_sort = 'title' and coalesce(v_dir, 'asc') = 'asc'",
    );
    expect(sql).toContain(
      "v_sort = 'title' and coalesce(v_dir, 'asc') = 'desc'",
    );
    expect(sql).toContain("order by x.title desc, x.id asc");
    expect(sql).toContain("sort is one of title");
    expect(sql).toContain("direction is asc or desc");
  });

  it("flips only the first key for the other direction", () => {
    const sql = listBody(EXTENDED);

    expect(sql).toContain("order by x.created_at asc, x.id asc");
    expect(sql).toContain("order by x.created_at desc, x.id asc");
  });

  it("counts a facet under the list's own predicates, capped", () => {
    const sql = listBody(EXTENDED);

    expect(sql).toContain("if v_facet is not null then");
    expect(sql).toContain("facet is one of status, kind");
    expect(sql).toContain("when 'status' then (x.status)::text");
    expect(sql).toContain("when 'kind' then (x.kind)::text");
    expect(sql).toContain("limit v_total_cap + 1");
    expect(sql).toContain("limit 100");
    expect(sql).toContain("where x.tenant = list_things.tenant");
  });

  it("returns the count with its exactness", () => {
    const sql = listBody(EXTENDED);

    expect(sql).toContain("if v_count then");
    expect(sql).toContain(
      "jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap)",
    );
  });

  it("declares the extra variables only for an extended list", () => {
    expect(listDeclare(EXTENDED)).toContain("v_sort text");
    expect(listDeclare(EXTENDED)).toContain("v_facet text");
    expect(listDeclare(BASE)).not.toContain("v_sort");
  });
});

describe("list filters", () => {
  it("matches any value of a list and treats a scalar as a list of one", () => {
    const sql = filterAny("status", "x.status");

    expect(sql).toContain("not (v_filters -> 'status' is not null");
    expect(sql).toContain("jsonb_array_elements_text(v_filters -> 'status')");
    expect(sql).toContain("array[v_filters ->> 'status']");
    expect(sql).toContain("x.status = any(");
  });

  it("casts the list, not the column, so an index stays usable", () => {
    expect(filterAny("ownerId", "x.owner", "uuid")).toContain(")::uuid[])");
  });

  it("treats a missing, null or empty filter as not set", () => {
    const sql = filterSet("status");

    expect(sql).toContain("jsonb_typeof(v_filters -> 'status') <> 'null'");
    expect(sql).toContain("jsonb_array_length(v_filters -> 'status') = 0");
  });

  it("reads a flag and a single value from a list or a scalar", () => {
    expect(filterFlag("mine")).toContain("= 'true'");
    expect(filterFirst("due")).toContain("v_filters #>> '{due,0}'");
    expect(filterFirst("due")).toContain("v_filters ->> 'due'");
  });
});
