import type { DbError } from "../../core/errors.ts";
import type { AiMessagePart } from "../ai-chat/message.ts";
import type { AiFile, AiFiles, AiFilesOptions, StorageReply } from "./types.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { fromStorageError } from "../../storage/errors.ts";
import {
  applyTemporal,
  blockCall,
  instantArg,
  isRecord,
  notFoundError,
  optionalText,
  recordsOf,
  textOf,
} from "../shared.ts";
import {
  documentOf,
  fileOf,
  providerFileOf,
  suggestionOf,
  versionOf,
} from "./rows.ts";

export type {
  AiDocument,
  AiDocumentEdit,
  AiDocumentKind,
  AiDocumentVersion,
  AiDocumentWithContent,
  AiFile,
  AiFileBucket,
  AiFiles,
  AiFileSource,
  AiFilesOptions,
  AiFileStatus,
  AiFileStorage,
  AiFileUpload,
  AiProviderFile,
  AiSuggestion,
  NewAiDocument,
  NewAiFile,
  StoredAiFile,
} from "./types.ts";

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

const notFound = (): DbError =>
  notFoundError("No AI file you can see has this id", "AI_FILE_NOT_FOUND");

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
