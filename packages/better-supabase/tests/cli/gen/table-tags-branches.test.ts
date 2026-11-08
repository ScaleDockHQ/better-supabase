import { describe, expect, it } from "vitest";

import type { TableComment } from "../../../src/cli/gen/table-tags.ts";

import { withTableTags } from "../../../src/cli/gen/table-tags.ts";
import { resolveConfig } from "../../../src/config/index.ts";

function table(
  name: string,
  comment: string | null,
  schema = "public",
): TableComment {
  return { schema, name, comment };
}

const base = resolveConfig({ blocks: {} }, "/tmp");

describe("withTableTags, tables and comments", () => {
  it("skips tables outside the configured schemas and tables without a comment", () => {
    const config = withTableTags(base, [
      table("a", "@bsb subject", "elsewhere"),
      table("b", null),
      table("c", "plain text"),
    ]);

    expect(config).toBe(base);
  });

  it("names a table outside public by its qualified name", () => {
    const config = resolveConfig(
      { blocks: {}, database: { schemas: ["public", "crm"] } },
      "/tmp",
    );

    const next = withTableTags(config, [
      table("deals", "@bsb realtime user=owner; vector-search column=e", "crm"),
    ]);

    expect(next.realtime.tables).toContain("crm.deals");
    expect(next.realtime.users["crm.deals"]).toBe("owner");
    expect(next.vectorSearch).toEqual([
      { table: "crm.deals", column: "e", distance: "cosine" },
    ]);
  });

  it("ignores public-only tags in another schema", () => {
    const config = resolveConfig(
      { blocks: {}, database: { schemas: ["public", "crm"] } },
      "/tmp",
    );

    const next = withTableTags(config, [
      table(
        "deals",
        "@bsb encrypted a; lookup b; server c; events; search",
        "crm",
      ),
    ]);

    expect(next).toBe(config);
  });
});

describe("withTableTags, columns", () => {
  it("lets an own column definition win and merges it otherwise", () => {
    const config = resolveConfig(
      {
        blocks: {},
        appTables: {
          people: {
            columns: {
              note: { type: "text", format: "email" },
              secret: { type: "text" },
            },
          },
        },
      },
      "/tmp",
    );

    const next = withTableTags(config, [
      table("people", "@bsb encrypted note=bigint; lookup secret; server note"),
    ]);

    expect(next.appTables["people"]?.columns?.["note"]).toMatchObject({
      type: "text",
    });
    expect(next.appTables["people"]?.columns?.["secret"]).toEqual({
      type: "text",
    });
  });

  it("builds a column from a tag alone and refines it with a later tag", () => {
    const next = withTableTags(base, [
      table(
        "people",
        "@bsb encrypted ssn=bigint; lookup ssn; server ssn; server token; lookup email",
      ),
    ]);

    expect(next.appTables["people"]?.columns).toEqual({
      ssn: { type: "bigint", encrypted: true, lookup: true, access: "server" },
      token: { type: "text", access: "server" },
      email: { type: "text", lookup: true },
    });
  });

  it("ignores an unknown column type", () => {
    expect(
      withTableTags(base, [table("people", "@bsb encrypted ssn=nope")]),
    ).toBe(base);
  });
});

describe("withTableTags, events and search", () => {
  it("turns events on for everything, or for chosen kinds only", () => {
    const next = withTableTags(base, [
      table("a", "@bsb events"),
      table("b", "@bsb events on=created"),
      table("c", '@bsb events include="x, y"'),
    ]);

    expect(next.appTables["a"]?.events).toBe(true);
    expect(next.appTables["b"]?.events).toEqual({ on: ["created"] });
    expect(next.appTables["c"]?.events).toEqual({ include: ["x", "y"] });
  });

  it("leaves events and search the config already set", () => {
    const config = {
      ...base,
      appTables: { a: { events: true as const, search: true as const } },
    };

    expect(
      withTableTags(config, [table("a", "@bsb events; search columns=x")]),
    ).toBe(config);
  });

  it("reads search columns, or turns search on for every text column", () => {
    const next = withTableTags(base, [
      table("a", "@bsb search columns=title,body"),
      table("b", "@bsb search"),
    ]);

    expect(next.appTables["a"]?.search).toEqual({ columns: ["title", "body"] });
    expect(next.appTables["b"]?.search).toBe(true);
  });

  it("names events after the subject whose table is public-qualified", () => {
    const config = resolveConfig(
      {
        blocks: {},
        recordTypes: { item: { table: "public.items", title: "name" } },
      },
      "/tmp",
    );

    const next = withTableTags(config, [table("items", "@bsb events")]);

    expect(next.appTables["items"]?.subject).toEqual({ type: "item" });
  });
});

describe("withTableTags, lifecycle and history", () => {
  const blocks = { "field-history": {}, pipelines: {} };

  const subject = (config: typeof base) => ({
    ...config,
    subjects: { deal: { table: "deals", title: "name" } },
  });

  it("ignores a tag whose table is not a subject", () => {
    const config = resolveConfig({ blocks }, "/tmp");

    expect(
      withTableTags(config, [
        table("deals", "@bsb history a; lifecycle stage=s pipeline=p"),
      ]),
    ).toBe(config);
  });

  it("needs history fields and both lifecycle arguments", () => {
    const config = subject(resolveConfig({ blocks }, "/tmp"));

    const next = withTableTags(config, [
      table("deals", "@bsb history; lifecycle stage=s; lifecycle pipeline=p"),
    ]);

    expect(next).toBe(config);
  });

  it("matches a subject whose table carries the public prefix", () => {
    const resolved = resolveConfig({ blocks }, "/tmp");

    const config = {
      ...resolved,
      subjects: { deal: { table: "public.deals", title: "n" } },
    };

    const next = withTableTags(config, [
      table("deals", "@bsb audit-reads; history a"),
    ]);

    expect(next.subjects["deal"]).toMatchObject({ auditReads: true });
    expect(next.blocks["field-history"]?.on).toEqual({
      deal: { fields: ["a"] },
    });
  });

  it("keeps an existing binding, in the object or the list form", () => {
    const resolved = resolveConfig(
      {
        blocks: {
          "field-history": { on: ["deal"] },
          pipelines: { on: { deal: { stage: "x", pipeline: "y" } } },
        },
      },
      "/tmp",
    );

    const config = subject(resolved);

    expect(
      withTableTags(config, [
        table("deals", "@bsb history a; lifecycle stage=s pipeline=p"),
      ]),
    ).toBe(config);
  });

  it("adds to an existing list-form binding and skips an absent block", () => {
    const resolved = resolveConfig(
      { blocks: { "field-history": { on: ["other"] } } },
      "/tmp",
    );

    const config = subject(resolved);

    const next = withTableTags(config, [
      table("deals", "@bsb history a; lifecycle stage=s pipeline=p"),
    ]);

    expect(next.blocks["field-history"]?.on).toEqual({
      other: {},
      deal: { fields: ["a"] },
    });
    expect(next.blocks["pipelines"]).toBeUndefined();
  });
});
