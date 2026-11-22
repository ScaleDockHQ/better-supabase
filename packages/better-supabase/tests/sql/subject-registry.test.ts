import { describe, expect, it } from "vitest";

import { tenantNames } from "../../src/core/entity-naming.ts";
import {
  auditedSubjects,
  checkCall,
  logsSubjectReads,
  registeredIdMatches,
  registeredSubjects,
  subjectColumns,
  teamActions,
  tenantColumnOf,
  urlExpression,
} from "../../src/sql/subject-registry.ts";

const one = (entry: Record<string, unknown>, type = "order"): unknown =>
  registeredSubjects({ [type]: { table: "public.orders", ...entry } });

describe("registeredSubjects errors", () => {
  it.each([
    [{}, "Order", /lowercase letters, digits, hyphens/u],
    [{ table: "a.b.c" }, "order", /subjects\.order\.table must be "table"/u],
    [{ table: "Orders" }, "order", /subjects\.order\.table must be a column/u],
    [{ id: "Bad" }, "order", /subjects\.order\.id must be a column name/u],
    [{ idType: "1x" }, "order", /idType must be a type name/u],
    [{ tenant: 3 }, "order", /subjects\.order\.tenant must be a column/u],
    [{ title: "X" }, "order", /subjects\.order\.title must be a column/u],
    [{ deletedAt: "-" }, "order", /deletedAt must be a column/u],
    [{ template: "T" }, "order", /subjects\.order\.template must be/u],
    [{ template: { column: "T" } }, "order", /template\.column must be/u],
    [
      { template: { column: "t", children: [{ column: "c", table: "A" }] } },
      "order",
      /template\.children\[0\]\.table must be "table" or "schema\.table"/u,
    ],
    [{ url: "/o/{Id}" }, "order", /subjects\.order\.url \{Id\} must be/u],
    [
      { readAccess: "all" },
      "order",
      /readAccess must be "tenant" or "record"/u,
    ],
    [{ team: { actions: [] } }, "order", /team must be \{ actions/u],
    [
      { team: { actions: ["read"] }, tenant: false },
      "order",
      /team needs a tenant column/u,
    ],
    [{ auditReads: "yes" }, "order", /auditReads must be true or false/u],
    [
      { auditReads: true, tenant: false },
      "order",
      /auditReads needs a tenant column/u,
    ],
    [
      { tenant: false, permissions: { read: "orders.read" } },
      "order",
      /permissions need a tenant column or a scope/u,
    ],
    [{ rank: { column: "R" } }, "order", /rank\.column must be/u],
    [{ rank: { column: "r", group: "G" } }, "order", /rank\.group must be/u],
    [{ search: { title: "T" } }, "order", /subjects\.order\.search must be/u],
    [
      { search: { from: { view: 3, key: "id" } } },
      "order",
      /search\.from\.view must be "table" or "schema\.table"/u,
    ],
    [
      { search: { from: { view: "a.b.c", key: "id" } } },
      "order",
      /search\.from\.view must be "table" or "schema\.table"/u,
    ],
    [
      { search: { watch: [{ table: "lines", key: "order_id", via: "V" }] } },
      "order",
      /search\.watch\[0\]\.via must be/u,
    ],
    [
      { search: { watch: [{ table: "lines", key: "k", columns: ["C"] }] } },
      "order",
      /search\.watch\[0\]\.columns\[0\] must be/u,
    ],
    [
      {
        search: {
          watch: [
            {
              table: "lines",
              key: "k",
              through: [{ table: "x", from: "a", to: "B" }],
            },
          ],
        },
      },
      "order",
      /search\.watch\[0\]\.through\[0\]\.to must be/u,
    ],
  ])("rejects %j on %s", (entry, type, message) => {
    expect(() => one(entry, type)).toThrow(message);
  });

  it.each([
    ["Read", "orders.read", /use an action name with a permission key/u],
    ["read", "", /use an action name with a permission key/u],
    ["read", 3, /use a permission key or \{ key, rows/u],
    ["read", ["a"], /use a permission key or \{ key, rows/u],
    ["read", { nope: 1 }, /read\.nope is not an option/u],
    ["read", { key: "a", also: "" }, /also must be a permission key/u],
    ["read", { key: "" }, /key must be a permission key/u],
    [
      "read",
      { key: "a", rows: "Bad" },
      /rows must be the provider's SQL name/u,
    ],
    ["read", { rows: "file_node", owner: "x" }, /rows needs the key/u],
    ["read", { owner: "Bad" }, /permissions\.read\.owner must be a column/u],
    ["read", { check: "nodot" }, /check must be a schema-qualified function/u],
    ["read", {}, /needs a key, an owner column or a check/u],
  ])("rejects permission %s: %j", (action, value, message) => {
    expect(() => one({ permissions: { [action]: value } })).toThrow(message);
  });
});

describe("registeredSubjects", () => {
  it("quotes the table, id and renamed tenant", () => {
    expect(
      registeredSubjects(
        { order: { table: "sales.orders", id: "order_id" } },
        tenantNames("workspace"),
      ),
    ).toEqual([
      expect.objectContaining({
        schema: "sales",
        table: "orders",
        qualified: '"sales"."orders"',
        id: '"order_id"',
        tenant: '"workspace_id"',
      }),
    ]);
  });

  it("accepts a full entry", () => {
    const [subject] = registeredSubjects({
      order: {
        table: "orders",
        tenant: false,
        scope: "platform",
        idType: "bigint",
        permissions: {
          read: { key: "orders.read", rows: "file_node", also: "x.y" },
          edit: { owner: "owner_id", check: "app.can_edit" },
        },
        search: {
          from: { view: "app.order_search", key: "id" },
          watch: [
            {
              table: "lines",
              key: "order_id",
              via: "order_id",
              columns: ["name"],
              through: [{ table: "app.links", from: "a", to: "b" }],
            },
          ],
        },
      },
    } as never);

    expect(subject?.tenant).toBeUndefined();
    expect(teamActions(subject!)).toEqual([]);
    expect(registeredIdMatches(subject!, "$1", "o")).toBe(
      'o."id" = ($1)::bigint',
    );
  });
});

describe("subject helpers", () => {
  const [audited, plain] = registeredSubjects({
    order: { table: "orders", auditReads: true, team: { actions: ["read"] } },
    note: { table: "notes" },
  });

  it("pick the audited types and team actions", () => {
    expect(auditedSubjects([audited!, plain!]).map((s) => s.type)).toEqual([
      "order",
    ]);
    expect(teamActions(audited!)).toEqual(["read"]);
    expect(teamActions(plain!)).toEqual([]);
    expect(logsSubjectReads(undefined)).toBe(false);
    expect(logsSubjectReads({ order: { table: "o", auditReads: true } })).toBe(
      true,
    );
    expect(
      logsSubjectReads({
        order: { table: "o", auditReads: true, tenant: false },
      } as never),
    ).toBe(false);
  });

  it("render ids, checks and urls", () => {
    expect(registeredIdMatches(plain!, "$1")).toBe('s."id"::text = $1');
    expect(checkCall("app.can_edit", '"id"')).toBe('"app"."can_edit"(s."id")');
    expect(urlExpression("")).toBe("''");
    expect(urlExpression("/orders/{id}/lines", "o")).toBe(
      "'/orders/' || o.\"id\"::text || '/lines'",
    );
    expect(urlExpression("{id}")).toBe('s."id"::text');
  });

  it("find the tenant column of a table", () => {
    const subjects = {
      order: { table: "orders", tenant: "shop_id" },
      log: { table: "audit.logs", tenant: false },
    } as never;

    expect(tenantColumnOf("public.orders", subjects)).toBe("shop_id");
    expect(tenantColumnOf("audit.logs", subjects)).toBeUndefined();
    expect(tenantColumnOf("lines", subjects, tenantNames(), "x_id")).toBe(
      "x_id",
    );
    expect(tenantColumnOf("lines", subjects)).toBe("organization_id");
  });

  it("list every column an entry names", () => {
    expect(
      subjectColumns(
        {
          table: "orders",
          title: "name",
          deletedAt: "deleted_at",
          template: { column: "template_id" },
          url: "/o/{slug}",
          rank: { column: "rank", group: "list_id" },
          search: {
            title: "name",
            body: ["notes"],
            facets: ["status"],
            description: "summary",
            exclude: "hidden",
            watch: [{ table: "lines", key: "order_id", via: "order_id" }],
          },
          permissions: { edit: { owner: "owner_id" }, read: "orders.read" },
        },
        "workspace",
      ),
    ).toEqual([
      ["id", "id"],
      ["tenant", "workspace_id"],
      ["title", "name"],
      ["deletedAt", "deleted_at"],
      ["template.column", "template_id"],
      ["url {slug}", "slug"],
      ["rank.column", "rank"],
      ["rank.group", "list_id"],
      ["search.title", "name"],
      ["search.body", "notes"],
      ["search.facets", "status"],
      ["search.description", "summary"],
      ["search.exclude", "hidden"],
      ["search.watch.via", "order_id"],
      ["permissions.edit.owner", "owner_id"],
    ]);
    expect(
      subjectColumns({
        table: "orders",
        tenant: false,
        template: "template_id",
        search: { from: { view: "v", key: "id" }, title: "name" },
      } as never),
    ).toEqual([
      ["id", "id"],
      ["template", "template_id"],
    ]);
  });
});
