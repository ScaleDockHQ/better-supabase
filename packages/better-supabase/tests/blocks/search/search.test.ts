import { describe, expect, it } from "vitest";

import type { CloudEvent } from "../../../src/events/cloud-event.ts";

import {
  createSearch,
  SEARCH_SINK_DEFAULTS,
  searchSink,
} from "../../../src/blocks/search/index.ts";
import { err, ok } from "../../../src/core/result.ts";

function recorder(results: Record<string, unknown> = {}) {
  const calls: { fn: string; args: unknown }[] = [];

  return {
    calls,
    transport: {
      call(_schema: string, fn: string, args: unknown) {
        calls.push({ fn, args });

        return Promise.resolve(results[fn] ?? null);
      },
    },
  };
}

const hit = {
  organizationId: "org",
  subjectType: "note",
  subjectId: "n1",
  title: "Revenue plan",
  url: "/notes/n1",
  snippet: "the revenue",
  score: "0.5",
};

const item = {
  subjectType: "note",
  subjectId: "n1",
  title: null,
  url: null,
  openedAt: "2026-10-01T10:00:00Z",
  starredAt: null,
};

const event = (type: string, data: unknown): CloudEvent => ({
  specversion: "1.0",
  id: type,
  source: "test",
  type,
  data,
});

describe("search block", () => {
  it("searches as the caller and maps the hits", async () => {
    const { calls, transport } = recorder({ search: [hit] });
    const search = createSearch({ transport });
    expect(await search.search({ q: "revenue" }).orThrow()).toEqual([
      { ...hit, score: 0.5 },
    ]);
    await search
      .search({
        q: "revenue",
        query: {
          types: ["note"],
          organizationId: "org",
          limit: 5,
          embedding: [0.1, 0.2],
        },
      })
      .orThrow();
    await search.search({ q: "revenue", query: { embedding: null } }).orThrow();
    expect(calls.map((call) => call.args)).toEqual([
      { q: "revenue", types: null, tenant: null, max_results: 20 },
      {
        q: "revenue",
        types: ["note"],
        tenant: "org",
        max_results: 5,
        query_embedding: "[0.1,0.2]",
      },
      { q: "revenue", types: null, tenant: null, max_results: 20 },
    ]);
  });

  it("rejects an embedding that is not finite before calling", async () => {
    const { calls, transport } = recorder();
    const search = createSearch({ transport });

    const result = await search.search({
      q: "x",
      query: { embedding: [Number.NaN] },
    });

    expect(result.ok).toBe(false);
    expect(calls).toEqual([]);
  });

  it("reads recents and favorites, and records opens and stars", async () => {
    const { calls, transport } = recorder({
      search_recents: [item],
      search_favorites: [],
      search_touch: true,
      search_star: true,
    });

    const search = createSearch({ transport });
    const [recent] = await search.recents().orThrow();
    expect(recent?.openedAt?.toString()).toBe("2026-10-01T10:00:00Z");
    expect(recent?.starredAt).toBeUndefined();
    await search.favorites({ limit: 3, types: ["note"] }).orThrow();
    expect(
      await search.touch({ subjectType: "note", subjectId: "n1" }).orThrow(),
    ).toBe(true);
    expect(
      await search.star({ subjectType: "note", subjectId: "n1" }).orThrow(),
    ).toBe(true);
    await search
      .star({ subjectType: "note", subjectId: "n1", starred: false })
      .orThrow();
    expect(calls.map((call) => call.args)).toEqual([
      { max_results: 10, types: null },
      { max_results: 3, types: ["note"] },
      { subject_type: "note", subject_id: "n1" },
      { subject_type: "note", subject_id: "n1", starred: true },
      { subject_type: "note", subject_id: "n1", starred: false },
    ]);
  });

  it("maintains the index through the service transport", async () => {
    const member = recorder();

    const service = recorder({
      search_refresh: true,
      search_remove: false,
      search_reindex: "4",
    });

    const search = createSearch({
      transport: member.transport,
      service: service.transport,
    });

    expect(
      await search.refresh({ subjectType: "note", subjectId: "n1" }).orThrow(),
    ).toBe(true);
    expect(
      await search.remove({ subjectType: "note", subjectId: "n1" }).orThrow(),
    ).toBe(false);
    expect(await search.reindex().orThrow()).toBe(4);
    await search.reindex("note").orThrow();
    expect(member.calls).toEqual([]);
    expect(service.calls.map((call) => [call.fn, call.args])).toEqual([
      ["search_refresh", { subject_type: "note", subject_id: "n1" }],
      ["search_remove", { subject_type: "note", subject_id: "n1" }],
      ["search_reindex", { subject_type: null }],
      ["search_reindex", { subject_type: "note" }],
    ]);
  });

  it("embeds pending documents and stores the vectors", async () => {
    const pending = [
      { subjectType: "note", subjectId: "n1", contentHash: "h1", text: "a" },
      { subjectType: "note", subjectId: "n2", contentHash: "h2", text: "b" },
    ];

    const { calls, transport } = recorder({
      search_pending_embeddings: pending,
      search_set_embeddings: 2,
    });

    const search = createSearch({ transport });
    const texts: string[][] = [];

    const stored = await search
      .embedPending({
        embed: (values) => {
          texts.push([...values]);

          return Promise.resolve(values.map((_, index) => [index, 1]));
        },
        limit: 10,
      })
      .orThrow();

    expect(stored).toBe(2);
    expect(texts).toEqual([["a", "b"]]);
    expect(calls.map((call) => call.args)).toEqual([
      { max_results: 10 },
      {
        subject_types: ["note", "note"],
        subject_ids: ["n1", "n2"],
        content_hashes: ["h1", "h2"],
        embeddings: ["[0,1]", "[1,1]"],
      },
    ]);
  });

  it("embeds nothing without pending documents, and checks the count", async () => {
    const empty = createSearch({
      transport: recorder({ search_pending_embeddings: [] }).transport,
    });

    expect(
      await empty
        .embedPending({ embed: () => Promise.reject(new Error("unused")) })
        .orThrow(),
    ).toBe(0);

    const short = createSearch({
      transport: recorder({
        search_pending_embeddings: [
          { subjectType: "a", subjectId: "1", contentHash: "h", text: "t" },
        ],
      }).transport,
    });

    const result = await short.embedPending({
      embed: () => Promise.resolve([]),
    });

    expect(result.ok ? undefined : result.error.message).toContain(
      "embed returned 0 vectors for 1 texts",
    );
  });

  it("runs block hooks around the methods", async () => {
    const seen: string[] = [];

    const search = createSearch({
      transport: recorder({ search_touch: true }).transport,
      hooks: {
        touch: {
          before: (args) => {
            seen.push(`before ${args[0].subjectType}/${args[0].subjectId}`);
          },
        },
      },
    });

    await search.touch({ subjectType: "note", subjectId: "n1" }).orThrow();
    expect(seen).toEqual(["before note/n1"]);
  });
});

describe("searchSink", () => {
  const index = () => {
    const calls: string[] = [];
    let failure: { hint?: string; message: string } | undefined;

    return {
      calls,
      fail(next: { hint?: string; message: string }) {
        failure = next;
      },
      search: {
        remove: ({
          subjectType: type,
          subjectId: id,
        }: {
          subjectType: string;
          subjectId: string;
        }) => {
          calls.push(`remove ${type}/${id}`);

          return Promise.resolve(failure ? err(failure as never) : ok(true));
        },
        refresh: ({
          subjectType: type,
          subjectId: id,
        }: {
          subjectType: string;
          subjectId: string;
        }) => {
          calls.push(`refresh ${type}/${id}`);

          return Promise.resolve(failure ? err(failure as never) : ok(true));
        },
      },
    };
  };

  it("removes trashed and purged subjects and refreshes restored ones", async () => {
    const target = index();
    const sink = searchSink(target.search as never);
    const data = { subjectType: "note", subjectId: "n1" };
    await sink.send([
      event("dev.better-supabase.subject.trashed", data),
      event("dev.better-supabase.subject.restored", data),
      event("dev.better-supabase.subject.purged", data),
      event("dev.better-supabase.subject.renamed", data),
      event("dev.better-supabase.subject.trashed", { subjectType: "note" }),
      event("dev.better-supabase.subject.trashed", "n1"),
    ]);
    expect(target.calls).toEqual([
      "remove note/n1",
      "refresh note/n1",
      "remove note/n1",
    ]);
    expect(SEARCH_SINK_DEFAULTS["subject.trashed"]).toBe("remove");
  });

  it("maps custom events and prefixes", async () => {
    const target = index();

    const sink = searchSink(target.search as never, {
      on: { "doc.archived": "remove" },
      typePrefix: "com.acme",
    });

    await sink.send([
      event("com.acme.doc.archived", { subjectType: "doc", subjectId: "d1" }),
    ]);
    expect(target.calls).toEqual(["remove doc/d1"]);
  });

  it("skips unknown subject types and throws on other errors", async () => {
    const target = index();
    const sink = searchSink(target.search as never);

    const trashed = event("dev.better-supabase.subject.trashed", {
      subjectType: "note",
      subjectId: "n1",
    });

    target.fail({ hint: "SEARCH_SUBJECT_UNKNOWN", message: "unknown" });
    await sink.send([trashed]);
    target.fail({ message: "boom" });
    await expect(sink.send([trashed])).rejects.toThrow(
      "searchSink: remove note/n1 failed: boom",
    );
  });
});
