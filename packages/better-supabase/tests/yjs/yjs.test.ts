import { describe, expect, it, vi } from "vitest";
import * as Y from "yjs";

import type {
  DecidedSuggestion,
  Documents,
  DocumentState,
  DocumentSuggestion,
  OpenedDocument,
} from "../../src/blocks/documents/documents.ts";
import type { RealtimeClient } from "../../src/realtime/index.ts";

import { toBase64 } from "../../src/core/base64.ts";
import { AsyncResult } from "../../src/core/result.ts";
import { temporal } from "../../src/core/temporal-required.ts";
import {
  compactDocument,
  createDocumentProvider,
} from "../../src/yjs/index.ts";

const DOC_ID = "00000000-0000-4000-8000-000000000001";

function fakeServer(canWrite = true, canSuggest = canWrite) {
  const push = vi.fn();
  const suggestions: DocumentSuggestion[] = [];
  let snapshot: { state: Uint8Array; seq: number } | undefined;
  let updates: { seq: number; update: Uint8Array }[] = [];
  let next = 1;
  let offline = false;

  const stateAfter = (after: number): DocumentState => {
    if (snapshot !== undefined && after < snapshot.seq) {
      return {
        snapshot: snapshot.state,
        snapshotSeq: snapshot.seq,
        updates: updates.filter((item) => item.seq > snapshot!.seq),
      };
    }

    return {
      snapshotSeq: snapshot?.seq ?? 0,
      updates: updates.filter((item) => item.seq > after),
    };
  };

  const now = temporal().Now.instant();

  const documents: Documents = {
    open: (ref) => {
      const opened: OpenedDocument = {
        id: DOC_ID,
        organizationId: ref.organizationId,
        subjectType: ref.subjectType,
        subjectId: ref.subjectId,
        name: ref.name ?? "body",
        topic: `documents:${DOC_ID}`,
        canWrite,
        canSuggest,
        createdAt: now,
        updatedAt: now,
        ...stateAfter(0),
        ...(snapshot === undefined ? {} : { snapshot: snapshot.state }),
      };

      return AsyncResult.ok(opened);
    },
    push: ({
      documentId: _id,
      update,
    }: {
      documentId: string;
      update: Uint8Array;
    }) => {
      push();

      if (offline) {
        return AsyncResult.err<number>({
          kind: "network",
          message: "offline",
        } as never);
      }

      const seq = next;
      next += 1;
      updates.push({ seq, update });

      return AsyncResult.ok(seq);
    },
    pull: ({ documentId: _id, afterSeq: after }) =>
      AsyncResult.ok(stateAfter(after)),
    compact: ({ documentId: _id, state, throughSeq: through }) => {
      snapshot = { state, seq: through };
      updates = updates.filter((item) => item.seq > through);

      return AsyncResult.ok(true);
    },
    saveVersion: () => AsyncResult.ok({ id: "v", number: 1 }),
    versions: () => AsyncResult.ok([]),
    nameVersion: () => AsyncResult.ok(true),
    suggest: ({ documentId, update, summary }) => {
      const suggestion: DocumentSuggestion = {
        id: `s${String(suggestions.length + 1)}`,
        documentId,
        update,
        status: "open",
        createdAt: now,
        ...(summary === undefined ? {} : { summary }),
      };

      suggestions.push(suggestion);

      return AsyncResult.ok(suggestion);
    },
    suggestions: () => AsyncResult.ok(suggestions),
    decideSuggestion: ({ suggestionId: id, decision }) => {
      const found = suggestions.find((item) => item.id === id);

      if (found === undefined) {
        return AsyncResult.err<DecidedSuggestion>({
          kind: "not_found",
          message: "suggestion not found",
        } as never);
      }

      if (decision !== "accepted") {
        return AsyncResult.ok({ ...found, status: decision });
      }

      const seq = next;
      next += 1;
      updates.push({ seq, update: found.update });

      return AsyncResult.ok({ ...found, status: decision, seq });
    },
    version: () => AsyncResult.ok(new Uint8Array()),
    toCompact: () => AsyncResult.ok([DOC_ID]),
    page: (ref) =>
      documents
        .open(ref)
        .map((opened) => ({ ...opened, versions: [], suggestions: [] })),
  };

  return {
    documents,
    push,
    suggestions,
    count: () => updates.length,
    snapshotSeq: () => snapshot?.seq,
    setOffline: (value: boolean) => {
      offline = value;
    },
  };
}

type Listener = (message: { event: string; payload: unknown }) => void;

/** One fake Realtime channel per client, all on one broadcast bus. */
function fakeBus() {
  const channels: {
    listeners: Listener[];
    syncs: (() => void)[];
    presence: Record<string, Record<string, unknown>[]>;
    report?: (status: string) => void;
  }[] = [];

  const client = () => {
    const entry: (typeof channels)[number] = {
      listeners: [],
      syncs: [],
      presence: {},
    };

    channels.push(entry);

    const channel = {
      topic: "",
      on: (type: string, _filter: unknown, listener: Listener) => {
        if (type === "broadcast") {
          entry.listeners.push(listener);
        }

        if (type === "presence") {
          entry.syncs.push(listener as () => void);
        }

        return channel;
      },
      presenceState: () => entry.presence,
      track: async () => "ok",
      untrack: async () => "ok",
      subscribe: (callback: (status: string) => void) => {
        entry.report = callback;
        queueMicrotask(() => {
          callback("SUBSCRIBED");
        });

        return channel;
      },
      send: vi.fn(async (message: { event: string; payload: unknown }) => {
        for (const other of channels) {
          if (other === entry) {
            continue;
          }

          for (const listener of other.listeners) {
            listener(message);
          }
        }

        return "ok";
      }),
    };

    const raw = {
      channel: (topic: string) => {
        channel.topic = `realtime:${topic}`;

        return channel;
      },
      getChannels: () => [channel],
      removeChannel: async () => "ok",
      realtime: { setAuth: async () => undefined },
    };

    // SAFETY: the fake implements the channel calls the provider makes.
    return {
      client: raw as unknown as RealtimeClient,
      entry,
      channel,
      sync: (state: Record<string, Record<string, unknown>[]>) => {
        entry.presence = state;

        for (const listener of entry.syncs) {
          listener();
        }
      },
      deliver: (payload: unknown) => {
        for (const listener of entry.listeners) {
          listener({ event: "update", payload });
        }
      },
    };
  };

  return { client };
}

const ref = { organizationId: "org", subjectType: "page", subjectId: "p1" };

describe("createDocumentProvider", () => {
  it("syncs two documents through the log and the topic", async () => {
    const server = fakeServer();
    const bus = fakeBus();
    const a = new Y.Doc();
    const b = new Y.Doc();

    const one = createDocumentProvider({
      documents: server.documents,
      client: bus.client().client,
      doc: a,
      ref,
      yjs: Y,
    });

    await one.connect().orThrow();
    a.getText("t").insert(0, "hello");
    await one.flush();
    expect(server.count()).toBe(1);

    const two = createDocumentProvider({
      documents: server.documents,
      client: bus.client().client,
      doc: b,
      ref,
      yjs: Y,
    });

    await two.connect().orThrow();
    expect(b.getText("t").toString()).toBe("hello");
    expect(two.status).toBe("synced");

    b.getText("t").insert(5, " world");
    await two.flush();
    expect(a.getText("t").toString()).toBe("hello world");
    expect(server.count()).toBe(2);
    await one.destroy();
    await two.destroy();
    expect(one.status).toBe("closed");
  });

  it("keeps edits made offline and sends them on reconnect", async () => {
    const server = fakeServer();
    const bus = fakeBus();
    const doc = new Y.Doc();
    const errors: unknown[] = [];
    const { client, entry } = bus.client();

    const provider = createDocumentProvider({
      documents: server.documents,
      client,
      doc,
      ref,
      yjs: Y,
      onError: (error) => errors.push(error),
    });

    await provider.connect().orThrow();
    server.setOffline(true);
    doc.getText("t").insert(0, "a");
    doc.getText("t").insert(1, "b");
    await provider.flush();
    expect(provider.status).toBe("offline");
    expect(errors.length).toBeGreaterThan(0);
    server.setOffline(false);
    entry.report?.("CHANNEL_ERROR");
    entry.report?.("SUBSCRIBED");
    await vi.waitFor(() => {
      expect(server.count()).toBe(1);
    });
    const copy = new Y.Doc();

    const state = await server.documents
      .pull({ documentId: DOC_ID, afterSeq: 0 })
      .orThrow();

    for (const item of state.updates) {
      Y.applyUpdate(copy, item.update);
    }

    expect(copy.getText("t").toString()).toBe("ab");
    await provider.destroy();
  });

  it("does not push for a reader", async () => {
    const server = fakeServer(false);
    const doc = new Y.Doc();

    const provider = createDocumentProvider({
      documents: server.documents,
      client: fakeBus().client().client,
      doc,
      ref,
      yjs: Y,
    });

    await provider.connect().orThrow();
    doc.getText("t").insert(0, "x");
    await provider.flush();
    expect(server.push).not.toHaveBeenCalled();
    await provider.destroy();
  });

  it("collects suggest-mode edits into a suggestion an editor accepts", async () => {
    const server = fakeServer(false, true);
    const bus = fakeBus();
    const draft = new Y.Doc();
    const edited = new Y.Doc();

    const suggester = createDocumentProvider({
      documents: server.documents,
      client: bus.client().client,
      doc: draft,
      ref,
      yjs: Y,
      mode: "suggest",
    });

    expect((await suggester.submitSuggestion()).ok).toBe(false);
    await suggester.connect().orThrow();
    expect(suggester.mode).toBe("suggest");
    expect(suggester.hasDraft).toBe(false);
    expect((await suggester.submitSuggestion()).ok).toBe(false);
    draft.getText("t").insert(0, "new ");
    draft.getText("t").insert(4, "text");
    await suggester.flush();
    expect(server.push).not.toHaveBeenCalled();
    expect(suggester.hasDraft).toBe(true);
    const suggestion = await suggester.submitSuggestion("Intro").orThrow();
    expect(suggestion.summary).toBe("Intro");
    expect(suggester.hasDraft).toBe(false);
    expect(server.count()).toBe(0);

    const editorServer = { ...server.documents };

    const editor = createDocumentProvider({
      documents: {
        ...editorServer,
        open: (target) =>
          editorServer
            .open(target)
            .map((opened) => ({ ...opened, canWrite: true })),
      },
      client: bus.client().client,
      doc: edited,
      ref,
      yjs: Y,
    });

    expect((await editor.acceptSuggestion(suggestion.id)).ok).toBe(false);
    await editor.connect().orThrow();
    expect(edited.getText("t").toString()).toBe("");
    const missing = await editor.acceptSuggestion("nope");
    expect(missing.ok).toBe(false);
    const decided = await editor.acceptSuggestion(suggestion.id).orThrow();
    expect(decided.seq).toBe(1);
    expect(edited.getText("t").toString()).toBe("new text");
    expect(server.count()).toBe(1);
    await editor.flush();
    expect(server.push).not.toHaveBeenCalled();
    await suggester.destroy();
    await editor.destroy();
  });

  it("keeps the draft when a suggestion fails and accepts out of order", async () => {
    const server = fakeServer();
    const doc = new Y.Doc();
    let failing = true;

    const provider = createDocumentProvider({
      documents: {
        ...server.documents,
        suggest: ({ documentId, update, summary }) =>
          failing
            ? AsyncResult.err<DocumentSuggestion>({
                kind: "network",
                message: "offline",
              } as never)
            : server.documents.suggest({ documentId, update, summary }),
        decideSuggestion: ({ suggestionId: id, decision }) =>
          server.documents
            .decideSuggestion({ suggestionId: id, decision })
            .map((decided) => ({ ...decided, seq: 5 })),
      },
      client: fakeBus().client().client,
      doc,
      ref,
      yjs: Y,
      mode: "suggest",
    });

    await provider.connect().orThrow();
    doc.getText("t").insert(0, "one");
    expect((await provider.submitSuggestion()).ok).toBe(false);
    expect(provider.hasDraft).toBe(true);
    failing = false;
    const suggestion = await provider.submitSuggestion().orThrow();
    expect(provider.hasDraft).toBe(false);
    const decided = await provider.acceptSuggestion(suggestion.id).orThrow();
    expect(decided.seq).toBe(5);
    await provider.destroy();
  });

  it("ignores suggest-mode edits without the suggest permission", async () => {
    const server = fakeServer(false, false);
    const doc = new Y.Doc();

    const provider = createDocumentProvider({
      documents: server.documents,
      client: fakeBus().client().client,
      doc,
      ref,
      yjs: Y,
    });

    await provider.connect().orThrow();
    provider.setMode("suggest");
    doc.getText("t").insert(0, "x");
    expect(provider.hasDraft).toBe(false);
    provider.setMode("edit");
    expect(provider.mode).toBe("edit");
    await provider.destroy();
  });

  it("skips the broadcast when an accept carries no sequence number", async () => {
    const server = fakeServer();
    const bus = fakeBus().client();
    const doc = new Y.Doc();
    const other = new Y.Doc();
    other.getText("t").insert(0, "late");

    const provider = createDocumentProvider({
      documents: {
        ...server.documents,
        decideSuggestion: () =>
          AsyncResult.ok<DecidedSuggestion>({
            id: "s1",
            documentId: DOC_ID,
            update: Y.encodeStateAsUpdate(other),
            status: "accepted",
            createdAt: temporal().Now.instant(),
          }),
      },
      client: bus.client,
      doc,
      ref,
      yjs: Y,
    });

    await provider.connect().orThrow();
    await provider.acceptSuggestion("s1").orThrow();
    expect(doc.getText("t").toString()).toBe("late");
    expect(bus.channel.send).not.toHaveBeenCalled();
    await provider.destroy();
  });

  it("loads yjs itself when it is not passed", async () => {
    const server = fakeServer();

    const provider = createDocumentProvider({
      documents: server.documents,
      client: fakeBus().client().client,
      doc: new Y.Doc(),
      ref,
    });

    await provider.connect().orThrow();
    await provider.destroy();
  });

  it("shares presence and exposes the opened document", async () => {
    const server = fakeServer();
    const bus = fakeBus().client();
    const seen: unknown[] = [];

    const provider = createDocumentProvider<{ name: string }>({
      documents: server.documents,
      client: bus.client,
      doc: new Y.Doc(),
      ref,
      yjs: Y,
      onPresence: (members) => seen.push(members),
    });

    expect(provider.document).toBeUndefined();
    expect(provider.members()).toEqual([]);
    const early = await provider.track({ name: "Ada" });
    expect(early.ok).toBe(false);
    const opened = await provider.connect().orThrow();
    expect(await provider.connect().orThrow()).toBe(opened);
    expect(provider.document?.id).toBe(DOC_ID);
    expect((await provider.track({ name: "Ada" })).ok).toBe(true);
    bus.sync({ k: [{ presence_ref: "1", name: "Ada" }] });
    await vi.waitFor(() => {
      expect(provider.members()).toHaveLength(1);
    });
    expect(seen.length).toBeGreaterThan(0);
    await provider[Symbol.asyncDispose]();
    expect(provider.status).toBe("closed");
  });

  it("applies broadcasts and ignores malformed ones", async () => {
    const server = fakeServer();
    const bus = fakeBus().client();
    const doc = new Y.Doc();

    const provider = createDocumentProvider({
      documents: server.documents,
      client: bus.client,
      doc,
      ref,
      yjs: Y,
    });

    await provider.connect().orThrow();
    const other = new Y.Doc();
    other.getText("t").insert(0, "hi");
    bus.deliver("nope");
    bus.deliver({ seq: "1", update: "x" });
    bus.deliver({ seq: 1, update: toBase64(Y.encodeStateAsUpdate(other)) });
    await vi.waitFor(() => {
      expect(doc.getText("t").toString()).toBe("hi");
    });
    await provider.destroy();
  });

  it("opens from a snapshot after compaction", async () => {
    const server = fakeServer();
    const seed = new Y.Doc();
    seed.on("update", (update: Uint8Array) => {
      void server.documents.push({ documentId: DOC_ID, update });
    });
    seed.getText("t").insert(0, "saved");
    await compactDocument({
      documents: server.documents,
      documentId: DOC_ID,
      yjs: Y,
    }).orThrow();
    const doc = new Y.Doc();

    const provider = createDocumentProvider({
      documents: server.documents,
      client: fakeBus().client().client,
      doc,
      ref,
      yjs: Y,
    });

    await provider.connect().orThrow();
    expect(doc.getText("t").toString()).toBe("saved");
    await provider.destroy();
  });

  it("reports open, pull and broadcast failures", async () => {
    const server = fakeServer();
    const failure = { kind: "network", message: "down" } as never;
    const statuses: string[] = [];

    const closed = createDocumentProvider({
      documents: {
        ...server.documents,
        open: () => AsyncResult.err<OpenedDocument>(failure),
      },
      client: fakeBus().client().client,
      doc: new Y.Doc(),
      ref,
      yjs: Y,
      onStatus: (status) => statuses.push(status),
    });

    expect((await closed.connect()).ok).toBe(false);
    expect(statuses).toEqual(["connecting", "closed"]);

    const errors: unknown[] = [];
    const bus = fakeBus().client();
    bus.channel.send.mockImplementation(async () => "error");
    const doc = new Y.Doc();

    const provider = createDocumentProvider({
      documents: {
        ...server.documents,
        pull: () => AsyncResult.err<DocumentState>(failure),
      },
      client: bus.client,
      doc,
      ref,
      yjs: Y,
      onError: (error) => errors.push(error),
    });

    await provider.connect().orThrow();
    doc.getText("t").insert(0, "a");
    await provider.flush();
    expect(String(errors[0])).toMatch(/broadcast failed/);
    bus.entry.report?.("SUBSCRIBED");
    await vi.waitFor(() => {
      expect(errors).toContain(failure);
    });
    await provider.destroy();
  });
});

describe("compactDocument", () => {
  it("merges the log into a snapshot that rebuilds the document", async () => {
    const server = fakeServer();
    const doc = new Y.Doc();
    doc.on("update", (update: Uint8Array) => {
      void server.documents.push({ documentId: DOC_ID, update });
    });
    doc.getText("t").insert(0, "one ");
    doc.getText("t").insert(4, "two");
    expect(server.count()).toBe(2);
    expect(
      await compactDocument({
        documents: server.documents,
        documentId: DOC_ID,
        yjs: Y,
      }).orThrow(),
    ).toBe(true);
    expect(server.count()).toBe(0);
    expect(server.snapshotSeq()).toBe(2);

    const copy = new Y.Doc();

    const state = await server.documents
      .pull({ documentId: DOC_ID, afterSeq: 0 })
      .orThrow();

    Y.applyUpdate(copy, state.snapshot!);
    expect(copy.getText("t").toString()).toBe("one two");
    expect(
      await compactDocument({
        documents: server.documents,
        documentId: DOC_ID,
        yjs: Y,
      }).orThrow(),
    ).toBe(false);
  });

  it("returns the pull error", async () => {
    const server = fakeServer();
    const failure = { kind: "network", message: "down" } as never;

    const result = await compactDocument({
      documents: {
        ...server.documents,
        pull: () => AsyncResult.err<DocumentState>(failure),
      },
      documentId: DOC_ID,
      yjs: Y,
    });

    expect(result.ok).toBe(false);
  });
});
