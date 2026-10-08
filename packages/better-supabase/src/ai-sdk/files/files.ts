import { createDownload, type Experimental_DownloadFunction } from "ai";

import type { AiFilePart } from "../../blocks/ai-chat/message.ts";
import type { AiFiles, AiFileSource } from "../../blocks/ai-files/ai-files.ts";
import type { DbError } from "../../core/errors.ts";

import { aiFileUrl, parseAiFileUrl } from "../../blocks/ai-files/ai-files.ts";
import { errorText } from "../../blocks/shared.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";

export interface AiFileDownloadOptions {
  /**
   * How other URLs download: the SDK's `createDownload()` by default, or
   * `false` to refuse every URL that isn't `supabase-storage://`.
   */
  readonly fallback?: Experimental_DownloadFunction | false;
  readonly abortSignal?: AbortSignal;
}

/** Thrown by the download function, so the SDK reports a failed file part. */
export class AiFileDownloadError extends Error {
  readonly error: DbError;
  constructor(url: URL, error: DbError) {
    super(`Could not download ${url.href}: ${error.message}`);
    this.name = "AiFileDownloadError";
    this.error = error;
  }
}

/**
 * The SDK's `experimental_download` for messages that hold
 * `supabase-storage://` file URLs: it reads each file as the caller, so a
 * user can never send a model someone else's file, and keeps the
 * `maxBytes` limit of `createAiFiles`.
 */
export function aiFileDownload(
  files: AiFiles,
  options: AiFileDownloadOptions = {},
): Experimental_DownloadFunction {
  const fallback = options.fallback ?? sdkDownload(options.abortSignal);
  return (requests) =>
    Promise.all(
      requests.map(async (request) => {
        if (parseAiFileUrl(request.url)) {
          const read = await files.files
            .resolve(request.url)
            .andThen((file) => files.files.read(file));
          if (!read.ok) throw new AiFileDownloadError(request.url, read.error);
          return { data: read.data.data, mediaType: read.data.file.mediaType };
        }
        if (request.isUrlSupportedByModel) return null;
        if (fallback === false) {
          throw new AiFileDownloadError(
            request.url,
            dbError("invalid_request", "Only supabase-storage:// URLs", {
              hint: "AI_FILE_URL",
            }),
          );
        }
        const [downloaded] = await fallback([request]);
        return downloaded ?? null;
      }),
    );
}

function sdkDownload(abortSignal?: AbortSignal): Experimental_DownloadFunction {
  const download = createDownload();
  return (requests) =>
    Promise.all(
      requests.map((request) =>
        download(
          abortSignal === undefined
            ? { url: request.url }
            : { url: request.url, abortSignal },
        ),
      ),
    );
}

/** A file a model generated: the SDK's `GeneratedFile`, typed structurally. */
export interface GeneratedFileLike {
  readonly uint8Array: Uint8Array;
  readonly mediaType: string;
}

export interface SaveGeneratedOptions {
  readonly organizationId: string;
  readonly ownerId: string;
  readonly chatId?: string;
  /** The file name for the n-th file; default `generated-{n}.{ext}`. */
  readonly filename?: (file: GeneratedFileLike, index: number) => string;
  readonly source?: AiFileSource;
}

const EXTENSIONS: Readonly<Record<string, string>> = {
  "image/png": "png",
  "image/jpeg": "jpg",
  "image/webp": "webp",
  "image/gif": "gif",
  "audio/mpeg": "mp3",
  "audio/wav": "wav",
  "audio/ogg": "ogg",
  "video/mp4": "mp4",
  "application/pdf": "pdf",
  "text/plain": "txt",
};

/**
 * Stores what `generateImage`, `generateSpeech` or a model's file output
 * returned (service role) and gives back file parts that point at them.
 */
export function saveGeneratedFiles(
  files: AiFiles,
  generated: readonly GeneratedFileLike[],
  options: SaveGeneratedOptions,
): AsyncResult<readonly AiFilePart[]> {
  return AsyncResult.from(async () => {
    const parts: AiFilePart[] = [];
    for (const [index, file] of generated.entries()) {
      const filename =
        options.filename?.(file, index) ??
        `generated-${String(index + 1)}.${EXTENSIONS[file.mediaType] ?? "bin"}`;
      const stored = await files.files.store(options.organizationId, {
        ownerId: options.ownerId,
        filename,
        mediaType: file.mediaType,
        data: file.uint8Array,
        source: options.source ?? "generated",
        ...(options.chatId === undefined ? {} : { chatId: options.chatId }),
      });
      if (!stored.ok) return err(stored.error);
      parts.push({
        type: "file",
        mediaType: stored.data.mediaType,
        url: aiFileUrl(stored.data),
        filename: stored.data.filename,
      });
    }
    return ok(parts);
  });
}

export interface ProviderFileUpload {
  /** What the provider's file API returned: a file id or a file URI. */
  readonly reference: string;
  readonly expiresAt?: Temporal.Instant;
}

/**
 * The provider's reference for a file, uploading it once with `upload`
 * (such as the SDK's `uploadFile` or a provider client) and reusing the
 * reference until it expires.
 */
export function providerFile(
  files: AiFiles,
  fileId: string,
  provider: string,
  upload: (file: {
    readonly data: Uint8Array;
    readonly mediaType: string;
    readonly filename: string;
  }) => Promise<ProviderFileUpload>,
): AsyncResult<string> {
  return files.providerFiles.get(fileId, provider).andThen(async (cached) => {
    if (cached) return ok(cached.reference);
    const read = await files.files.read(fileId);
    if (!read.ok) return err(read.error);
    let uploaded: ProviderFileUpload;
    try {
      uploaded = await upload({
        data: read.data.data,
        mediaType: read.data.file.mediaType,
        filename: read.data.file.filename,
      });
    } catch (cause) {
      return err(
        dbError(
          "network",
          `The ${provider} upload failed: ${errorText(cause)}`,
          {
            hint: "AI_PROVIDER_FILE_UPLOAD",
          },
        ),
      );
    }
    const saved = await files.providerFiles.set(
      fileId,
      provider,
      uploaded.reference,
      uploaded.expiresAt,
    );
    return saved.ok ? ok(uploaded.reference) : err(saved.error);
  });
}
