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
      canSuggest: false,
      snapshotSeq: 4,
      snapshot: new Uint8Array([1, 2]),
      updates: [{ seq: 5, update: new Uint8Array([3]) }],
    });
    expect(opened.updatedAt.toString()).toBe("2026-10-02T00:00:00Z");
    expect(
      await documents
        .push({ documentId: "d1", update: new Uint8Array([3]) })
        .orThrow(),
    ).toBe(6);

    const pulled = await documents
      .pull({ documentId: "d1", afterSeq: 5 })
      .orThrow();

    expect(pulled).toEqual({ snapshotSeq: 0, updates: [] });
    expect(
      await documents
        .compact({
          documentId: "d1",
          state: new Uint8Array([1, 2]),
          throughSeq: 6,
        })
        .orThrow(),
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
          source: "manual",
          frozen: true,
          createdBy: "u1",
          createdAt: "2026-10-03T00:00:00Z",
        },
        { id: "v1", number: 1, createdAt: "2026-10-01T00:00:00Z" },
      ],
      get_document_version: () => "AQI=",
    });

    const documents = createDocuments({ transport: fake, schema: "app" });
    expect(
      await documents
        .saveVersion({ documentId: "d1", state: new Uint8Array([1]) })
        .orThrow(),
    ).toEqual({ id: "v1", number: 1 });
    await documents
      .saveVersion({
        documentId: "d1",
        state: new Uint8Array([1]),
        label: "Final",
      })
      .orThrow();
    const listed = await documents.versions({ documentId: "d1" }).orThrow();
    expect(listed[0]).toMatchObject({
      label: "Final",
      source: "manual",
      frozen: true,
      createdBy: "u1",
    });
    expect(listed[1]).toMatchObject({ source: "manual", frozen: false });
    expect(listed[1]).not.toHaveProperty("label");

    const named = await documents
      .versions({ documentId: "d1", named: true })
      .orThrow();

    expect(named.map((item) => item.id)).toEqual(["v2"]);
    expect(listed[1]).not.toHaveProperty("createdBy");
    expect(
      await documents.version({ documentId: "d1", versionId: "v1" }).orThrow(),
    ).toEqual(new Uint8Array([1, 2]));
    expect(fake.calls[0]![1]).toMatchObject({ label: null });
    expect(fake.calls[1]![1]).toMatchObject({ label: "Final" });
  });

  it("names versions", async () => {
    const fake = transport({ name_document_version: () => true });

    const documents = createDocuments({ transport: fake, schema: "app" });
    expect(
      await documents
        .nameVersion({ documentId: "d1", versionId: "v1", label: "Draft" })
        .orThrow(),
    ).toBe(true);
    await documents
      .nameVersion({ documentId: "d1", versionId: "v1", label: null })
      .orThrow();
    expect(fake.calls).toEqual([
      [
        "name_document_version",
        { document_id: "d1", version_id: "v1", label: "Draft" },
      ],
      [
        "name_document_version",
        { document_id: "d1", version_id: "v1", label: null },
      ],
    ]);
  });

  it("suggests, lists and decides suggestions", async () => {
    const open = {
      id: "s1",
      documentId: "d1",
      update: "Aw==",
      summary: null,
      status: "open",
      createdBy: "u1",
      createdAt: "2026-10-03T00:00:00Z",
      decidedBy: null,
      decidedAt: null,
      note: null,
    };

    const fake = transport({
      suggest_document_change: () => open,
      list_document_suggestions: () => [open],
      decide_document_suggestion: (args) =>
        (args as { decision: string }).decision === "accepted"
          ? {
              ...open,
              summary: "Typo",
              status: "accepted",
              decidedBy: "u2",
              decidedAt: "2026-10-04T00:00:00Z",
              note: "Thanks",
              seq: "7",
            }
          : { ...open, status: "bogus" },
    });

    const documents = createDocuments({ transport: fake, schema: "app" });

    const suggested = await documents
      .suggest({ documentId: "d1", update: new Uint8Array([3]) })
      .orThrow();

    expect(suggested).toMatchObject({
      id: "s1",
      update: new Uint8Array([3]),
      status: "open",
      createdBy: "u1",
    });
    expect(suggested).not.toHaveProperty("summary");
    expect(suggested).not.toHaveProperty("seq");
    await documents
      .suggest({
        documentId: "d1",
        update: new Uint8Array([3]),
        summary: "Typo",
      })
      .orThrow();
    expect(
      await documents.suggestions({ documentId: "d1" }).orThrow(),
    ).toHaveLength(1);
    await documents
      .suggestions({ documentId: "d1", options: { status: "all" } })
      .orThrow();

    const accepted = await documents
      .decideSuggestion({
        suggestionId: "s1",
        decision: "accepted",
        note: "Thanks",
      })
      .orThrow();

    expect(accepted).toMatchObject({
      status: "accepted",
      summary: "Typo",
      decidedBy: "u2",
      note: "Thanks",
      seq: 7,
    });
    expect(accepted.decidedAt?.toString()).toBe("2026-10-04T00:00:00Z");

    const bad = await documents.decideSuggestion({
      suggestionId: "s1",
      decision: "rejected",
    });

    expect(bad.error).toBeDefined();
    expect(fake.calls).toEqual([
      [
        "suggest_document_change",
        { document_id: "d1", payload: "Aw==", summary: null },
      ],
      [
        "suggest_document_change",
        { document_id: "d1", payload: "Aw==", summary: "Typo" },
      ],
      ["list_document_suggestions", { document_id: "d1", status: "open" }],
      ["list_document_suggestions", { document_id: "d1", status: "all" }],
      [
        "decide_document_suggestion",
        { suggestion_id: "s1", decision: "accepted", note: "Thanks" },
      ],
      [
        "decide_document_suggestion",
        { suggestion_id: "s1", decision: "rejected", note: null },
      ],
    ]);
  });

  it("lists documents to compact with optional limits", async () => {
    const fake = transport({ documents_to_compact: () => ["d1", "d2"] });

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

    const pushed = await documents.push({
      documentId: "d1",
      update: new Uint8Array([1]),
    });

    expect(pushed.error).toBeDefined();
    expect(await documents.toCompact().orThrow()).toEqual([]);
  });
});
