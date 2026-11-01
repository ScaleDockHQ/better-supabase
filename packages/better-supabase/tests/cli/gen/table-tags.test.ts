import { describe, expect, it } from "vitest";

import type { TableComment } from "../../../src/cli/gen/table-tags.ts";

import { withTableTags } from "../../../src/cli/gen/table-tags.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { loadFixtureSnapshot } from "../fixtures/render.ts";

async function tagged(
  table: string,
  comment: string,
): Promise<readonly TableComment[]> {
  const { schema } = await first();
  const snapshot = await loadFixtureSnapshot();

  return snapshot.generator.tables.map((each) =>
    each.schema === schema && each.name === table
      ? { ...each, comment }
      : { ...each, comment: null },
  );
}

async function first(): Promise<{ schema: string; name: string; key: string }> {
  const snapshot = await loadFixtureSnapshot();
  const { schemas } = resolveConfig({ blocks: {} }, "/tmp");

  const table = snapshot.generator.tables.find((each) =>
    schemas.includes(each.schema),
  );

  if (table === undefined) {
    throw new Error("The fixture has no table in the default schemas.");
  }

  return {
    schema: table.schema,
    name: table.name,
    key:
      table.schema === "public" ? table.name : `${table.schema}.${table.name}`,
  };
}

describe("withTableTags", () => {
  it("returns the config itself without tags", async () => {
    const config = resolveConfig({ blocks: {} }, "/tmp");

    expect(
      withTableTags(
        config,
        (await loadFixtureSnapshot()).generator.tables.map((each) => ({
          ...each,
          comment: null,
        })),
      ),
    ).toBe(config);
  });

  it("turns subject, realtime and vector-search tags into config", async () => {
    const { name, key } = await first();
    const config = resolveConfig({ blocks: {} }, "/tmp");

    const next = withTableTags(
      config,
      await tagged(
        name,
        "Free text. @bsb subject title=id url=/x/{id}; realtime global; vector-search column=embedding",
      ),
    );

    expect(next.subjects[name]).toMatchObject({ table: key, title: "id" });
    expect(next.realtime.tables).toContain(key);
    expect(next.realtime.global).toContain(key);
    expect(next.vectorSearch).toContainEqual({
      table: key,
      column: "embedding",
      distance: "cosine",
    });
  });

  it("turns audit-reads, history and lifecycle tags into config", async () => {
    const { name, key } = await first();

    const config = resolveConfig(
      { blocks: { "field-history": {}, pipelines: {} } },
      "/tmp",
    );

    const next = withTableTags(
      config,
      await tagged(
        name,
        "@bsb subject; audit-reads; history title body; lifecycle stage=status pipeline=deals",
      ),
    );

    expect(next.subjects[name]).toMatchObject({ table: key, auditReads: true });

    expect(next.blocks["field-history"]?.on).toEqual({
      [name]: { fields: ["title", "body"] },
    });

    expect(next.blocks["pipelines"]?.on).toEqual({
      [name]: { stage: "status", pipeline: "deals" },
    });
  });

  it("keeps what the config sets itself", async () => {
    const { name, key } = await first();

    const base = resolveConfig({ blocks: {} }, "/tmp");

    const config = {
      ...base,
      subjects: { [name]: { table: key, title: "kept" } },
    };

    const next = withTableTags(
      config,
      await tagged(name, "@bsb subject title=other"),
    );

    expect(next.subjects[name]?.title).toBe("kept");
  });

  it("rejects a tag that declares a block's subject type", async () => {
    const { name } = await first();
    const tables = await tagged(name, "@bsb subject type=task");
    const config = resolveConfig({ blocks: { tasks: {} } }, "/tmp");

    expect(() => withTableTags(config, tables)).toThrow(
      /declares "task", which the tasks block registers itself/u,
    );

    const renamed = resolveConfig(
      { blocks: { tasks: { names: { task: "work_item" } } } },
      "/tmp",
    );

    expect(withTableTags(renamed, tables).subjects["task"]).toBeDefined();
  });

  it("skips tables outside the schemas and unusable tags", async () => {
    const { name, key } = await first();
    const config = resolveConfig({ blocks: {} }, "/tmp");

    const ignored = withTableTags(
      config,
      await tagged(
        name,
        "@bsb vector-search column=e distance=manhattan; vector-search; subject type=a tenant=org; unknown",
      ),
    );

    expect(ignored.vectorSearch).toEqual([]);
    expect(ignored.subjects["a"]).toMatchObject({ table: key, tenant: "org" });

    const present = {
      ...config,
      realtime: { ...config.realtime, tables: [key] },
      vectorSearch: [{ table: key, column: "x", distance: "cosine" as const }],
    };

    const kept = withTableTags(
      present,
      await tagged(name, "@bsb realtime; vector-search column=y"),
    );

    expect(kept.realtime.tables).toEqual([key]);
    expect(kept.vectorSearch).toHaveLength(1);

    const outside = withTableTags(
      { ...config, schemas: ["nowhere"] },
      await tagged(name, "@bsb realtime"),
    );

    expect(outside.realtime.tables).toEqual([]);
  });

  it("reads realtime global and user arguments and subject url", async () => {
    const { name, key } = await first();
    const config = resolveConfig({ blocks: {} }, "/tmp");

    const next = withTableTags(
      config,
      await tagged(
        name,
        "@bsb realtime global user=owner_id; subject url=/x/{id}",
      ),
    );

    expect(next.realtime.global).toContain(key);
    expect(next.realtime.users[key]).toBe("owner_id");
    expect(next.subjects[name]?.url).toBe("/x/{id}");
  });

  it("reads json, encrypted and events tags", async () => {
    const { name, key } = await first();
    const config = resolveConfig({ blocks: {} }, "/tmp");

    const next = withTableTags(
      config,
      await tagged(
        name,
        '@bsb json meta="Record<string, string>" doc=import:@/types#Doc bad; encrypted ssn=bigint note odd=nope; events on="created, bogus" include="a, b"',
      ),
    );

    expect(next.json[`${key}.meta`]).toEqual({
      type: "Record<string, string>",
    });
    expect(next.json[`${key}.doc`]).toEqual({ import: "@/types#Doc" });
    expect(next.json[`${key}.bad`]).toBeUndefined();
    expect(next.appTables[name]?.columns?.["note"]).toEqual({
      type: "text",
      encrypted: true,
    });
    expect(next.appTables[name]?.columns?.["ssn"]).toEqual({
      type: "bigint",
      encrypted: true,
    });
    expect(next.appTables[name]?.columns?.["odd"]).toBeUndefined();
    expect(next.appTables[name]?.events).toEqual({
      on: ["created"],
      include: ["a", "b"],
    });

    const hidden = withTableTags(
      config,
      await tagged(name, "@bsb encrypted note=text; server note secret"),
    );

    expect(hidden.appTables[name]?.columns?.["note"]).toEqual({
      type: "text",
      encrypted: true,
      access: "server",
    });
    expect(hidden.appTables[name]?.columns?.["secret"]).toEqual({
      type: "text",
      access: "server",
    });

    const looked = withTableTags(
      config,
      await tagged(name, "@bsb lookup bsn; encrypted bsn=text"),
    );

    expect(looked.appTables[name]?.columns?.["bsn"]).toEqual({
      type: "text",
      encrypted: true,
      lookup: true,
    });

    const named = withTableTags(
      config,
      await tagged(name, "@bsb subject type=thing; events"),
    );

    expect(named.appTables[name]?.subject).toEqual({ type: "thing" });

    const all = withTableTags(config, await tagged(name, "@bsb events"));

    expect(all.appTables[name]?.events).toBe(true);
  });

  it("lets config win over json, encrypted and events tags", async () => {
    const { name, key } = await first();
    const base = resolveConfig({ blocks: {} }, "/tmp");

    const config = {
      ...base,
      json: { [`${key}.meta`]: { type: "Kept" } },
      appTables: {
        [name]: {
          events: true as const,
          columns: { ssn: { type: "text" as const } },
        },
      },
    };

    const next = withTableTags(
      config,
      await tagged(
        name,
        "@bsb json meta=Other; encrypted ssn; events on=created",
      ),
    );

    expect(next).toBe(config);
  });
});
