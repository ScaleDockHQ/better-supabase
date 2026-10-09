import { describe, expect, it, vi } from "vitest";

import type { AiFile, AiFiles } from "../../../src/blocks/ai-files/index.ts";
import type { Embedder } from "../../../src/blocks/knowledge/index.ts";
import type { BlockTransport } from "../../../src/core/block-transport.ts";

import { chunk, createKnowledge } from "../../../src/blocks/knowledge/index.ts";
import { AsyncResult } from "../../../src/core/result.ts";

const AT = "2026-01-01T00:00:00Z";

const documentRow = (overrides: Record<string, unknown> = {}) => ({
  id: "d1",
  organization_id: "o1",
  owner_id: "u1",
  scope: "user",
  scope_id: "u1",
  file_id: null,
  title: "Notes",
  source: null,
  metadata: { topic: "a" },
  status: "pending",
  error: null,
  chunk_count: 1,
  embedding_model: "m1",
  created_at: AT,
  updated_at: AT,
  ...overrides,
});

type Handler = (args: Record<string, unknown>) => unknown;

function fakeTransport(handlers: Record<string, Handler>) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const transport: BlockTransport = {
    call: (_schema, fn, args) => {
      calls.push({ fn, args });
      const handler = handlers[fn];
      if (!handler) return Promise.reject(new Error(`unexpected ${fn}`));
      try {
        return Promise.resolve(handler(args));
      } catch (cause) {
        return Promise.reject(cause);
      }
    },
  };
  return { transport, calls };
}

const embedder = (
  model = "m1",
): Embedder & { readonly batches: string[][] } => {
  const batches: string[][] = [];
  return {
    model,
    batches,
    embed: (values) => {
      batches.push([...values]);
      return Promise.resolve(values.map((_, index) => [index, 0.5]));
    },
  };
};

describe("chunk", () => {
  it("breaks at paragraphs, lines, sentences and words", () => {
    expect(chunk("")).toEqual([]);
    expect(chunk("short text")).toEqual([{ content: "short text", tokens: 3 }]);
    const paragraphs = chunk("aaaa aaaa\n\nbbbb bbbb", {
      size: 12,
      overlap: 0,
    });
    expect(paragraphs.map((c) => c.content)).toEqual([
      "aaaa aaaa",
      "bbbb bbbb",
    ]);
    const words = chunk("one two three four five six", {
      size: 10,
      overlap: 4,
    });
    expect(words.map((c) => c.content)).toEqual([
      "one two",
      "two three",
      "four five",
      "six",
    ]);
    expect(
      chunk("abcdefghij", { size: 4, overlap: 0 }).map((c) => c.content),
    ).toEqual(["abcd", "efgh", "ij"]);
    expect(chunk("a\r\nb", { size: 10 }).map((c) => c.content)).toEqual([
      "a\nb",
    ]);
  });

  it("rejects a bad size or overlap", () => {
    expect(() => chunk("x", { size: 0 })).toThrow(/size/);
    expect(() => chunk("x", { size: 4, overlap: 4 })).toThrow(/overlap/);
    expect(() => chunk("x", { overlap: -1 })).toThrow(/overlap/);
  });
});

describe("createKnowledge", () => {
  it("creates, lists, gets, writes and removes documents", async () => {
    const { transport, calls } = fakeTransport({
      create_knowledge_document: () => documentRow(),
      write_knowledge_chunks: () => documentRow({ chunk_count: 2 }),
      get_knowledge_document: (args) =>
        args["document_id"] === "d1" ? documentRow({ status: "ready" }) : null,
      list_knowledge_documents: () => [
        documentRow(),
        documentRow({ id: "d2", scope: "bogus", status: "bogus" }),
      ],
      delete_knowledge_document: () => true,
    });
    const knowledge = createKnowledge({ transport, embedder: embedder() });

    const created = await knowledge.documents
      .create("o1", { title: "Notes", scope: "user", metadata: { a: 1 } })
      .orThrow();
    expect(created).toMatchObject({
      id: "d1",
      scope: "user",
      scopeId: "u1",
      fileId: undefined,
      metadata: { topic: "a" },
      chunkCount: 1,
      embeddingModel: "m1",
    });
    expect(created.createdAt.toString()).toBe("2026-01-01T00:00:00Z");

    const ingested = await knowledge.ingest
      .text("o1", { title: "Notes", text: "hello world" })
      .orThrow();
    expect(ingested.chunkCount).toBe(2);
    expect(calls.at(-1)).toEqual({
      fn: "write_knowledge_chunks",
      args: {
        document_id: "d1",
        chunks: { items: [{ content: "hello world", tokens: 3 }] },
        model: "m1",
      },
    });

    expect((await knowledge.documents.get("d1").orThrow()).status).toBe(
      "ready",
    );
    const missing = await knowledge.documents.get("nope");
    expect(missing.ok ? undefined : missing.error.hint).toBe(
      "KNOWLEDGE_NOT_FOUND",
    );
    const listed = await knowledge.documents
      .list("o1", { scope: "user", scopeId: "u1", limit: 5 })
      .orThrow();
    expect(listed.map((d) => [d.scope, d.status])).toEqual([
      ["user", "pending"],
      ["user", "failed"],
    ]);
    expect(
      calls.find((c) => c.fn === "list_knowledge_documents")?.args,
    ).toEqual({
      tenant: "o1",
      scope: "user",
      scope_id: "u1",
      max_rows: 5,
    });
    expect(await knowledge.documents.remove("d1").orThrow()).toBe(true);
  });

  it("ingests a file through ai-files and the extractor", async () => {
    const { transport, calls } = fakeTransport({
      create_knowledge_document: (args) =>
        documentRow({ file_id: args["file_id"], title: args["title"] }),
      write_knowledge_chunks: () => documentRow({ file_id: "f1" }),
    });
    const file = (mediaType: string): AiFile =>
      ({
        id: "f1",
        filename: "notes.md",
        mediaType,
      }) as AiFile;
    const read = vi.fn((fileId: string) =>
      AsyncResult.ok({
        file: file(fileId === "pdf" ? "application/pdf" : "text/markdown"),
        data: new TextEncoder().encode("# Notes"),
      }),
    );
    // SAFETY: the block calls only files.read.
    const files = { files: { read } } as unknown as AiFiles;
    const knowledge = createKnowledge({ transport, files });

    const doc = await knowledge.ingest.file("o1", "f1").orThrow();
    expect(doc.fileId).toBe("f1");
    expect(calls[0]?.args).toMatchObject({
      file_id: "f1",
      title: "notes.md",
      source: "notes.md",
    });
    const pdf = await knowledge.ingest.file("o1", "pdf");
    expect(pdf.ok ? undefined : pdf.error.hint).toBe("KNOWLEDGE_UNSUPPORTED");

    const extract = vi.fn(() => Promise.resolve("from a pdf"));
    const custom = createKnowledge({ transport, files, extract });
    await custom.ingest.file("o1", "pdf", { title: "Report" }).orThrow();
    expect(extract).toHaveBeenCalledOnce();

    const noFiles = await createKnowledge({ transport }).ingest.file(
      "o1",
      "f1",
    );
    expect(noFiles.ok ? undefined : noFiles.error.hint).toBe(
      "KNOWLEDGE_NO_FILES",
    );
  });

  it("processes pending chunks in batches until the document is ready", async () => {
    let pending = [
      { idx: 0, content: "a", hash: "ha" },
      { idx: 1, content: "b", hash: "hb" },
      { idx: 2, content: "c", hash: "hc" },
    ];
    const { transport: service, calls } = fakeTransport({
      pending_knowledge_chunks: (args) =>
        pending.slice(0, Number(args["batch"])),
      set_knowledge_embeddings: (args) => {
        const items = (args["embeddings"] as { items: { idx: number }[] })
          .items;
        pending = pending.filter(
          (row) => !items.some((item) => item.idx === row.idx),
        );
        return pending.length;
      },
    });
    const model = embedder();
    const knowledge = createKnowledge({
      transport: service,
      service,
      embedder: model,
      batchSize: 2,
    });
    expect(await knowledge.process("d1").orThrow()).toBe(0);
    expect(model.batches).toEqual([["a", "b"], ["c"]]);
    expect(
      calls.find((c) => c.fn === "set_knowledge_embeddings")?.args,
    ).toEqual({
      document_id: "d1",
      embeddings: {
        items: [
          { idx: 0, hash: "ha", embedding: "[0,0.5]" },
          { idx: 1, hash: "hb", embedding: "[1,0.5]" },
        ],
      },
      model: "m1",
    });
    expect(await knowledge.process("d1").orThrow()).toBe(0);
  });

  it("rejects vectors that don't match the chunks", async () => {
    const { transport, calls } = fakeTransport({
      pending_knowledge_chunks: () => [
        { idx: 0, content: "a", hash: "ha" },
        { idx: 1, content: "b", hash: "hb" },
      ],
      set_knowledge_embeddings: () => 0,
    });
    for (const vectors of [
      [[1, 2]],
      [[1, 2], [3]],
      [
        [1, 2],
        [Number.NaN, 1],
      ],
      [[], []],
    ]) {
      const result = await createKnowledge({
        transport,
        embedder: { model: "m1", embed: () => Promise.resolve(vectors) },
      }).process("d1");
      expect(result.ok ? undefined : result.error).toMatchObject({
        kind: "invalid_input",
        hint: "EMBEDDING_INVALID",
      });
    }
    expect(calls.some((c) => c.fn === "set_knowledge_embeddings")).toBe(false);
  });

  it("stops when a round leaves the same chunks waiting", async () => {
    const { transport, calls } = fakeTransport({
      pending_knowledge_chunks: () => [{ idx: 0, content: "a", hash: "old" }],
      set_knowledge_embeddings: () => 1,
    });
    const knowledge = createKnowledge({ transport, embedder: embedder() });
    expect(await knowledge.process("d1").orThrow()).toBe(1);
    expect(
      calls.filter((c) => c.fn === "set_knowledge_embeddings"),
    ).toHaveLength(2);
  });

  it("stops processing on abort and fails without an embedder", async () => {
    const { transport } = fakeTransport({
      pending_knowledge_chunks: () => [{ idx: 0, content: "a" }],
      set_knowledge_embeddings: () => 3,
    });
    const controller = new AbortController();
    const knowledge = createKnowledge({
      transport,
      embedder: {
        model: "m1",
        embed: (values) => {
          controller.abort();
          return Promise.resolve(values.map(() => [1]));
        },
      },
    });
    expect(
      await knowledge.process("d1", { signal: controller.signal }).orThrow(),
    ).toBe(3);
    const bare = await createKnowledge({ transport }).process("d1");
    expect(bare.ok ? undefined : bare.error.hint).toBe("KNOWLEDGE_NO_EMBEDDER");
    const broken = await createKnowledge({
      transport: fakeTransport({}).transport,
    }).process("d1");
    expect(broken.ok).toBe(false);
  });

  it("drains pending documents and marks failures", async () => {
    const { transport, calls } = fakeTransport({
      pending_knowledge_documents: () => ["d1", "d2"],
      pending_knowledge_chunks: (args) =>
        args["document_id"] === "d1" ? [] : [{ idx: 0, content: "x" }],
      fail_knowledge_document: () => true,
    });
    const embed = vi.fn(() => Promise.reject(new Error("down")));
    const knowledge = createKnowledge({
      transport,
      embedder: { model: "m1", embed },
    });
    expect(await knowledge.drain({ batch: 5 }).orThrow()).toBe(1);
    expect(embed).toHaveBeenCalledTimes(3);
    expect(calls.find((c) => c.fn === "fail_knowledge_document")?.args).toEqual(
      {
        document_id: "d2",
        error: "down",
      },
    );
    const flaky = vi
      .fn()
      .mockRejectedValueOnce(new Error("blip"))
      .mockResolvedValue([[1]]);
    const retried = fakeTransport({
      pending_knowledge_documents: () => ["d3"],
      pending_knowledge_chunks: () => [{ idx: 0, content: "x", hash: "h" }],
      set_knowledge_embeddings: () => 0,
      fail_knowledge_document: () => true,
    });
    expect(
      await createKnowledge({
        transport: retried.transport,
        embedder: { model: "m1", embed: flaky },
      })
        .drain({ attempts: 2 })
        .orThrow(),
    ).toBe(1);
    expect(retried.calls.some((c) => c.fn === "fail_knowledge_document")).toBe(
      false,
    );
    const controller = new AbortController();
    controller.abort();
    expect(await knowledge.drain({ signal: controller.signal }).orThrow()).toBe(
      0,
    );
    const empty = createKnowledge({
      transport: fakeTransport({ pending_knowledge_documents: () => null })
        .transport,
    });
    expect(await empty.drain().orThrow()).toBe(0);
  });

  it("runs as a job and fails the document on the last attempt", async () => {
    const { transport, calls } = fakeTransport({
      pending_knowledge_chunks: () => [{ idx: 0, content: "x" }],
      fail_knowledge_document: () => true,
    });
    const knowledge = createKnowledge({
      transport,
      embedder: {
        model: "m1",
        embed: () => Promise.reject(new Error("quota")),
      },
    });
    const handler = knowledge.embedJob();
    const signal = new AbortController().signal;
    // SAFETY: the handler reads only attempts and maxAttempts.
    const job = (attempts: number) => ({ attempts, maxAttempts: 2 }) as never;
    await expect(
      Promise.resolve(handler({ document_id: "d1" }, job(1), signal)),
    ).rejects.toThrow("quota");
    expect(calls.some((c) => c.fn === "fail_knowledge_document")).toBe(false);
    await expect(
      Promise.resolve(handler({ document_id: "d1" }, job(2), signal)),
    ).rejects.toThrow("quota");
    expect(calls.some((c) => c.fn === "fail_knowledge_document")).toBe(true);

    const done = createKnowledge({
      transport: fakeTransport({ pending_knowledge_chunks: () => [] })
        .transport,
    }).embedJob();
    await expect(
      Promise.resolve(done({ document_id: "d1" }, job(1), signal)),
    ).resolves.toBeUndefined();
  });

  it("searches with an embedded query, a given embedding or text only", async () => {
    const hit = {
      document_id: "d1",
      idx: 0,
      content: "hello",
      metadata: null,
      title: "Notes",
      score: 0.03,
    };
    const { transport, calls } = fakeTransport({
      knowledge_search: () => [hit],
      reembed_knowledge: () => 4,
    });
    const model = embedder();
    const knowledge = createKnowledge({ transport, embedder: model });
    const hits = await knowledge
      .search("o1", "hello", {
        scopes: [{ scope: "organization" }],
        k: 3,
        filter: { topic: "a" },
      })
      .orThrow();
    expect(hits).toEqual([
      {
        documentId: "d1",
        index: 0,
        content: "hello",
        metadata: {},
        title: "Notes",
        score: 0.03,
      },
    ]);
    expect(calls[0]?.args).toEqual({
      tenant: "o1",
      query_embedding: "[0,0.5]",
      query_text: "hello",
      scopes: { items: [{ scope: "organization" }] },
      k: 3,
      filter: { topic: "a" },
    });
    await knowledge.search("o1", { embedding: [1, 2] }).orThrow();
    expect(calls[1]?.args).toMatchObject({
      query_embedding: "[1,2]",
      query_text: undefined,
    });
    await knowledge.search("o1", "").orThrow();
    expect(calls[2]?.args).toMatchObject({
      query_embedding: undefined,
      query_text: undefined,
    });
    await createKnowledge({ transport }).search("o1", "hi").orThrow();
    expect(calls[3]?.args).toMatchObject({
      query_embedding: undefined,
      query_text: "hi",
    });
    expect(model.batches).toEqual([["hello"]]);

    expect(
      await knowledge.reembed({ organizationId: "o1", model: "m2" }).orThrow(),
    ).toBe(4);
    expect(calls.at(-1)?.args).toEqual({ tenant: "o1", model: "m2" });
  });
});
