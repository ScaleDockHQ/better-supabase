import type { BlockTransport } from "../../core/block-transport.ts";
import type { DbError, ErrorMapper } from "../../core/errors.ts";
import type { AiMessage, AiMessagePart } from "../ai-chat/message.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { fromStorageError } from "../../storage/errors.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  instantArg,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
  toInstant,
} from "../shared.ts";

interface StorageReply<T> {
  readonly data: T | null;
  readonly error: unknown;
}

/** The `supabase.storage.from(bucket)` methods the block uses. */
export interface AiFileBucket {
  createSignedUploadUrl(
    path: string,
  ): PromiseLike<
    StorageReply<{ readonly signedUrl: string; readonly token: string }>
  >;
  createSignedUrl(
    path: string,
    expiresIn: number,
  ): PromiseLike<StorageReply<{ readonly signedUrl: string }>>;
  download(path: string): PromiseLike<StorageReply<Blob>>;
  remove(paths: string[]): PromiseLike<StorageReply<unknown>>;
  upload?(
    path: string,
    body: Blob | ArrayBuffer | Uint8Array,
    options?: { readonly contentType?: string; readonly upsert?: boolean },
  ): PromiseLike<StorageReply<unknown>>;
}

/** `supabase.storage`, typed structurally. */
export interface AiFileStorage {
  from(bucket: string): AiFileBucket;
}

export interface AiFilesOptions extends BlockTemporalOptions {
  /** Calls as the user: `rpcTransport(supabase)`. */
  readonly transport: BlockTransport;
  /** The user's `supabase.storage`, so the bucket policies apply. */
  readonly storage: AiFileStorage;
  /** Calls as the service role, for `store`, provider files and `purge`. */
  readonly service?: BlockTransport;
  /** The service role's `supabase.storage`, for `store` and `purge`. */
  readonly serviceStorage?: AiFileStorage;
  /** The module schema (`sql.modules["ai-files"].schema`), default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /** Lifetime of a signed download URL in seconds. Default 300. */
  readonly downloadTtl?: number;
  /** The most bytes `read` returns before it fails. Default 50 MB. */
  readonly maxBytes?: number;
}

export type AiFileStatus = "pending" | "ready" | "failed";
export type AiFileSource = "upload" | "generated" | "provider";

export interface AiFile {
  readonly id: string;
  readonly organizationId: string;
  readonly ownerId: string;
  readonly chatId: string | undefined;
  readonly projectId: string | undefined;
  readonly bucket: string;
  /** `{organizationId}/{ownerId}/{id}/{filename}` in the bucket. */
  readonly path: string;
  readonly mediaType: string;
  readonly filename: string;
  readonly size: number;
  readonly sha256: string | undefined;
  readonly status: AiFileStatus;
  readonly source: AiFileSource;
  readonly createdAt: Temporal.Instant;
  readonly uploadedAt: Temporal.Instant | undefined;
  readonly expiresAt: Temporal.Instant | undefined;
}

export interface NewAiFile {
  readonly filename: string;
  readonly mediaType: string;
  /** Bytes; `confirm()` replaces it with the stored size. */
  readonly size: number;
  readonly chatId?: string;
  readonly projectId?: string;
}

export interface AiFileUpload {
  readonly file: AiFile;
  /** PUT the file here, or pass `token` to `uploadToSignedUrl(path, token, file)`. */
  readonly signedUrl: string;
  readonly token: string;
}

export interface StoredAiFile {
  /** The user the file belongs to. */
  readonly ownerId: string;
  readonly filename: string;
  readonly mediaType: string;
  readonly data: Uint8Array | Blob;
  readonly chatId?: string;
  readonly source?: AiFileSource;
}

export interface AiProviderFile {
  readonly fileId: string;
  readonly provider: string;
  /** What the provider's file API returned: a file id or a file URI. */
  readonly reference: string;
  readonly expiresAt: Temporal.Instant | undefined;
}

export type AiDocumentKind = "text" | "code" | "sheet" | "image";

export interface AiDocument {
  readonly id: string;
  readonly organizationId: string;
  readonly ownerId: string;
  readonly chatId: string | undefined;
  readonly kind: AiDocumentKind;
  readonly title: string;
  readonly version: number;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** A document with the content of its current version. */
export interface AiDocumentWithContent extends AiDocument {
  readonly content: string | undefined;
  /** A path in the bucket, for an image or a large document. */
  readonly storagePath: string | undefined;
}

export interface AiDocumentVersion {
  readonly documentId: string;
  readonly version: number;
  readonly content: string | undefined;
  readonly storagePath: string | undefined;
  /** The assistant message that wrote this version. */
  readonly messageId: string | undefined;
  readonly createdBy: string | undefined;
  readonly createdAt: Temporal.Instant;
}

export interface NewAiDocument {
  readonly kind: AiDocumentKind;
  readonly title: string;
  readonly content?: string;
  readonly storagePath?: string;
  readonly chatId?: string;
  readonly messageId?: string;
  /** The service role only: the user the document belongs to. */
  readonly ownerId?: string;
}

export interface AiDocumentEdit {
  readonly content?: string;
  readonly storagePath?: string;
  readonly title?: string;
  readonly messageId?: string;
  /** Fails with `conflict` when the document moved past this version. */
  readonly expectedVersion?: number;
}

export interface AiSuggestion {
  readonly id: string;
  readonly documentId: string;
  readonly version: number;
  readonly originalText: string;
  readonly suggestedText: string;
  readonly description: string | undefined;
  readonly createdBy: string | undefined;
  readonly createdAt: Temporal.Instant;
  readonly resolvedAt: Temporal.Instant | undefined;
  readonly accepted: boolean | undefined;
}

export interface AiFiles {
  readonly files: {
    /** Reserves the file and returns a signed upload URL for its path. */
    upload(organizationId: string, file: NewAiFile): AsyncResult<AiFileUpload>;
    /** Marks the upload done once the object exists. */
    confirm(fileId: string, sha256?: string): AsyncResult<AiFile>;
    get(fileId: string): AsyncResult<AiFile>;
    /** The file a `supabase-storage://` URL names, when the caller may read it. */
    resolve(url: string | URL): AsyncResult<AiFile>;
    list(chatId: string): AsyncResult<readonly AiFile[]>;
    /** A signed download URL that expires after `downloadTtl`. */
    sign(file: AiFile | string): AsyncResult<string>;
    /** The bytes of a ready file, refusing more than `maxBytes`. */
    read(
      file: AiFile | string,
    ): AsyncResult<{ readonly file: AiFile; readonly data: Uint8Array }>;
    /** Deletes the object and the record. */
    remove(fileId: string): AsyncResult<boolean>;
    /** Writes a ready file for `ownerId` from the server (service role). */
    store(organizationId: string, file: StoredAiFile): AsyncResult<AiFile>;
    /**
     * Deletes stale pending uploads, expired files and the files of
     * deleted chats, then their objects (service role). Returns how many.
     */
    purge(options?: {
      readonly olderThan?: string;
      readonly batch?: number;
    }): AsyncResult<number>;
  };
  readonly providerFiles: {
    /** The provider's reference while it is valid (service role). */
    get(
      fileId: string,
      provider: string,
    ): AsyncResult<AiProviderFile | undefined>;
    set(
      fileId: string,
      provider: string,
      reference: string,
      expiresAt?: Temporal.Instant,
    ): AsyncResult<boolean>;
    /** References that expire within `horizon` (an interval, default `1 day`). */
    expiring(
      horizon?: string,
      batch?: number,
    ): AsyncResult<readonly AiProviderFile[]>;
  };
  readonly documents: {
    create(
      organizationId: string,
      document: NewAiDocument,
    ): AsyncResult<AiDocument>;
    get(documentId: string): AsyncResult<AiDocumentWithContent>;
    update(documentId: string, edit: AiDocumentEdit): AsyncResult<AiDocument>;
    /** Writes `version` as the newest version again. */
    rollback(documentId: string, version: number): AsyncResult<AiDocument>;
    versions(documentId: string): AsyncResult<readonly AiDocumentVersion[]>;
    remove(documentId: string): AsyncResult<boolean>;
    suggest(
      documentId: string,
      suggestion: {
        readonly originalText: string;
        readonly suggestedText: string;
        readonly description?: string;
      },
    ): AsyncResult<AiSuggestion>;
    suggestions(
      documentId: string,
      options?: { readonly openOnly?: boolean },
    ): AsyncResult<readonly AiSuggestion[]>;
    resolve(suggestionId: string, accepted: boolean): AsyncResult<AiSuggestion>;
  };
  /**
   * Replaces the `supabase-storage://` URLs of file parts with signed
   * download URLs, so a browser or a provider can fetch them. Parts the
   * caller may not read keep their URL.
   */
  sign(messages: readonly AiMessage[]): Promise<readonly AiMessage[]>;
}

const SCHEME = "supabase-storage:";

/** The URL a message stores for a file: `supabase-storage://{bucket}/{path}`. */
export function aiFileUrl(file: Pick<AiFile, "bucket" | "path">): string {
  return `${SCHEME}//${file.bucket}/${file.path.split("/").map(encodeURIComponent).join("/")}`;
}

/** The bucket and path of a `supabase-storage://` URL, or `undefined`. */
export function parseAiFileUrl(
  url: string | URL,
): { readonly bucket: string; readonly path: string } | undefined {
  let parsed: URL;
  try {
    parsed = typeof url === "string" ? new URL(url) : url;
  } catch {
    return undefined;
  }
  if (parsed.protocol !== SCHEME || parsed.hostname === "") return undefined;
  const segments = parsed.pathname.split("/").filter((part) => part !== "");
  if (segments.length === 0) return undefined;
  try {
    return {
      bucket: decodeURIComponent(parsed.hostname),
      path: segments.map(decodeURIComponent).join("/"),
    };
  } catch {
    return undefined;
  }
}

const FILE_STATUSES: ReadonlySet<string> = new Set([
  "pending",
  "ready",
  "failed",
]);
const FILE_SOURCES: ReadonlySet<string> = new Set([
  "upload",
  "generated",
  "provider",
]);
const DOCUMENT_KINDS: ReadonlySet<string> = new Set([
  "text",
  "code",
  "sheet",
  "image",
]);

const fileStatus = (value: unknown): AiFileStatus => {
  const text = textOf(value);
  // SAFETY: FILE_STATUSES holds exactly the AiFileStatus members.
  return FILE_STATUSES.has(text) ? (text as AiFileStatus) : "failed";
};

const fileSource = (value: unknown): AiFileSource => {
  const text = textOf(value);
  // SAFETY: FILE_SOURCES holds exactly the AiFileSource members.
  return FILE_SOURCES.has(text) ? (text as AiFileSource) : "upload";
};

const documentKind = (value: unknown): AiDocumentKind => {
  const text = textOf(value);
  // SAFETY: DOCUMENT_KINDS holds exactly the AiDocumentKind members.
  return DOCUMENT_KINDS.has(text) ? (text as AiDocumentKind) : "text";
};

const instant = (value: unknown): Temporal.Instant =>
  value instanceof Date ? toInstant(value) : toInstant(textOf(value));

function fileOf(value: unknown): AiFile {
  const row = recordOf(value, "ai_files");
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organization_id"]),
    ownerId: textOf(row["owner_id"]),
    chatId: optionalText(row["chat_id"]),
    projectId: optionalText(row["project_id"]),
    bucket: textOf(row["bucket"]),
    path: textOf(row["path"]),
    mediaType: textOf(row["media_type"]),
    filename: textOf(row["filename"]),
    size: Number(row["byte_size"] ?? 0),
    sha256: optionalText(row["sha256"]),
    status: fileStatus(row["status"]),
    source: fileSource(row["source"]),
    createdAt: instant(row["created_at"]),
    uploadedAt: optionalInstant(row["uploaded_at"]),
    expiresAt: optionalInstant(row["expires_at"]),
  };
}

function providerFileOf(value: unknown): AiProviderFile {
  const row = recordOf(value, "ai_provider_files");
  return {
    fileId: textOf(row["file_id"]),
    provider: textOf(row["provider"]),
    reference: textOf(row["reference"]),
    expiresAt: optionalInstant(row["expires_at"]),
  };
}

function documentOf(value: unknown): AiDocument {
  const row = recordOf(value, "ai_documents");
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organization_id"]),
    ownerId: textOf(row["owner_id"]),
    chatId: optionalText(row["chat_id"]),
    kind: documentKind(row["kind"]),
    title: textOf(row["title"]),
    version: Number(row["current_version"] ?? 1),
    createdAt: instant(row["created_at"]),
    updatedAt: instant(row["updated_at"]),
  };
}

function versionOf(value: unknown): AiDocumentVersion {
  const row = recordOf(value, "ai_document_versions");
  return {
    documentId: textOf(row["document_id"]),
    version: Number(row["version"]),
    content: optionalText(row["content"]),
    storagePath: optionalText(row["storage_path"]),
    messageId: optionalText(row["created_by_message_id"]),
    createdBy: optionalText(row["created_by"]),
    createdAt: instant(row["created_at"]),
  };
}

function suggestionOf(value: unknown): AiSuggestion {
  const row = recordOf(value, "ai_suggestions");
  const accepted = row["accepted"];
  return {
    id: textOf(row["id"]),
    documentId: textOf(row["document_id"]),
    version: Number(row["version"]),
    originalText: textOf(row["original_text"]),
    suggestedText: textOf(row["suggested_text"]),
    description: optionalText(row["description"]),
    createdBy: optionalText(row["created_by"]),
    createdAt: instant(row["created_at"]),
    resolvedAt: optionalInstant(row["resolved_at"]),
    accepted: typeof accepted === "boolean" ? accepted : undefined,
  };
}

const notFound = (): DbError =>
  dbError("not_found", "No AI file you can see has this id", {
    hint: "AI_FILE_NOT_FOUND",
  });

const notReady = (): DbError =>
  dbError("invalid_request", "The file is not uploaded yet", {
    hint: "AI_FILE_NOT_READY",
  });

function stored<T>(
  reply: PromiseLike<StorageReply<T>>,
): AsyncResult<NonNullable<T>> {
  return AsyncResult.from(async () => {
    try {
      const { data, error } = await reply;
      if (error) return err(fromStorageError(error, "storage.objects"));
      if (data === null || data === undefined) {
        return err(dbError("network", "Storage returned no data"));
      }
      return ok(data);
    } catch (cause) {
      return err(fromStorageError(cause, "storage.objects"));
    }
  });
}

/** 50 MB, the module's default `maxSize`. */
const DEFAULT_MAX_BYTES = 50 * 1024 * 1024;

/** Files and documents for AI chats, as the caller and as the service role. */
export function createAiFiles(options: AiFilesOptions): AiFiles {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const service = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );
  const ttl = options.downloadTtl ?? 300;
  const maxBytes = options.maxBytes ?? DEFAULT_MAX_BYTES;
  const serviceStorage = options.serviceStorage ?? options.storage;

  const found = (value: unknown): AsyncResult<AiFile> =>
    isRecord(value)
      ? AsyncResult.ok(fileOf(value))
      : AsyncResult.err(notFound());
  const get = (fileId: string): AsyncResult<AiFile> =>
    call("get_ai_file", { file_id: fileId }, (value) => value).andThen(found);
  const fileFrom = (file: AiFile | string): AsyncResult<AiFile> =>
    typeof file === "string" ? get(file) : AsyncResult.ok(file);
  const resolve = (url: string | URL): AsyncResult<AiFile> => {
    const target = parseAiFileUrl(url);
    if (!target) {
      return AsyncResult.err(
        dbError("invalid_request", "Not a supabase-storage:// URL", {
          hint: "AI_FILE_URL",
        }),
      );
    }
    return call(
      "get_ai_file_by_path",
      { bucket: target.bucket, path: target.path },
      (value) => value,
    ).andThen(found);
  };
  const sign = (file: AiFile | string): AsyncResult<string> =>
    fileFrom(file).andThen((row) =>
      row.status === "ready"
        ? stored(
            options.storage.from(row.bucket).createSignedUrl(row.path, ttl),
          ).map((url) => url.signedUrl)
        : Promise.resolve(err(notReady())),
    );

  return {
    files: {
      upload: (organizationId, file) =>
        call(
          "reserve_ai_file",
          {
            tenant: organizationId,
            filename: file.filename,
            media_type: file.mediaType,
            byte_size: file.size,
            chat_id: file.chatId,
            project_id: file.projectId,
          },
          fileOf,
        ).andThen((created) =>
          stored(
            options.storage
              .from(created.bucket)
              .createSignedUploadUrl(created.path),
          ).map((url) => ({
            file: created,
            signedUrl: url.signedUrl,
            token: url.token,
          })),
        ),
      confirm: (fileId, sha256) =>
        call("confirm_ai_file", { file_id: fileId, sha256 }, fileOf),
      get,
      resolve,
      list: (chatId) =>
        call("list_ai_files", { chat_id: chatId }, (value) =>
          recordsOf(value, "list_ai_files").map(fileOf),
        ),
      sign,
      read: (file) =>
        fileFrom(file).andThen(async (row) => {
          if (row.status !== "ready") return err(notReady());
          if (row.size > maxBytes) {
            return err(
              dbError("invalid_request", "The file is larger than maxBytes", {
                hint: "AI_FILE_TOO_LARGE",
              }),
            );
          }
          const blob = await stored(
            options.storage.from(row.bucket).download(row.path),
          );
          if (!blob.ok) return err(blob.error);
          if (blob.data.size > maxBytes) {
            return err(
              dbError("invalid_request", "The file is larger than maxBytes", {
                hint: "AI_FILE_TOO_LARGE",
              }),
            );
          }
          return ok({
            file: row,
            data: new Uint8Array(await blob.data.arrayBuffer()),
          });
        }),
      remove: (fileId) =>
        call("delete_ai_file", { file_id: fileId }, (value) => value).andThen(
          async (value) => {
            if (!isRecord(value)) return ok(false);
            const removed = await stored(
              options.storage
                .from(textOf(value["bucket"]))
                .remove([textOf(value["path"])]),
            );
            return removed.ok ? ok(true) : err(removed.error);
          },
        ),
      store: (organizationId, file) =>
        service(
          "store_ai_file",
          {
            tenant: organizationId,
            owner: file.ownerId,
            filename: file.filename,
            media_type: file.mediaType,
            byte_size:
              file.data instanceof Uint8Array
                ? file.data.byteLength
                : file.data.size,
            chat_id: file.chatId,
            source: file.source ?? "generated",
          },
          fileOf,
        ).andThen(async (created) => {
          const target = serviceStorage.from(created.bucket);
          if (!target.upload) {
            return err(
              dbError("invalid_request", "The storage client has no upload", {
                hint: "AI_FILE_STORAGE_CLIENT",
              }),
            );
          }
          const sent = await stored(
            target.upload(created.path, file.data, {
              contentType: created.mediaType,
              upsert: false,
            }),
          );
          if (sent.ok) return ok(created);
          await service("delete_ai_file", { file_id: created.id }, () => true);
          return err(sent.error);
        }),
      purge: (purgeOptions = {}) =>
        service(
          "purge_ai_files",
          { older_than: purgeOptions.olderThan, batch: purgeOptions.batch },
          (value) => recordsOf(value, "purge_ai_files"),
        ).andThen(async (removed) => {
          const byBucket = new Map<string, string[]>();
          for (const row of removed) {
            const bucket = textOf(row["bucket"]);
            const paths = byBucket.get(bucket) ?? [];
            paths.push(textOf(row["path"]));
            byBucket.set(bucket, paths);
          }
          for (const [bucket, paths] of byBucket) {
            const result = await stored(
              serviceStorage.from(bucket).remove(paths),
            );
            if (!result.ok) return err(result.error);
          }
          return ok(removed.length);
        }),
    },
    providerFiles: {
      get: (fileId, provider) =>
        service(
          "get_ai_provider_file",
          { file_id: fileId, provider },
          (value) => (isRecord(value) ? providerFileOf(value) : undefined),
        ),
      set: (fileId, provider, reference, expiresAt) =>
        service(
          "set_ai_provider_file",
          {
            file_id: fileId,
            provider,
            reference,
            expires_at: instantArg(expiresAt),
          },
          (value) => value === true,
        ),
      expiring: (horizon, batch) =>
        service("expiring_ai_provider_files", { horizon, batch }, (value) =>
          recordsOf(value, "expiring_ai_provider_files").map(providerFileOf),
        ),
    },
    documents: {
      create: (organizationId, document) =>
        (document.ownerId === undefined ? call : service)(
          "create_ai_document",
          {
            tenant: organizationId,
            kind: document.kind,
            title: document.title,
            content: document.content,
            chat_id: document.chatId,
            message_id: document.messageId,
            owner: document.ownerId,
            storage_path: document.storagePath,
          },
          documentOf,
        ),
      get: (documentId) =>
        call(
          "get_ai_document",
          { document_id: documentId },
          (value) => value,
        ).andThen((value) =>
          Promise.resolve(
            isRecord(value)
              ? ok({
                  ...documentOf(value),
                  content: optionalText(value["content"]),
                  storagePath: optionalText(value["storage_path"]),
                })
              : err(
                  dbError("not_found", "No document you can see has this id", {
                    hint: "AI_DOCUMENT_NOT_FOUND",
                  }),
                ),
          ),
        ),
      update: (documentId, edit) =>
        call(
          "update_ai_document",
          {
            document_id: documentId,
            content: edit.content,
            title: edit.title,
            message_id: edit.messageId,
            expected_version: edit.expectedVersion,
            storage_path: edit.storagePath,
          },
          documentOf,
        ),
      rollback: (documentId, version) =>
        call(
          "rollback_ai_document",
          { document_id: documentId, version },
          documentOf,
        ),
      versions: (documentId) =>
        call(
          "list_ai_document_versions",
          { document_id: documentId },
          (value) =>
            recordsOf(value, "list_ai_document_versions").map(versionOf),
        ),
      remove: (documentId) =>
        call(
          "delete_ai_document",
          { document_id: documentId },
          (value) => value === true,
        ),
      suggest: (documentId, suggestion) =>
        call(
          "suggest_ai_document_edit",
          {
            document_id: documentId,
            original_text: suggestion.originalText,
            suggested_text: suggestion.suggestedText,
            description: suggestion.description,
          },
          suggestionOf,
        ),
      suggestions: (documentId, query = {}) =>
        call(
          "list_ai_suggestions",
          { document_id: documentId, open_only: query.openOnly ?? true },
          (value) => recordsOf(value, "list_ai_suggestions").map(suggestionOf),
        ),
      resolve: (suggestionId, accepted) =>
        call(
          "resolve_ai_suggestion",
          { suggestion_id: suggestionId, accepted },
          suggestionOf,
        ),
    },
    sign: async (messages) => {
      const signed = new Map<string, string | undefined>();
      for (const message of messages) {
        for (const part of message.parts) {
          if (part.type !== "file" || signed.has(part.url)) continue;
          if (!parseAiFileUrl(part.url)) continue;
          const result = await resolve(part.url).andThen(sign);
          signed.set(part.url, result.ok ? result.data : undefined);
        }
      }
      if (signed.size === 0) return messages;
      const swap = (part: AiMessagePart): AiMessagePart => {
        if (part.type !== "file") return part;
        const url = signed.get(part.url);
        return url === undefined ? part : { ...part, url };
      };
      return messages.map((message) => ({
        ...message,
        parts: message.parts.map(swap),
      }));
    },
  };
}
