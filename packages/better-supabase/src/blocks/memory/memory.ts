import type { DbError } from "../../core/errors.ts";
import type { Result } from "../../core/result.ts";
import type {
  Memory,
  MemoryCommand,
  MemoryHit,
  MemoryNamespace,
  MemoryOptions,
  MemoryRecord,
  MemoryView,
} from "./types.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { vectorLiteral } from "../../core/search.ts";
import { checkVectors } from "../knowledge/knowledge.ts";
import {
  applyTemporal,
  blockCall,
  injectableOf,
  isRecord,
  recordsOf,
  run,
  textOf,
} from "../shared.ts";
import { documentOf, hitOf, memoryOf, recalledOf, viewOf } from "./rows.ts";

export type {
  Memory,
  MemoryCommand,
  MemoryDocument,
  MemoryHit,
  MemoryKind,
  MemoryNamespace,
  MemoryOptions,
  MemoryRecord,
  MemoryScope,
  MemoryView,
  RecalledMessage,
} from "./types.ts";

const nsArg = (ns: MemoryNamespace = {}): Record<string, string> => {
  const arg: Record<string, string> = {};
  if (ns.scope !== undefined) arg["scope"] = ns.scope;
  if (ns.agentId !== undefined) arg["agent_id"] = ns.agentId;
  if (ns.chatId !== undefined) arg["chat_id"] = ns.chatId;
  if (ns.projectId !== undefined) arg["project_id"] = ns.projectId;
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
  const embedder = injectableOf("embedder", options.embedder);
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
                recalledOf,
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
