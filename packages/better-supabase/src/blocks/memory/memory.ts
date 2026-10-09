import type { BlockTransport } from "../../core/block-transport.ts";
import type { DbError, ErrorMapper } from "../../core/errors.ts";
import type { Result } from "../../core/result.ts";
import type { Embedder } from "../knowledge/knowledge.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { vectorLiteral } from "../../core/search.ts";
import { checkVectors } from "../knowledge/knowledge.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  isRecord,
  optionalText,
  recordOf,
  recordsOf,
  run,
  textOf,
  toInstant,
} from "../shared.ts";

export type MemoryScope = "user" | "agent" | "chat" | "organization";
export type MemoryKind = "core" | "archival";

/**
 * Whose memory a call reads or changes. The default is the caller's own
 * memory; `organization` memory is shared and only admins change it. The
 * service role names the user in `ownerId`.
 */
export interface MemoryNamespace {
  readonly scope?: MemoryScope;
  readonly agentId?: string;
  readonly chatId?: string;
  readonly ownerId?: string;
}

export interface MemoryRecord {
  readonly id: string;
  readonly organizationId: string;
  readonly ownerId: string | undefined;
  readonly scope: MemoryScope;
  readonly agentId: string | undefined;
  readonly chatId: string | undefined;
  readonly kind: MemoryKind;
  /** A path under `/memories`, for core memory. */
  readonly path: string | undefined;
  readonly content: string;
  readonly version: number;
  readonly embeddingModel: string | undefined;
  readonly sourceMessageId: string | undefined;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface MemoryHit extends MemoryRecord {
  readonly score: number;
  /** Cosine similarity to the query embedding, when both have one. */
  readonly similarity: number | undefined;
}

export type MemoryView =
  | {
      readonly type: "file";
      readonly path: string;
      readonly content: string;
      readonly version: number;
    }
  | {
      readonly type: "directory";
      readonly path: string;
      readonly entries: readonly {
        readonly path: string;
        readonly size: number;
      }[];
    };

/** The commands of Anthropic's memory tool (`memory_20250818`). */
export type MemoryCommand =
  | {
      readonly command: "view";
      readonly path: string;
      readonly view_range?: readonly [number, number];
    }
  | {
      readonly command: "create";
      readonly path: string;
      readonly file_text: string;
    }
  | {
      readonly command: "str_replace";
      readonly path: string;
      readonly old_str: string;
      readonly new_str?: string;
    }
  | {
      readonly command: "insert";
      readonly path: string;
      readonly insert_line: number;
      readonly insert_text: string;
    }
  | { readonly command: "delete"; readonly path: string }
  | {
      readonly command: "rename";
      readonly old_path: string;
      readonly new_path: string;
    };

export interface RecalledMessage {
  readonly chatId: string;
  readonly messageId: string;
  readonly similarity: number;
}

export interface MemoryOptions extends BlockTemporalOptions {
  /** Calls as the user: `rpcTransport(supabase)`. */
  readonly transport: BlockTransport;
  /** Calls as the service role, for embeddings and extracted memories. */
  readonly service?: BlockTransport;
  /** The module schema (`sql.modules.memory.schema`), default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /** Embeds archival memories, messages and queries. */
  readonly embedder?: Embedder;
  /** The most characters `render` returns. Default 8000. */
  readonly maxRender?: number;
  /** `saveExtracted` skips a fact this similar to a saved one. Default 0.92. */
  readonly dedupeThreshold?: number;
}

export interface Memory {
  readonly core: {
    view(
      organizationId: string,
      path?: string,
      ns?: MemoryNamespace,
    ): AsyncResult<MemoryView | undefined>;
    /** Creates or overwrites a file; `expectedVersion` 0 means it must be new. */
    write(
      organizationId: string,
      path: string,
      content: string,
      ns?: MemoryNamespace,
      options?: { readonly expectedVersion?: number },
    ): AsyncResult<MemoryRecord>;
    strReplace(
      organizationId: string,
      path: string,
      oldText: string,
      newText: string,
      ns?: MemoryNamespace,
    ): AsyncResult<MemoryRecord>;
    insert(
      organizationId: string,
      path: string,
      line: number,
      text: string,
      ns?: MemoryNamespace,
    ): AsyncResult<MemoryRecord>;
    /** Deletes a file or a directory. Returns how many files. */
    remove(
      organizationId: string,
      path: string,
      ns?: MemoryNamespace,
    ): AsyncResult<number>;
    rename(
      organizationId: string,
      oldPath: string,
      newPath: string,
      ns?: MemoryNamespace,
    ): AsyncResult<number>;
    list(
      organizationId: string,
      ns?: MemoryNamespace,
    ): AsyncResult<readonly MemoryRecord[]>;
  };
  /** Runs a memory tool command and returns the text for the model. */
  run(
    organizationId: string,
    command: MemoryCommand,
    ns?: MemoryNamespace,
  ): AsyncResult<string>;
  readonly archival: {
    save(
      organizationId: string,
      content: string,
      ns?: MemoryNamespace,
      options?: { readonly sourceMessageId?: string },
    ): AsyncResult<MemoryRecord>;
    search(
      organizationId: string,
      query: string,
      ns?: MemoryNamespace,
      options?: { readonly k?: number; readonly signal?: AbortSignal },
    ): AsyncResult<readonly MemoryHit[]>;
    list(
      organizationId: string,
      ns?: MemoryNamespace,
      options?: { readonly limit?: number },
    ): AsyncResult<readonly MemoryRecord[]>;
    /** Deletes a memory, or marks it replaced by `supersededBy`. */
    forget(
      memoryId: string,
      options?: { readonly supersededBy?: string },
    ): AsyncResult<boolean>;
  };
  readonly recall: {
    /** Embeds a message so later chats can recall it (service role). */
    index(message: {
      readonly organizationId: string;
      readonly chatId: string;
      readonly messageId: string;
      readonly userId: string;
      readonly text: string;
    }): AsyncResult<boolean>;
    /** The caller's earlier messages closest to `query`. */
    search(
      organizationId: string,
      query: string,
      options?: {
        readonly k?: number;
        readonly excludeChat?: string;
        /** The service role only: whose messages. */
        readonly ownerId?: string;
        readonly signal?: AbortSignal;
      },
    ): AsyncResult<readonly RecalledMessage[]>;
  };
  /**
   * Core memory as delimited text for a system prompt, cut at
   * `maxRender` characters. Empty when there is none.
   */
  render(organizationId: string, ns?: MemoryNamespace): AsyncResult<string>;
  /** Saves facts that aren't already remembered. Returns the new ones. */
  saveExtracted(
    organizationId: string,
    facts: readonly string[],
    ns?: MemoryNamespace,
    options?: { readonly sourceMessageId?: string },
  ): AsyncResult<readonly MemoryRecord[]>;
  /** Embeds memories edited since their last embedding (service role). Returns how many. */
  embedPending(options?: {
    readonly batch?: number;
    readonly signal?: AbortSignal;
  }): AsyncResult<number>;
  /**
   * Documents under an opaque scope key, for agent runtimes (service role).
   * A write names the version it read; a stale one fails with the hint
   * `MEMORY_DOCUMENT_CONFLICT`.
   */
  readonly documents: {
    read(
      scopeKey: string,
      path: string,
    ): AsyncResult<MemoryDocument | undefined>;
    /** `expectedVersion: null` means the document must not exist yet. */
    write(
      scopeKey: string,
      path: string,
      content: string,
      options: {
        readonly expectedVersion: string | null;
        /** Seconds until the document expires. */
        readonly expiresIn?: number;
      },
    ): AsyncResult<MemoryDocument>;
    /** Deletes expired documents, at most `batch`. Returns how many. */
    purge(batch?: number): AsyncResult<number>;
  };
}

export interface MemoryDocument {
  readonly content: string;
  /** Opaque; pass it back as `expectedVersion`. */
  readonly version: string;
}

const SCOPES: ReadonlySet<string> = new Set([
  "user",
  "agent",
  "chat",
  "organization",
]);

const scopeOf = (value: unknown): MemoryScope => {
  const text = textOf(value);
  // SAFETY: SCOPES holds exactly the MemoryScope members.
  return SCOPES.has(text) ? (text as MemoryScope) : "user";
};

const instant = (value: unknown): Temporal.Instant =>
  value instanceof Date ? toInstant(value) : toInstant(textOf(value));

function memoryOf(value: unknown): MemoryRecord {
  const row = recordOf(value, "memories");
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organization_id"]),
    ownerId: optionalText(row["owner_id"]),
    scope: scopeOf(row["scope"]),
    agentId: optionalText(row["agent_id"]),
    chatId: optionalText(row["chat_id"]),
    kind: row["kind"] === "core" ? "core" : "archival",
    path: optionalText(row["path"]),
    content: textOf(row["content"]),
    version: Number(row["version"] ?? 1),
    embeddingModel: optionalText(row["embedding_model"]),
    sourceMessageId: optionalText(row["source_message_id"]),
    createdAt: instant(row["created_at"]),
    updatedAt: instant(row["updated_at"]),
  };
}

function hitOf(value: unknown): MemoryHit {
  const row = recordOf(value, "memory_search");
  const similarity = row["similarity"];
  return {
    ...memoryOf(row),
    score: Number(row["score"]),
    similarity: typeof similarity === "number" ? similarity : undefined,
  };
}

function viewOf(value: unknown): MemoryView | undefined {
  if (!isRecord(value)) return undefined;
  if (value["type"] === "file") {
    return {
      type: "file",
      path: textOf(value["path"]),
      content: textOf(value["content"]),
      version: Number(value["version"]),
    };
  }
  return {
    type: "directory",
    path: textOf(value["path"]),
    entries: recordsOf(value["entries"], "memory_view").map((entry) => ({
      path: textOf(entry["path"]),
      size: Number(entry["size"]),
    })),
  };
}

function documentOf(value: unknown): MemoryDocument {
  const row = recordOf(value, "memory_document");
  return { content: textOf(row["content"]), version: textOf(row["version"]) };
}

const nsArg = (ns: MemoryNamespace = {}): Record<string, string> => {
  const arg: Record<string, string> = {};
  if (ns.scope !== undefined) arg["scope"] = ns.scope;
  if (ns.agentId !== undefined) arg["agent_id"] = ns.agentId;
  if (ns.chatId !== undefined) arg["chat_id"] = ns.chatId;
  if (ns.ownerId !== undefined) arg["owner_id"] = ns.ownerId;
  return arg;
};

const noEmbedder = (): DbError =>
  dbError("invalid_request", "createMemory has no embedder", {
    hint: "MEMORY_NO_EMBEDDER",
  });

/** Numbered lines, as the memory tool shows a file. */
function numbered(
  content: string,
  range: readonly [number, number] | undefined,
): string {
  const lines = content.split("\n");
  const from = Math.max(range?.[0] ?? 1, 1);
  const to = range === undefined || range[1] === -1 ? lines.length : range[1];
  return lines
    .slice(from - 1, to)
    .map((line, index) => `${String(from + index).padStart(6)}\t${line}`)
    .join("\n");
}

const escapeTag = (text: string): string =>
  text.replaceAll("</memory", "<\\/memory");

/** Core memory files, archival facts and recall over earlier chats. */
export function createMemory(options: MemoryOptions): Memory {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const service = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );
  const embedder = options.embedder;
  const maxRender = options.maxRender ?? 8000;
  const threshold = options.dedupeThreshold ?? 0.92;

  const embedOne = (
    text: string,
    signal?: AbortSignal,
  ): AsyncResult<string | undefined> =>
    embedder
      ? run(() =>
          embedder.embed([text], signal === undefined ? undefined : { signal }),
        ).map((vectors) =>
          vectors[0] === undefined ? undefined : vectorLiteral(vectors[0]),
        )
      : AsyncResult.ok(undefined);

  const view = (
    organizationId: string,
    path = "/memories",
    ns?: MemoryNamespace,
  ): AsyncResult<MemoryView | undefined> =>
    call(
      "memory_view",
      { tenant: organizationId, path, ns: nsArg(ns) },
      viewOf,
    );

  const core: Memory["core"] = {
    view,
    write: (organizationId, path, content, ns, writeOptions = {}) =>
      call(
        "memory_create",
        {
          tenant: organizationId,
          path,
          content,
          ns: nsArg(ns),
          expected_version: writeOptions.expectedVersion,
        },
        memoryOf,
      ),
    strReplace: (organizationId, path, oldText, newText, ns) =>
      call(
        "memory_str_replace",
        {
          tenant: organizationId,
          path,
          old_text: oldText,
          new_text: newText,
          ns: nsArg(ns),
        },
        memoryOf,
      ),
    insert: (organizationId, path, line, text, ns) =>
      call(
        "memory_insert",
        {
          tenant: organizationId,
          path,
          insert_line: line,
          insert_text: text,
          ns: nsArg(ns),
        },
        memoryOf,
      ),
    remove: (organizationId, path, ns) =>
      call(
        "memory_delete",
        { tenant: organizationId, path, ns: nsArg(ns) },
        Number,
      ),
    rename: (organizationId, oldPath, newPath, ns) =>
      call(
        "memory_rename",
        {
          tenant: organizationId,
          old_path: oldPath,
          new_path: newPath,
          ns: nsArg(ns),
        },
        Number,
      ),
    list: (organizationId, ns) =>
      call(
        "memory_list",
        { tenant: organizationId, ns: nsArg(ns), kind: "core" },
        (value) => recordsOf(value, "memory_list").map(memoryOf),
      ),
  };

  const save = (
    organizationId: string,
    content: string,
    ns: MemoryNamespace | undefined,
    saveOptions: { readonly sourceMessageId?: string } = {},
    viaService = false,
    embedded?: string,
  ): AsyncResult<MemoryRecord> =>
    (embedded === undefined
      ? embedOne(content)
      : AsyncResult.ok<string | undefined>(embedded)
    ).andThen((embedding) =>
      (viaService ? service : call)(
        "memory_save",
        {
          tenant: organizationId,
          content,
          ns: nsArg(ns),
          embedding,
          model: embedding === undefined ? undefined : embedder?.model,
          source_message_id: saveOptions.sourceMessageId,
        },
        memoryOf,
      ),
    );

  const search = (
    organizationId: string,
    query: string,
    ns: MemoryNamespace | undefined,
    searchOptions: { readonly k?: number; readonly signal?: AbortSignal } = {},
    viaService = false,
    embedded?: string,
  ): AsyncResult<readonly MemoryHit[]> =>
    (embedded === undefined
      ? embedOne(query, searchOptions.signal)
      : AsyncResult.ok<string | undefined>(embedded)
    ).andThen((embedding) =>
      (viaService ? service : call)(
        "memory_search",
        {
          tenant: organizationId,
          query_embedding: embedding,
          query_text: query,
          ns: nsArg(ns),
          k: searchOptions.k,
        },
        (value) => recordsOf(value, "memory_search").map(hitOf),
      ),
    );

  const runCommand = (
    organizationId: string,
    command: MemoryCommand,
    ns?: MemoryNamespace,
  ): AsyncResult<string> => {
    switch (command.command) {
      case "view":
        return view(organizationId, command.path, ns).map((result) => {
          if (result === undefined) return `${command.path} does not exist.`;
          if (result.type === "file") {
            return `Here's the content of ${result.path} with line numbers:\n${numbered(result.content, command.view_range)}`;
          }
          const entries = result.entries.map(
            (entry) => `${String(entry.size)}\t${entry.path}`,
          );
          return `Here are the files in ${result.path}:\n${entries.join("\n")}`;
        });
      case "create":
        return core
          .write(organizationId, command.path, command.file_text, ns)
          .map(() => `File created successfully at: ${command.path}`);
      case "str_replace":
        return core
          .strReplace(
            organizationId,
            command.path,
            command.old_str,
            command.new_str ?? "",
            ns,
          )
          .map(() => `The memory file ${command.path} has been edited.`);
      case "insert":
        return core
          .insert(
            organizationId,
            command.path,
            command.insert_line,
            command.insert_text,
            ns,
          )
          .map(() => `The memory file ${command.path} has been edited.`);
      case "delete":
        return core
          .remove(organizationId, command.path, ns)
          .map((count) =>
            count === 0
              ? `${command.path} does not exist.`
              : `Successfully deleted ${command.path}`,
          );
      case "rename":
        return core
          .rename(organizationId, command.old_path, command.new_path, ns)
          .map(
            () =>
              `Successfully renamed ${command.old_path} to ${command.new_path}`,
          );
      default: {
        const unknown: never = command;
        return AsyncResult.err(
          dbError(
            "invalid_request",
            `Unknown memory command ${JSON.stringify(unknown)}`,
            { hint: "MEMORY_COMMAND" },
          ),
        );
      }
    }
  };

  return {
    core,
    run: runCommand,
    archival: {
      save: (organizationId, content, ns, saveOptions) =>
        save(organizationId, content, ns, saveOptions),
      search: (organizationId, query, ns, searchOptions) =>
        search(organizationId, query, ns, searchOptions),
      list: (organizationId, ns, listOptions = {}) =>
        call(
          "memory_list",
          {
            tenant: organizationId,
            ns: nsArg(ns),
            kind: "archival",
            max_rows: listOptions.limit,
          },
          (value) => recordsOf(value, "memory_list").map(memoryOf),
        ),
      forget: (memoryId, forgetOptions = {}) =>
        call(
          "memory_forget",
          { memory_id: memoryId, superseded_by: forgetOptions.supersededBy },
          (value) => value === true,
        ),
    },
    recall: {
      index: (message) =>
        embedder
          ? embedOne(message.text).andThen((embedding) =>
              service(
                "set_ai_message_embedding",
                {
                  chat_id: message.chatId,
                  message_id: message.messageId,
                  user_id: message.userId,
                  tenant: message.organizationId,
                  embedding,
                  model: embedder.model,
                },
                (value) => value === true,
              ),
            )
          : AsyncResult.err(noEmbedder()),
      search: (organizationId, query, recallOptions = {}) =>
        embedder
          ? embedOne(query, recallOptions.signal).andThen((embedding) =>
              call(
                "recall_ai_messages",
                {
                  tenant: organizationId,
                  query_embedding: embedding,
                  k: recallOptions.k,
                  exclude_chat: recallOptions.excludeChat,
                  owner: recallOptions.ownerId,
                },
                (value) =>
                  recordsOf(value, "recall_ai_messages").map((row) => ({
                    chatId: textOf(row["chat_id"]),
                    messageId: textOf(row["message_id"]),
                    similarity: Number(row["similarity"]),
                  })),
              ),
            )
          : AsyncResult.err(noEmbedder()),
    },
    render: (organizationId, ns) =>
      core.list(organizationId, ns).map((files) => {
        if (files.length === 0) return "";
        const close = "</memories>";
        let text = "<memories>\n";
        for (const file of files) {
          const block = `<memory path="${file.path ?? ""}">\n${escapeTag(file.content)}\n</memory>\n`;
          if (text.length + block.length + close.length > maxRender) {
            text += `<!-- ${String(files.length)} files; the rest is cut at ${String(maxRender)} characters -->\n`;
            break;
          }
          text += block;
        }
        return text + close;
      }),
    saveExtracted: (organizationId, facts, ns, saveOptions) =>
      AsyncResult.from(async (): Promise<Result<MemoryRecord[]>> => {
        const saved: MemoryRecord[] = [];
        const contents = facts
          .map((fact) => fact.trim())
          .filter((content) => content !== "");
        if (contents.length === 0) return ok(saved);
        let embeddings: readonly (string | undefined)[] = [];
        if (embedder) {
          const vectors = await run(() => embedder.embed(contents));
          if (!vectors.ok) return vectors;
          const invalid = checkVectors(vectors.data, contents.length);
          if (invalid) return err(invalid);
          embeddings = vectors.data.map((vector) => vectorLiteral(vector));
        }
        for (const [index, content] of contents.entries()) {
          const embedding = embeddings[index];
          const similar = await search(
            organizationId,
            content,
            ns,
            { k: 1 },
            true,
            embedding,
          );
          if (!similar.ok) return similar;
          const nearest = similar.data[0];
          if (
            nearest !== undefined &&
            (nearest.content === content ||
              (nearest.similarity ?? 0) >= threshold)
          ) {
            continue;
          }
          const record = await save(
            organizationId,
            content,
            ns,
            saveOptions,
            true,
            embedding,
          );
          if (!record.ok) return record;
          saved.push(record.data);
        }
        return ok(saved);
      }),
    embedPending: (embedOptions = {}) =>
      embedder
        ? service(
            "pending_memory_embeddings",
            { batch: embedOptions.batch },
            (value) => recordsOf(value, "pending_memory_embeddings"),
          ).andThen((rows) =>
            AsyncResult.from(async () => {
              if (rows.length === 0) return ok(0);
              const vectors = await run(() =>
                embedder.embed(
                  rows.map((row) => textOf(row["content"])),
                  embedOptions.signal === undefined
                    ? undefined
                    : { signal: embedOptions.signal },
                ),
              );
              if (!vectors.ok) return vectors;
              const invalid = checkVectors(vectors.data, rows.length);
              if (invalid) return err(invalid);
              return service(
                "set_memory_embeddings",
                {
                  items: {
                    items: rows.map((row, index) => ({
                      id: textOf(row["id"]),
                      hash: row["hash"],
                      embedding: vectorLiteral(vectors.data[index] ?? []),
                    })),
                  },
                  model: embedder.model,
                },
                Number,
              );
            }),
          )
        : AsyncResult.err(noEmbedder()),
    documents: {
      read: (scopeKey, path) =>
        service(
          "memory_document_read",
          { scope_key: scopeKey, path },
          (value) => (isRecord(value) ? documentOf(value) : undefined),
        ),
      write: (scopeKey, path, content, writeOptions) =>
        service(
          "memory_document_write",
          {
            scope_key: scopeKey,
            path,
            content,
            expected_version: writeOptions.expectedVersion,
            expires_in: writeOptions.expiresIn,
          },
          documentOf,
        ),
      purge: (batch) => service("purge_memory_documents", { batch }, Number),
    },
  };
}
