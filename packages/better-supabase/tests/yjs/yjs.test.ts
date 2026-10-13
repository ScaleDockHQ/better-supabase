import { describe, expect, it, vi } from "vitest";
import * as Y from "yjs";

import type {
  Documents,
  DocumentState,
  OpenedDocument,
} from "../../src/blocks/documents/documents.ts";
import type { RealtimeClient } from "../../src/realtime/index.ts";

import { AsyncResult } from "../../src/core/result.ts";
import { temporal } from "../../src/core/temporal-required.ts";
import {
  compactDocument,
  createDocumentProvider,
} from "../../src/yjs/index.ts";

const DOC_ID = "00000000-0000-4000-8000-000000000001";

function fakeServer(canWrite = true) {
  const push = vi.fn();
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
        createdAt: now,
        updatedAt: now,
        ...stateAfter(0),
        ...(snapshot === undefined ? {} : { snapshot: snapshot.state }),
      };
      return AsyncResult.ok(opened);
    },
    push: (_id: string, update: Uint8Array) => {
      push();
      if (offline) {
        return AsyncResult.err<number>({
          kind: "network",
          message: "offline",
        } as never);
      }
      const seq = next++;
      updates.push({ seq, update });
      return AsyncResult.ok(seq);
    },
    pull: (_id, after) => AsyncResult.ok(stateAfter(after)),
    compact: (_id, state, through) => {
      snapshot = { state, seq: through };
      updates = updates.filter((item) => item.seq > through);
      return AsyncResult.ok(true);
    },
    saveVersion: () => AsyncResult.ok({ id: "v", number: 1 }),
    versions: () => AsyncResult.ok([]),
    version: () => AsyncResult.ok(new Uint8Array()),
    toCompact: () => AsyncResult.ok([DOC_ID]),
  };
  return {
    documents,
    push,
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
    report?: (status: string) => void;
  }[] = [];
  const client = () => {
    const entry: (typeof channels)[number] = { listeners: [] };
    channels.push(entry);
    const channel = {
      topic: "",
      on: (type: string, _filter: unknown, listener: Listener) => {
        if (type === "broadcast") entry.listeners.push(listener);
        return channel;
      },
      presenceState: () => ({}),
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
          if (other === entry) continue;
          for (const listener of other.listeners) listener(message);
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
    return { client: raw as unknown as RealtimeClient, entry, channel };
  };
  return { client };
}

const ref = {
  organizationId: "org",
  subjectType: "page",
  subjectId: "p1",
};

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
    const state = await server.documents.pull(DOC_ID, 0).orThrow();
    for (const item of state.updates) Y.applyUpdate(copy, item.update);
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
});

describe("compactDocument", () => {
  it("merges the log into a snapshot that rebuilds the document", async () => {
    const server = fakeServer();
    const doc = new Y.Doc();
    doc.on("update", (update: Uint8Array) => {
      void server.documents.push(DOC_ID, update);
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
    const state = await server.documents.pull(DOC_ID, 0).orThrow();
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
});
