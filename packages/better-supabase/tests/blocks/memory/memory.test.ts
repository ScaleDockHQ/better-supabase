import { describe, expect, it } from "vitest";

import type {
  Embedder,
  MemoryCommand,
} from "../../../src/blocks/memory/index.ts";
import type { BlockTransport } from "../../../src/core/block-transport.ts";

import { createMemory } from "../../../src/blocks/memory/index.ts";

const AT = "2026-01-01T00:00:00Z";

const memoryRow = (overrides: Record<string, unknown> = {}) => ({
  id: "m1",
  organization_id: "o1",
  owner_id: "u1",
  scope: "user",
  agent_id: null,
  chat_id: null,
  kind: "core",
  path: "/memories/a.md",
  content: "hello",
  version: 2,
  embedding_model: null,
  source_message_id: null,
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
      return Promise.resolve(handler(args));
    },
  };
  return { transport, calls };
}

const embedder: Embedder = {
  model: "m1",
  embed: (values) => Promise.resolve(values.map((value) => [value.length, 1])),
};

describe("createMemory", () => {
  it("maps the core commands to their functions and namespace", async () => {
    const { transport, calls } = fakeTransport({
      memory_view: (args) =>
        args["path"] === "/memories/a.md"
          ? {
              type: "file",
              path: "/memories/a.md",
              content: "one\ntwo\nthree",
              version: 3,
            }
          : args["path"] === "/memories"
            ? {
                type: "directory",
                path: "/memories",
                entries: [{ path: "/memories/a.md", size: 5 }],
              }
            : null,
      memory_create: () => memoryRow(),
      memory_str_replace: () => memoryRow(),
      memory_insert: () => memoryRow(),
      memory_delete: (args) => (args["path"] === "/memories/gone" ? 0 : 2),
      memory_rename: () => 1,
      memory_list: () => [
        memoryRow({ scope: "bogus", kind: "archival", path: null }),
      ],
    });
    const memory = createMemory({ transport });
    const ns = {
      scope: "agent",
      agentId: "a1",
      chatId: "c1",
      ownerId: "u1",
    } as const;
    const run = (command: MemoryCommand) =>
      memory.run("o1", command, ns).orThrow();

    expect(await run({ command: "view", path: "/memories" })).toBe(
      "Here are the files in /memories:\n5\t/memories/a.md",
    );
    expect(calls[0]?.args).toEqual({
      tenant: "o1",
      path: "/memories",
      ns: { scope: "agent", agent_id: "a1", chat_id: "c1", owner_id: "u1" },
    });
    expect(
      await run({
        command: "view",
        path: "/memories/a.md",
        view_range: [2, -1],
      }),
    ).toBe(
      "Here's the content of /memories/a.md with line numbers:\n     2\ttwo\n     3\tthree",
    );
    expect(await run({ command: "view", path: "/memories/a.md" })).toContain(
      "     1\tone",
    );
    expect(await run({ command: "view", path: "/memories/none" })).toBe(
      "/memories/none does not exist.",
    );
    expect(
      await run({ command: "create", path: "/memories/a.md", file_text: "x" }),
    ).toBe("File created successfully at: /memories/a.md");
    expect(
      await run({
        command: "str_replace",
        path: "/memories/a.md",
        old_str: "x",
      }),
    ).toBe("The memory file /memories/a.md has been edited.");
    expect(calls.at(-1)?.args).toMatchObject({ old_text: "x", new_text: "" });
    expect(
      await run({
        command: "insert",
        path: "/memories/a.md",
        insert_line: 1,
        insert_text: "y",
      }),
    ).toBe("The memory file /memories/a.md has been edited.");
    expect(await run({ command: "delete", path: "/memories/b" })).toBe(
      "Successfully deleted /memories/b",
    );
    expect(await run({ command: "delete", path: "/memories/gone" })).toBe(
      "/memories/gone does not exist.",
    );
    expect(
      await run({
        command: "rename",
        old_path: "/memories/a.md",
        new_path: "/memories/b.md",
      }),
    ).toBe("Successfully renamed /memories/a.md to /memories/b.md");
    const unknown = await memory.run(
      "o1",
      // SAFETY: an unknown command from a model that ignored the schema.
      { command: "copy" } as unknown as MemoryCommand,
    );
    expect(unknown.ok ? undefined : unknown.error.hint).toBe("MEMORY_COMMAND");

    const written = await memory.core
      .write("o1", "/memories/a.md", "x", {}, { expectedVersion: 2 })
      .orThrow();
    expect(written).toMatchObject({
      kind: "core",
      version: 2,
      ownerId: "u1",
      agentId: undefined,
    });
    expect(calls.at(-1)?.args).toMatchObject({ expected_version: 2, ns: {} });
    const listed = await memory.core.list("o1").orThrow();
    expect(listed[0]).toMatchObject({
      scope: "user",
      kind: "archival",
      path: undefined,
    });
    expect(await memory.core.view("o1").orThrow()).toMatchObject({
      type: "directory",
    });
  });

  it("renders core memory with escaped content and a size cap", async () => {
    const files = [
      memoryRow({ path: "/memories/a.md", content: "x </memory> y" }),
      memoryRow({ path: "/memories/b.md", content: "z".repeat(100) }),
    ];
    const { transport } = fakeTransport({ memory_list: () => files });
    const memory = createMemory({ transport, maxRender: 120 });
    const text = await memory.render("o1").orThrow();
    expect(text).toContain(
      '<memory path="/memories/a.md">\nx <\\/memory> y\n</memory>',
    );
    expect(text).toContain("2 files; the rest is cut at 120 characters");
    expect(text.endsWith("</memories>")).toBe(true);
    const empty = createMemory({
      transport: fakeTransport({ memory_list: () => [] }).transport,
    });
    expect(await empty.render("o1").orThrow()).toBe("");
    const all = await createMemory({ transport }).render("o1").orThrow();
    expect(all).not.toContain("cut");
  });

  it("saves, searches, lists and forgets archival memory", async () => {
    const { transport, calls } = fakeTransport({
      memory_save: (args) =>
        memoryRow({
          kind: "archival",
          path: null,
          content: args["content"],
          embedding_model: args["model"],
        }),
      memory_search: () => [
        { ...memoryRow({ kind: "archival" }), score: 0.03, similarity: 0.8 },
        { ...memoryRow(), score: 0.01, similarity: null },
      ],
      memory_list: () => [],
      memory_forget: () => true,
    });
    const memory = createMemory({ transport, embedder });
    const saved = await memory.archival
      .save("o1", "likes tea", undefined, { sourceMessageId: "msg1" })
      .orThrow();
    expect(saved.embeddingModel).toBe("m1");
    expect(calls[0]?.args).toMatchObject({
      embedding: "[9,1]",
      model: "m1",
      source_message_id: "msg1",
    });
    const hits = await memory.archival
      .search("o1", "tea", {}, { k: 2 })
      .orThrow();
    expect(hits.map((hit) => hit.similarity)).toEqual([0.8, undefined]);
    expect(calls[1]?.args).toMatchObject({
      query_embedding: "[3,1]",
      query_text: "tea",
      k: 2,
    });
    expect(
      await memory.archival.list("o1", {}, { limit: 3 }).orThrow(),
    ).toEqual([]);
    expect(calls[2]?.args).toMatchObject({ kind: "archival", max_rows: 3 });
    expect(
      await memory.archival.forget("m1", { supersededBy: "m2" }).orThrow(),
    ).toBe(true);
    expect(calls[3]?.args).toEqual({ memory_id: "m1", superseded_by: "m2" });

    const plain = createMemory({ transport });
    await plain.archival.save("o1", "x").orThrow();
    expect(calls.at(-1)?.args).toMatchObject({
      embedding: undefined,
      model: undefined,
    });
  });

  it("saves only facts it doesn't remember yet, as the service role", async () => {
    const nearest: Record<string, unknown> = {
      "likes tea": {
        ...memoryRow({ content: "likes tea" }),
        score: 1,
        similarity: 0.5,
      },
      "drinks tea": {
        ...memoryRow({ content: "loves tea" }),
        score: 1,
        similarity: 0.95,
      },
    };
    const user = fakeTransport({});
    const server = fakeTransport({
      memory_search: (args) => {
        const hit = nearest[String(args["query_text"])];
        return hit ? [hit] : [];
      },
      memory_save: (args) => memoryRow({ content: args["content"] }),
    });
    const memory = createMemory({
      transport: user.transport,
      service: server.transport,
      embedder,
    });
    const batches: (readonly string[])[] = [];
    const counting = createMemory({
      transport: user.transport,
      service: server.transport,
      embedder: {
        model: embedder.model,
        embed: (values) => {
          batches.push(values);
          return embedder.embed(values);
        },
      },
    });
    const saved = await counting
      .saveExtracted(
        "o1",
        ["likes tea", "drinks tea", "", "lives in Utrecht"],
        { ownerId: "u1" },
      )
      .orThrow();
    expect(saved.map((record) => record.content)).toEqual(["lives in Utrecht"]);
    expect(batches).toEqual([["likes tea", "drinks tea", "lives in Utrecht"]]);
    const searched = server.calls.filter((c) => c.fn === "memory_search");
    const stored = server.calls.find((c) => c.fn === "memory_save");
    expect(stored?.args["embedding"]).toBe(
      searched.at(-1)?.args["query_embedding"],
    );
    expect(user.calls).toEqual([]);
    expect(await memory.saveExtracted("o1", ["  ", ""]).orThrow()).toEqual([]);

    const failing = createMemory({
      transport: fakeTransport({}).transport,
      embedder,
    });
    expect((await failing.saveExtracted("o1", ["x"])).ok).toBe(false);
    const saveFails = createMemory({
      transport: fakeTransport({ memory_search: () => [] }).transport,
      embedder,
    });
    expect((await saveFails.saveExtracted("o1", ["x"])).ok).toBe(false);
  });

  it("indexes and recalls messages, and needs an embedder for it", async () => {
    const { transport, calls } = fakeTransport({
      set_ai_message_embedding: () => true,
      recall_ai_messages: () => [
        { chat_id: "c1", message_id: "m1", similarity: 0.7 },
      ],
    });
    const memory = createMemory({ transport, embedder });
    expect(
      await memory.recall
        .index({
          organizationId: "o1",
          chatId: "c1",
          messageId: "m1",
          userId: "u1",
          text: "hi",
        })
        .orThrow(),
    ).toBe(true);
    expect(calls[0]?.args).toEqual({
      chat_id: "c1",
      message_id: "m1",
      user_id: "u1",
      tenant: "o1",
      embedding: "[2,1]",
      model: "m1",
    });
    expect(
      await memory.recall
        .search("o1", "hi", { k: 2, excludeChat: "c9", ownerId: "u1" })
        .orThrow(),
    ).toEqual([{ chatId: "c1", messageId: "m1", similarity: 0.7 }]);
    expect(calls[1]?.args).toMatchObject({
      k: 2,
      exclude_chat: "c9",
      owner: "u1",
    });

    const bare = createMemory({ transport });
    for (const result of [
      await bare.recall.index({
        organizationId: "o1",
        chatId: "c1",
        messageId: "m1",
        userId: "u1",
        text: "hi",
      }),
      await bare.recall.search("o1", "hi"),
      await bare.embedPending(),
    ]) {
      expect(result.ok ? undefined : result.error.hint).toBe(
        "MEMORY_NO_EMBEDDER",
      );
    }
  });

  it("embeds memories edited since their last embedding", async () => {
    const { transport, calls } = fakeTransport({
      pending_memory_embeddings: () => [
        { id: "m1", content: "abc", hash: "h1" },
        { id: "m2", content: "de", hash: "h2" },
      ],
      set_memory_embeddings: () => 1,
    });
    const memory = createMemory({ transport, service: transport, embedder });
    expect(await memory.embedPending({ batch: 10 }).orThrow()).toBe(1);
    expect(calls.map((c) => c.fn)).toEqual([
      "pending_memory_embeddings",
      "set_memory_embeddings",
    ]);
    expect(calls[1]?.args).toEqual({
      items: {
        items: [
          { id: "m1", hash: "h1", embedding: "[3,1]" },
          { id: "m2", hash: "h2", embedding: "[2,1]" },
        ],
      },
      model: "m1",
    });

    const none = createMemory({
      transport: fakeTransport({ pending_memory_embeddings: () => [] })
        .transport,
      embedder,
    });
    expect(await none.embedPending().orThrow()).toBe(0);
    const short = createMemory({
      transport: fakeTransport({
        pending_memory_embeddings: () => [{ id: "m1", content: "a" }],
      }).transport,
      embedder: { model: "m1", embed: () => Promise.resolve([]) },
    });
    const shortResult = await short.embedPending();
    expect(shortResult.ok ? undefined : shortResult.error.hint).toBe(
      "EMBEDDING_INVALID",
    );
    const broken = createMemory({
      transport: fakeTransport({
        pending_memory_embeddings: () => [{ id: "m1", content: "a" }],
      }).transport,
      embedder: { model: "m1", embed: () => Promise.reject(new Error("down")) },
    });
    expect((await broken.embedPending()).ok).toBe(false);
    const unstored = createMemory({
      transport: fakeTransport({
        pending_memory_embeddings: () => [{ id: "m1", content: "a" }],
      }).transport,
      embedder,
    });
    expect((await unstored.embedPending()).ok).toBe(false);
    const aborted = new AbortController();
    aborted.abort();
    expect(
      await createMemory({
        transport: fakeTransport({ pending_memory_embeddings: () => [] })
          .transport,
        embedder,
      })
        .embedPending({ signal: aborted.signal })
        .orThrow(),
    ).toBe(0);
  });
});
