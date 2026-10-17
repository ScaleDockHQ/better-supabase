import { describe, expect, it } from "vitest";

import { createDocuments } from "../../../src/blocks/documents/index.ts";

function transport(results: Record<string, (args: unknown) => unknown>) {
  const calls: [string, unknown][] = [];
  return {
    calls,
    call(schema: string, fn: string, args: unknown) {
      expect(schema).toBe("app");
      calls.push([fn, args]);
      const result = results[fn];
      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }
      return Promise.resolve(result(args));
    },
  };
}

const OPENED = {
  id: "d1",
  organizationId: "o",
  subjectType: "project",
  subjectId: "p1",
  name: "body",
  topic: "documents:d1",
  canWrite: true,
  createdAt: "2026-10-01T00:00:00Z",
  updatedAt: "2026-10-02T00:00:00Z",
  snapshot: "AQI=",
  snapshotSeq: "4",
  updates: [{ seq: 5, update: "Aw==" }],
};

describe("documents client", () => {
  it("opens, pushes, pulls and compacts with bytes", async () => {
    const fake = transport({
      open_document: () => OPENED,
      push_document_update: () => 6,
      pull_document_updates: () => ({ updates: [] }),
      compact_document: () => true,
    });
    const documents = createDocuments({ transport: fake, schema: "app" });
    const opened = await documents
      .open({ organizationId: "o", subjectType: "project", subjectId: "p1" })
      .orThrow();
    expect(opened).toMatchObject({
      id: "d1",
      canWrite: true,
      snapshotSeq: 4,
      snapshot: new Uint8Array([1, 2]),
      updates: [{ seq: 5, update: new Uint8Array([3]) }],
    });
    expect(opened.updatedAt.toString()).toBe("2026-10-02T00:00:00Z");
    expect(await documents.push("d1", new Uint8Array([3])).orThrow()).toBe(6);
    const pulled = await documents.pull("d1", 5).orThrow();
    expect(pulled).toEqual({ snapshotSeq: 0, updates: [] });
    expect(
      await documents.compact("d1", new Uint8Array([1, 2]), 6).orThrow(),
    ).toBe(true);
    expect(fake.calls).toEqual([
      [
        "open_document",
        {
          tenant: "o",
          subject_type: "project",
          subject_id: "p1",
          name: "body",
        },
      ],
      ["push_document_update", { document_id: "d1", payload: "Aw==" }],
      ["pull_document_updates", { document_id: "d1", after_seq: 5 }],
      [
        "compact_document",
        { document_id: "d1", state: "AQI=", through_seq: 6 },
      ],
    ]);
  });

  it("saves, lists and reads versions", async () => {
    const fake = transport({
      save_document_version: () => ({ id: "v1", number: 1 }),
      list_document_versions: () => [
        {
          id: "v2",
          number: 2,
          label: "Final",
          createdBy: "u1",
          createdAt: "2026-10-03T00:00:00Z",
        },
        { id: "v1", number: 1, createdAt: "2026-10-01T00:00:00Z" },
      ],
      get_document_version: () => "AQI=",
    });
    const documents = createDocuments({ transport: fake, schema: "app" });
    expect(
      await documents.saveVersion("d1", new Uint8Array([1])).orThrow(),
    ).toEqual({ id: "v1", number: 1 });
    await documents.saveVersion("d1", new Uint8Array([1]), "Final").orThrow();
    const listed = await documents.versions("d1").orThrow();
    expect(listed[0]).toMatchObject({ label: "Final", createdBy: "u1" });
    expect(listed[1]).not.toHaveProperty("label");
    expect(listed[1]).not.toHaveProperty("createdBy");
    expect(await documents.version("d1", "v1").orThrow()).toEqual(
      new Uint8Array([1, 2]),
    );
    expect(fake.calls[0]![1]).toMatchObject({ label: null });
    expect(fake.calls[1]![1]).toMatchObject({ label: "Final" });
  });

  it("lists documents to compact with optional limits", async () => {
    const fake = transport({
      documents_to_compact: () => ["d1", "d2"],
    });
    const documents = createDocuments({ transport: fake, schema: "app" });
    expect(await documents.toCompact().orThrow()).toEqual(["d1", "d2"]);
    await documents.toCompact({ minUpdates: 10, limit: 5 }).orThrow();
    expect(fake.calls).toEqual([
      ["documents_to_compact", {}],
      ["documents_to_compact", { min_updates: 10, max_documents: 5 }],
    ]);
  });

  it("returns an error for a malformed sequence", async () => {
    const fake = transport({
      push_document_update: () => -1,
      documents_to_compact: () => null,
    });
    const documents = createDocuments({ transport: fake, schema: "app" });
    const pushed = await documents.push("d1", new Uint8Array([1]));
    expect(pushed.error).toBeDefined();
    expect(await documents.toCompact().orThrow()).toEqual([]);
  });
});
