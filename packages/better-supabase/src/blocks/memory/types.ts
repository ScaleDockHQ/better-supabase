import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { Embedder } from "../knowledge/knowledge.ts";
import type { BlockTemporalOptions } from "../shared.ts";

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
