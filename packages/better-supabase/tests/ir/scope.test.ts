import { describe, expect, it } from "vitest";

import type { ScopeFor } from "../../src/ir/scope.ts";
import type {
  Condition,
  Include,
  Operation,
  Selection,
} from "../../src/ir/types.ts";
import type { TableMeta } from "../../src/schema/types.ts";

import {
  scopeCondition,
  scopeOperation,
  scopeSelection,
} from "../../src/ir/scope.ts";
import { column } from "../../src/ir/types.ts";
import { schema } from "../fixtures/generated-camel.ts";

function table(key: string): TableMeta {
  const found = schema.meta.tables[key];
  if (!found) throw new Error(`No fixture table ${key}`);
  return found;
}

const customers = table("customers");
const notes = table("notes");
const organizations = table("organizations");

const live = column("archived_at", "is", null);
const tenant = column("organization_id", "eq", "o1");

/** Customers are soft-deleted, notes are tenant-scoped, organizations are unscoped. */
const scopeFor: ScopeFor = (target) =>
  target.key === "customers"
    ? live
    : target.key === "notes"
      ? tenant
      : undefined;

const body = column("body", "eq", "x");

function onNotes(
  quantifier: "some" | "none" | "every",
  where: Condition | undefined,
): Condition {
  const relation = customers.relations["notes"];
  if (!relation) throw new Error("No notes relation");
  return {
    kind: "relation",
    name: "notes",
    relation,
    target: notes,
    quantifier,
    where,
  };
}

function onOrganization(where: Condition | undefined): Condition {
  const relation = customers.relations["organization"];
  if (!relation) throw new Error("No organization relation");
  return {
    kind: "relation",
    name: "organization",
    relation,
    target: organizations,
    quantifier: "some",
    where,
  };
}

describe("scopeCondition", () => {
  it("returns undefined without a condition", () => {
    expect(scopeCondition(undefined, scopeFor)).toBeUndefined();
  });

  it("keeps column conditions", () => {
    expect(scopeCondition(body, scopeFor)).toBe(body);
  });

  it.each<[string, Condition, Condition]>([
    [
      "some",
      onNotes("some", body),
      onNotes("some", { kind: "and", items: [body, tenant] }),
    ],
    [
      "some without a filter",
      onNotes("some", undefined),
      onNotes("some", tenant),
    ],
    [
      "none",
      onNotes("none", body),
      onNotes("none", { kind: "and", items: [body, tenant] }),
    ],
    [
      "every",
      onNotes("every", body),
      onNotes("none", {
        kind: "and",
        items: [tenant, { kind: "not", item: body }],
      }),
    ],
    [
      "every without a filter",
      onNotes("every", undefined),
      onNotes("every", undefined),
    ],
    [
      "an unscoped target",
      onOrganization(column("slug", "eq", "acme")),
      onOrganization(column("slug", "eq", "acme")),
    ],
  ])("scopes %s", (_name, input, expected) => {
    expect(scopeCondition(input, scopeFor)).toEqual(expected);
  });

  it("recurses through and, or, not and nested relations", () => {
    const input: Condition = {
      kind: "or",
      items: [
        {
          kind: "and",
          items: [body, { kind: "not", item: onNotes("some", undefined) }],
        },
        onOrganization(undefined),
      ],
    };
    expect(scopeCondition(input, scopeFor)).toEqual({
      kind: "or",
      items: [
        {
          kind: "and",
          items: [body, { kind: "not", item: onNotes("some", tenant) }],
        },
        onOrganization(undefined),
      ],
    });
  });
});

const notesInclude = (overrides: Partial<Include> = {}): Include => {
  const relation = customers.relations["notes"];
  if (!relation) throw new Error("No notes relation");
  return {
    alias: "notes",
    relation,
    target: notes,
    selection: { columns: [{ alias: "id", column: "id" }], includes: [] },
    where: undefined,
    orderBy: [],
    limit: undefined,
    required: false,
    ...overrides,
  };
};

describe("scopeSelection", () => {
  it("returns a selection without includes unchanged", () => {
    const selection: Selection = {
      columns: [{ alias: "id", column: "id" }],
      includes: [],
    };
    expect(scopeSelection(selection, scopeFor)).toBe(selection);
  });

  it("scopes include filters and nested includes", () => {
    const customerRelation = notes.relations["customer"];
    if (!customerRelation) throw new Error("No customer relation");
    const nested: Include = {
      ...notesInclude(),
      alias: "customer",
      relation: customerRelation,
      target: customers,
    };
    const selection: Selection = {
      columns: [],
      includes: [
        notesInclude({
          where: body,
          selection: { columns: [], includes: [nested] },
        }),
      ],
    };
    expect(scopeSelection(selection, scopeFor)).toEqual({
      columns: [],
      includes: [
        notesInclude({
          where: { kind: "and", items: [body, tenant] },
          selection: { columns: [], includes: [{ ...nested, where: live }] },
        }),
      ],
    });
  });
});

describe("scopeOperation", () => {
  const selection: Selection = { columns: [], includes: [notesInclude()] };
  const scopedSelection: Selection = {
    columns: [],
    includes: [notesInclude({ where: tenant })],
  };
  const id = column("id", "eq", "c1");

  it("scopes the root rows, filters and includes of a select", () => {
    const op: Operation = {
      kind: "select",
      table: customers,
      selection,
      where: id,
      orderBy: [],
      limit: undefined,
      offset: undefined,
      count: undefined,
      head: false,
      single: undefined,
    };
    expect(scopeOperation(op, scopeFor)).toEqual({
      ...op,
      selection: scopedSelection,
      where: { kind: "and", items: [id, live] },
    });
  });

  it("leaves the root rows alone when it is not the root", () => {
    const op: Operation = {
      kind: "delete",
      table: customers,
      where: id,
      returning: undefined,
    };
    expect(scopeOperation(op, scopeFor, false)).toEqual(op);
  });

  it.each(["update", "delete"] as const)(
    "scopes the rows and returning of %s",
    (kind) => {
      const op: Operation =
        kind === "update"
          ? {
              kind,
              table: customers,
              set: { name: "B" },
              where: undefined,
              returning: selection,
            }
          : { kind, table: customers, where: undefined, returning: selection };
      expect(scopeOperation(op, scopeFor)).toEqual({
        ...op,
        where: live,
        returning: scopedSelection,
      });
    },
  );

  it("keeps a missing returning undefined", () => {
    const op: Operation = {
      kind: "update",
      table: customers,
      set: { name: "B" },
      where: id,
      returning: undefined,
    };
    expect(scopeOperation(op, scopeFor)).toEqual({
      ...op,
      where: { kind: "and", items: [id, live] },
    });
  });

  it("scopes only the returning selection of an insert", () => {
    const base = {
      kind: "insert",
      table: customers,
      rows: [{ name: "A" }],
      onConflict: undefined,
      defaultToNull: false,
    } as const;
    expect(scopeOperation({ ...base, returning: selection }, scopeFor)).toEqual(
      {
        ...base,
        returning: scopedSelection,
      },
    );
    expect(scopeOperation({ ...base, returning: undefined }, scopeFor)).toEqual(
      {
        ...base,
        returning: undefined,
      },
    );
  });
});
