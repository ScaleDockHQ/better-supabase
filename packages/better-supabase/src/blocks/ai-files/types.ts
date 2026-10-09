import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { AiMessage } from "../ai-chat/message.ts";
import type { BlockTemporalOptions } from "../shared.ts";

export interface StorageReply<T> {
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
