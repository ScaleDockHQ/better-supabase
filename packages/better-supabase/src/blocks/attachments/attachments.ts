import type { Author } from "../../core/block-authors.ts";
import type { BlockFields, FieldsOf } from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTenantOptions } from "../../core/block-tenant.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { DbError, ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { Result } from "../../core/result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { EventSink } from "../../events/index.ts";
import type { RecordRef } from "../../schema/types.ts";
import type { ImageTransform, TransformOptions } from "../../storage/bucket.ts";
import type { TtlPreset } from "../../storage/ttl.ts";
import type { JobHandler } from "../queue/types.ts";
import type { BlockTemporalOptions } from "../shared.ts";
import type { UploadClaimStorage } from "../upload-claim.ts";

import { authorOf } from "../../core/block-authors.ts";
import {
  allWithFields,
  blockFields,
  extraOf,
  extraFieldsArg,
  withFields,
} from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { optionalRecordRefOf } from "../../core/block-subjects.ts";
import { requireOrganization } from "../../core/block-tenant.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok, toDbError } from "../../core/result.ts";
import { fromStorageError } from "../../storage/errors.ts";
import { ttlSeconds } from "../../storage/ttl.ts";
import { transformFor } from "../../storage/variants.ts";
import {
  blockCall,
  errorText,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
  toInstant,
  applyTemporal,
} from "../shared.ts";
import { claimsUploads, claimUpload } from "../upload-claim.ts";

interface StorageReply<T> {
  readonly data: T | null;
  readonly error: unknown;
}

/** The `supabase.storage.from(bucket)` methods attachments use. */
export interface AttachmentBucket {
  createSignedUploadUrl(
    path: string,
  ): PromiseLike<
    StorageReply<{ readonly signedUrl: string; readonly token: string }>
  >;
  createSignedUrl(
    path: string,
    expiresIn: number,
    options?: { download?: string | boolean; transform?: TransformOptions },
  ): PromiseLike<StorageReply<{ readonly signedUrl: string }>>;
  download(path: string): PromiseLike<StorageReply<Blob>>;
  /** Used by `publicUrl`, for files in `options.publicBuckets`. */
  getPublicUrl?(
    path: string,
    options?: { download?: string | boolean; transform?: TransformOptions },
  ): { readonly data: { readonly publicUrl: string } };
  remove(paths: string[]): PromiseLike<StorageReply<unknown>>;
  /** Used by `put`, which uploads from the server. */
  upload?(
    path: string,
    body: Blob | ArrayBuffer | Uint8Array,
    options?: { readonly contentType?: string; readonly upsert?: boolean },
  ): PromiseLike<StorageReply<unknown>>;
}

/** `supabase.storage`, typed structurally. */
export interface AttachmentStorage extends UploadClaimStorage {
  from(bucket: string): AttachmentBucket;
}

export interface AttachmentsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
>
  extends BlockTemporalOptions, BlockTenantOptions {
  /**
   * The subject types configured with `tenant: false`. Their files have no
   * organization, so `upload`, `put` and `list` on such a subject send no
   * tenant and need none.
   */
  readonly tenantless?: readonly string[];
  /**
   * A Standard Schema for the attachment columns the app adds
   * (`blocks.attachments.options.extraColumns`), keyed by column name. It types
   * and parses them on every read, and validates them on `upload` and `put`,
   * which return a `validation` error for a bad value.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Attachments<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  /** The caller's transport (`rpcTransport(supabase)`). */
  readonly transport: BlockTransport;
  /** The caller's `supabase.storage`, so the bucket policies apply. */
  readonly storage: AttachmentStorage;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`. Default `better_supabase`.
   */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /**
   * `blocks.attachments.options.requireScan`, which `defineBlocks` passes from
   * `blocks.generated.ts`. Default `true`.
   */
  readonly requireScan?: boolean;
  /**
   * `blocks.attachments.options.publicBuckets`, which `defineBlocks` passes
   * from `blocks.generated.ts`: the buckets `publicUrl` serves. Default none.
   */
  readonly publicBuckets?: readonly string[];
  /** Lifetime of a signed download URL in seconds. Default 300. */
  readonly downloadTtl?: number;
}

export type AttachmentStatus = "pending" | "clean" | "infected" | "failed";

export interface Attachment {
  readonly id: string;
  /** `undefined` for a file of a subject without a tenant (`tenant: false`). */
  readonly organizationId: string | undefined;
  /** `undefined` for a file uploaded without a subject. */
  readonly subject: RecordRef | undefined;
  readonly bucket: string;
  /**
   * The current version's object path in the bucket:
   * `{organizationId}/attachments/{id}` unless `options.path` says otherwise,
   * with `-v<version>` from version 2 on.
   */
  readonly path: string;
  readonly name: string;
  readonly mimeType: string;
  readonly size: number;
  /** Starts at 1; `replace` adds one, `restore` goes back to an earlier one. */
  readonly version: number;
  /** The image's width in pixels, as the uploader measured it. */
  readonly width: number | undefined;
  /** The image's height in pixels, as the uploader measured it. */
  readonly height: number | undefined;
  /** The document's page count, as the uploader counted it. */
  readonly pages: number | undefined;
  readonly status: AttachmentStatus;
  /** What the scanner reported, such as the signature it matched. */
  readonly scanDetail: string | undefined;
  /** What `upload` stored with the file; `{}` without any. */
  readonly metadata: Readonly<Record<string, unknown>>;
  readonly uploadedBy: string | undefined;
  /**
   * The uploader's name and avatar from `profiles`, on `list()`; `undefined`
   * without the `profiles` module or once the account is deleted.
   */
  readonly author: Author | undefined;
  readonly createdAt: Temporal.Instant;
  /** Set by `confirm()` once the object exists. */
  readonly uploadedAt: Temporal.Instant | undefined;
  readonly scannedAt: Temporal.Instant | undefined;
}

export interface NewAttachment {
  readonly name: string;
  readonly mimeType: string;
  /** Bytes; `confirm()` replaces it with the stored size. */
  readonly size: number;
  /**
   * App data about the file, such as a caption or its source, kept with the
   * record.
   */
  readonly metadata?: Readonly<Record<string, unknown>>;
  /** The image's width in pixels, for previews and layout before loading. */
  readonly width?: number;
  /** The image's height in pixels. */
  readonly height?: number;
  /** The document's page count. */
  readonly pages?: number;
}

/** A new version of a file for `replace`: what changes with the bytes. */
export type AttachmentReplacement = Omit<NewAttachment, "metadata">;

/** An earlier version of a file, kept when it was replaced. */
export interface AttachmentVersion {
  readonly attachmentId: string;
  readonly version: number;
  readonly bucket: string;
  readonly path: string;
  readonly name: string;
  readonly mimeType: string;
  readonly size: number;
  readonly width: number | undefined;
  readonly height: number | undefined;
  readonly pages: number | undefined;
  readonly status: AttachmentStatus;
  readonly scanDetail: string | undefined;
  readonly uploadedBy: string | undefined;
  readonly uploadedAt: Temporal.Instant | undefined;
  readonly scannedAt: Temporal.Instant | undefined;
  /** When the version stopped being the current one. */
  readonly archivedAt: Temporal.Instant;
}

/** What `images().signedUrl` takes: `useImage` passes its options here. */
export interface AttachmentImageUrlOptions<V extends string = never> {
  /** Seconds or a preset. Defaults to the client's `downloadTtl`. */
  readonly ttl?: number | TtlPreset;
  readonly transform?: ImageTransform<V>;
}

/**
 * Image previews of attachments, shaped for `useImage(source, attachment,
 * transform)` from `better-supabase/react`: a signed, resized URL per pixel
 * density, behind the same scan gate as `download`.
 */
export interface AttachmentImages<V extends string = never> {
  readonly bucket: {
    readonly id: string;
    readonly public: false;
    readonly variants: Readonly<Record<V, TransformOptions>>;
  };
  /**
   * The public URL of an image in one of `options.publicBuckets`, resized by
   * `transform`. Any other file, or a target given by id, is an
   * `invalid_request` error with hint `ATTACHMENT_PRIVATE`.
   */
  publicUrl(
    target: Attachment | string,
    options?: { readonly transform?: ImageTransform<V> },
  ): Result<string>;
  /**
   * A signed URL of the image resized by `transform`. `ATTACHMENT_NOT_SCANNED`
   * until the scan passes, `ATTACHMENT_NOT_IMAGE` for a file that is not
   * `image/*`. A target given by id is read first.
   */
  signedUrl(
    target: Attachment | string,
    options?: AttachmentImageUrlOptions<V>,
  ): AsyncResult<string>;
}

export interface AttachmentUpload<F extends object = Record<never, never>> {
  readonly attachment: Attachment & F;
  /**
   * PUT the file here, or pass `token` to `uploadToSignedUrl(path, token,
   * file)`.
   */
  readonly signedUrl: string;
  readonly token: string;
}

export interface AttachmentDownload<F extends object = Record<never, never>> {
  readonly attachment: Attachment & F;
  readonly signedUrl: string;
}

/**
 * `F` is the extra attachment fields `options.fields` describes. The methods
 * that create or list files act in the block's `tenant`, except on a subject
 * type in `options.tenantless`.
 */
export interface Attachments<F extends object = Record<never, never>> {
  /**
   * Creates the pending record on `subject` (`null` for a file without one) and
   * a signed upload URL for its path. When Storage refuses the URL, the record
   * is deleted again.
   */
  upload(
    subject: RecordRef | null,
    attachment: NewAttachment & Partial<F>,
  ): AsyncResult<AttachmentUpload<F>>;
  /**
   * Marks the upload done after the file is stored; emits
   * `attachment.uploaded`.
   */
  confirm(id: string): AsyncResult<Attachment & F>;
  get(id: string): AsyncResult<Attachment & F>;
  /** The files of `subject`, or every file of the tenant without one. */
  list(subject?: RecordRef | null): AsyncResult<readonly (Attachment & F)[]>;
  /**
   * A signed URL for a file the scanner passed. `invalid_request` with hint
   * `ATTACHMENT_NOT_SCANNED` until then, and for an infected file.
   */
  download(
    id: string,
    options?: {
      readonly as?: string | boolean;
      /** An earlier version from `versions(id)`; default the current one. */
      readonly version?: number;
    },
  ): AsyncResult<AttachmentDownload<F>>;
  /**
   * The public URL of a file in one of `options.publicBuckets`, which Storage
   * serves without a signed URL. A file in a private bucket is an
   * `invalid_request` error with hint `ATTACHMENT_PRIVATE`.
   */
  publicUrl(
    attachment: Attachment,
    options?: { readonly as?: string | boolean },
  ): Result<string>;
  /**
   * Deletes every version's file, then the record (the uploader, or
   * `attachments.manage`).
   */
  remove(id: string): AsyncResult<boolean>;
  /**
   * Starts a new version of the file (its uploader with `attachments.upload`,
   * or `attachments.manage`): the current one becomes an earlier version, and
   * the new one waits for its upload to the signed URL, `confirm` and the scan.
   * Emits `attachment.replaced`.
   */
  replace(
    id: string,
    file: AttachmentReplacement,
  ): AsyncResult<AttachmentUpload<F>>;
  /** The file's earlier versions, newest first. */
  versions(id: string): AsyncResult<readonly AttachmentVersion[]>;
  /**
   * Makes an earlier version current again; the current one becomes an earlier
   * version. Emits `attachment.restored`.
   */
  restore(id: string, version: number): AsyncResult<Attachment & F>;
  /**
   * Image previews for `useImage`, with the app's named variants (`{ thumb: {
   * width: 160, height: 160, resize: "cover" } }`).
   */
  images<V extends string = never>(
    variants?: Readonly<Record<V, TransformOptions>>,
  ): AttachmentImages<V>;
  /**
   * Creates the record on `subject` (`null` for none), uploads `file` from the
   * server and confirms it, for files the server makes or fetches (an export, a
   * generated PDF, an import). Returns the confirmed attachment, which still
   * waits for the scan when the module requires one. When Storage refuses the
   * upload, the record is deleted again, so no pending record is left behind.
   */
  put(
    subject: RecordRef | null,
    attachment: NewAttachment & Partial<F>,
    file: Blob | ArrayBuffer | Uint8Array,
  ): AsyncResult<Attachment & F>;
  /**
   * The file's bytes, for server-side processing, behind the same scan gate as
   * `download`: `ATTACHMENT_NOT_SCANNED` until the scan passes.
   */
  read(
    id: string,
  ): AsyncResult<{ readonly attachment: Attachment & F; readonly file: Blob }>;
}

const STATUSES: readonly AttachmentStatus[] = [
  "pending",
  "clean",
  "infected",
  "failed",
];

function statusOf(value: unknown): AttachmentStatus {
  const status = STATUSES.find((candidate) => candidate === value);

  if (status === undefined) {
    throw new TypeError(`Unknown attachment status ${JSON.stringify(value)}`);
  }

  return status;
}

const optionalCount = (value: unknown): number | undefined =>
  value === null || value === undefined ? undefined : Number(value);

/** An attachments row, as `get_attachment` and `create_attachment` return it. */
export function attachmentOf(value: unknown): Attachment {
  const row = recordOf(value, "attachments");

  return {
    id: textOf(row["id"]),
    organizationId: optionalText(row["organization_id"]),
    subject: optionalRecordRefOf(row["subject_type"], row["subject_id"]),
    bucket: textOf(row["bucket"]),
    path: textOf(row["object_path"]),
    name: textOf(row["name"]),
    mimeType: textOf(row["mime_type"]),
    size: Number(row["size"]),
    version: Number(row["version"] ?? 1),
    width: optionalCount(row["width"]),
    height: optionalCount(row["height"]),
    pages: optionalCount(row["pages"]),
    status: statusOf(row["status"]),
    scanDetail: optionalText(row["scan_detail"]),
    metadata: isRecord(row["metadata"]) ? row["metadata"] : {},
    uploadedBy: optionalText(row["uploaded_by"]),
    author: authorOf(row["author"]),
    createdAt: toInstant(textOf(row["created_at"])),
    uploadedAt: optionalInstant(row["uploaded_at"]),
    scannedAt: optionalInstant(row["scanned_at"]),
  };
}

/** An `attachment_versions` row, as `list_attachment_versions` returns it. */
export function attachmentVersionOf(value: unknown): AttachmentVersion {
  const row = recordOf(value, "attachment_versions");

  return {
    attachmentId: textOf(row["attachment_id"]),
    version: Number(row["version"]),
    bucket: textOf(row["bucket"]),
    path: textOf(row["object_path"]),
    name: textOf(row["name"]),
    mimeType: textOf(row["mime_type"]),
    size: Number(row["size"]),
    width: optionalCount(row["width"]),
    height: optionalCount(row["height"]),
    pages: optionalCount(row["pages"]),
    status: statusOf(row["status"]),
    scanDetail: optionalText(row["scan_detail"]),
    uploadedBy: optionalText(row["uploaded_by"]),
    uploadedAt: optionalInstant(row["uploaded_at"]),
    scannedAt: optionalInstant(row["scanned_at"]),
    archivedAt: toInstant(textOf(row["archived_at"])),
  };
}

/** The parts of a file version `download` reads. */
type FileVersion = Pick<
  Attachment,
  "bucket" | "path" | "status" | "uploadedAt"
>;

const CLAIM_HINTS = {
  notUploaded: "ATTACHMENT_NOT_UPLOADED",
  forbidden: "ATTACHMENT_FORBIDDEN",
} as const;

const notFound = (): DbError =>
  dbError("not_found", "No attachment you can see has this id", {
    hint: "ATTACHMENT_NOT_FOUND",
  });

/** A Storage reply as a result, its error mapped to a `DbError`. */
export function stored<T>(
  reply: PromiseLike<StorageReply<T>>,
): AsyncResult<NonNullable<T>> {
  return AsyncResult.from(async () => {
    try {
      const { data, error } = await reply;

      if (error) {
        return err(fromStorageError(error, "storage.objects"));
      }

      if (data === null || data === undefined) {
        return err(dbError("network", "Storage returned no data"));
      }

      return ok(data);
    } catch (cause) {
      return err(fromStorageError(cause, "storage.objects"));
    }
  });
}

/**
 * Waits for a scan from a job or an event. A scan whose target is gone (the
 * attachment row, or for an object the stored object) is done, not a failure,
 * so the job or event is not retried; every other error throws.
 */
async function settle(
  scanned: AsyncResult<unknown>,
  gone: (error: DbError) => boolean,
): Promise<void> {
  const result = await scanned;

  if (result.ok || gone(result.error)) {
    return;
  }

  await scanned.orThrow();
}

const attachmentGone = (error: DbError): boolean =>
  error.kind === "not_found" && error.hint === "ATTACHMENT_NOT_FOUND";

const objectGone = (error: DbError): boolean =>
  error.kind === "not_found" && error.code === "NoSuchKey";

function lookup(
  call: ReturnType<typeof blockCall>,
  id: string,
): AsyncResult<Attachment> {
  return call("get_attachment", { id }, (value) => value).andThen((value) =>
    Promise.resolve(
      isRecord(value) ? ok(attachmentOf(value)) : err(notFound()),
    ),
  );
}

/** Attachments as the caller: the table's and the bucket's policies apply. */
const NEW_ATTACHMENT: ReadonlySet<string> = new Set([
  "name",
  "mimeType",
  "size",
  "metadata",
  "width",
  "height",
  "pages",
]);

export function createAttachments<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: AttachmentsOptions<S>): Attachments<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const fields: BlockFields<F> = blockFields(
    options.fields,
    "attachment fields",
  );

  const tenantless: ReadonlySet<string> = new Set(options.tenantless);

  const tenantOf = (
    subject: RecordRef | null | undefined,
  ): AsyncResult<string | null> =>
    subject !== null && subject !== undefined && tenantless.has(subject.type)
      ? AsyncResult.ok(null)
      : requireOrganization(options.tenant).map(
          (tenant): string | null => tenant,
        );

  const typed = (value: unknown): AsyncResult<Attachment & F> =>
    AsyncResult.from(() => withFields(fields, value, attachmentOf(value)));

  const find = (id: string): AsyncResult<Attachment & F> =>
    call("get_attachment", { id }, (value) => value).andThen((value) =>
      isRecord(value) ? typed(value) : AsyncResult.err(notFound()),
    );

  const confirmed = (id: string): AsyncResult<Attachment & F> =>
    call("confirm_attachment", { id }, (value) => value).andThen(typed);

  const confirm = (id: string): AsyncResult<Attachment & F> =>
    claimsUploads(options.storage)
      ? lookup(call, id).andThen((attachment) =>
          attachment.uploadedAt === undefined
            ? claimUpload(options.storage, attachment, CLAIM_HINTS).andThen(
                () => confirmed(id),
              )
            : confirmed(id),
        )
      : confirmed(id);

  const requireScan = options.requireScan ?? true;
  const ttl = options.downloadTtl ?? 300;

  const bucket = (attachment: Attachment): AttachmentBucket =>
    options.storage.from(attachment.bucket);

  /** Why a file can't be read yet, or `undefined` once it can. */
  const gate = (
    attachment: Pick<Attachment, "status" | "uploadedAt">,
  ): DbError | undefined => {
    const readable =
      attachment.status === "clean" ||
      (!requireScan &&
        attachment.status !== "infected" &&
        attachment.uploadedAt !== undefined);

    return readable
      ? undefined
      : dbError(
          "invalid_request",
          attachment.status === "infected"
            ? "The file failed the malware scan"
            : "The file is not scanned yet",
          { hint: "ATTACHMENT_NOT_SCANNED" },
        );
  };

  const publicBuckets: ReadonlySet<string> = new Set(options.publicBuckets);

  const publicUrl = (
    attachment: Attachment,
    url: { download?: string | boolean; transform?: TransformOptions } = {},
  ): Result<string> => {
    const target = bucket(attachment);

    if (!publicBuckets.has(attachment.bucket) || !target.getPublicUrl) {
      return err(
        dbError("invalid_request", "The file's bucket is not public", {
          hint: "ATTACHMENT_PRIVATE",
        }),
      );
    }

    const blocked = gate(attachment);

    if (blocked !== undefined) {
      return err(blocked);
    }

    return ok(target.getPublicUrl(attachment.path, url).data.publicUrl);
  };

  const listVersions = (
    id: string,
  ): AsyncResult<readonly AttachmentVersion[]> =>
    call("list_attachment_versions", { id }, (value) =>
      recordsOf(value, "list_attachment_versions").map(attachmentVersionOf),
    );

  const versionOf = (id: string, version: number): AsyncResult<FileVersion> =>
    listVersions(id).andThen((earlier) => {
      const found = earlier.find((each) => each.version === version);

      return Promise.resolve(
        found === undefined
          ? err(
              dbError("not_found", "The file has no version with this number", {
                hint: "ATTACHMENT_VERSION_NOT_FOUND",
              }),
            )
          : ok(found),
      );
    });

  const discard = async (
    created: Attachment,
    error: DbError,
  ): Promise<Result<never>> => {
    await call("delete_attachment", { id: created.id }, (value) => value);

    return err(error);
  };

  const create = (
    subject: RecordRef | null,
    attachment: NewAttachment,
  ): AsyncResult<Attachment & F> =>
    tenantOf(subject)
      .andThen((organizationId) =>
        AsyncResult.from(() =>
          extraFieldsArg(fields, extraOf(attachment, NEW_ATTACHMENT)),
        ).andThen((more) =>
          call(
            "create_attachment",
            {
              tenant: organizationId,
              name: attachment.name,
              mime_type: attachment.mimeType,
              size: attachment.size,
              subject_type: subject?.type,
              subject_id: subject?.id,
              metadata: attachment.metadata,
              width: attachment.width,
              height: attachment.height,
              pages: attachment.pages,
              ...more,
            },
            (value) => value,
          ),
        ),
      )
      .andThen(typed);

  const upload = (
    subject: RecordRef | null,
    attachment: NewAttachment,
  ): AsyncResult<AttachmentUpload<F>> =>
    create(subject, attachment).andThen(async (created) => {
      const url = await stored(
        bucket(created).createSignedUploadUrl(created.path),
      );

      if (!url.ok) {
        return discard(created, url.error);
      }

      return ok({
        attachment: created,
        signedUrl: url.data.signedUrl,
        token: url.data.token,
      });
    });

  const client: Attachments<F> = {
    upload,
    confirm,
    get: find,
    list: (subject) =>
      tenantOf(subject).andThen((organizationId) =>
        call(
          "list_attachments",
          {
            tenant: organizationId,
            subject_type: subject?.type,
            subject_id: subject?.id,
          },
          (value) =>
            recordsOf(value, "list_attachments").map(
              (raw) => [raw, attachmentOf(raw)] as const,
            ),
        ).andThen((rows) => allWithFields(fields, rows)),
      ),
    download: (id, download = {}) =>
      find(id).andThen((attachment) => {
        const { version } = download;

        const file =
          version === undefined || version === attachment.version
            ? AsyncResult.ok<FileVersion>(attachment)
            : versionOf(id, version);

        return file.andThen((chosen) => {
          const blocked = gate(chosen);

          if (blocked) {
            return Promise.resolve(err(blocked));
          }

          return stored(
            options.storage
              .from(chosen.bucket)
              .createSignedUrl(
                chosen.path,
                ttl,
                download.as === undefined
                  ? undefined
                  : { download: download.as },
              ),
          ).map((url) => ({ attachment, signedUrl: url.signedUrl }));
        });
      }),
    replace: (id, file) =>
      call(
        "replace_attachment",
        {
          id,
          name: file.name,
          mime_type: file.mimeType,
          size: file.size,
          width: file.width,
          height: file.height,
          pages: file.pages,
        },
        (value) => value,
      )
        .andThen(typed)
        .andThen((replaced) =>
          stored(bucket(replaced).createSignedUploadUrl(replaced.path)).map(
            (url) => ({
              attachment: replaced,
              signedUrl: url.signedUrl,
              token: url.token,
            }),
          ),
        ),
    versions: listVersions,
    publicUrl: (attachment, url = {}) =>
      publicUrl(attachment, url.as === undefined ? {} : { download: url.as }),
    restore: (id, version) =>
      call(
        "restore_attachment_version",
        { id, version },
        (value) => value,
      ).andThen(typed),
    images: <V extends string = never>(
      // SAFETY: without variants V is never, so the empty record has every key.
      variants = {} as Readonly<Record<V, TransformOptions>>,
    ): AttachmentImages<V> => ({
      bucket: { id: "attachments", public: false, variants },
      publicUrl: (target, url = {}) => {
        if (typeof target === "string") {
          return err(
            dbError("invalid_request", "A public URL needs the attachment", {
              hint: "ATTACHMENT_PRIVATE",
            }),
          );
        }

        let transform: TransformOptions | undefined;

        try {
          transform = transformFor("attachments", variants, url.transform);
        } catch (cause) {
          return err(toDbError(cause));
        }

        return publicUrl(target, transform === undefined ? {} : { transform });
      },
      signedUrl: (target, url = {}) =>
        (typeof target === "string"
          ? find(target)
          : AsyncResult.ok<Attachment>(target)
        ).andThen((attachment) => {
          const blocked =
            gate(attachment) ??
            (attachment.mimeType.startsWith("image/")
              ? undefined
              : dbError("invalid_request", "The file is not an image", {
                  hint: "ATTACHMENT_NOT_IMAGE",
                }));

          if (blocked) {
            return Promise.resolve(err(blocked));
          }

          let transform: TransformOptions | undefined;

          try {
            transform = transformFor("attachments", variants, url.transform);
          } catch (cause) {
            return Promise.resolve(err(toDbError(cause)));
          }

          return stored(
            bucket(attachment).createSignedUrl(
              attachment.path,
              url.ttl === undefined ? ttl : ttlSeconds(url.ttl),
              transform === undefined ? undefined : { transform },
            ),
          ).map((signed) => signed.signedUrl);
        }),
    }),
    put: (subject, attachment, file) =>
      create(subject, attachment).andThen(async (created) => {
        const target = bucket(created);

        if (!target.upload) {
          return discard(
            created,
            dbError("invalid_request", "The storage client has no upload", {
              hint: "ATTACHMENT_STORAGE_CLIENT",
            }),
          );
        }

        const sent = await stored(
          target.upload(created.path, file, {
            contentType: created.mimeType,
            upsert: false,
          }),
        );

        if (!sent.ok) {
          return discard(created, sent.error);
        }

        return confirmed(created.id);
      }),
    read: (id) =>
      find(id).andThen((attachment) => {
        const blocked = gate(attachment);

        if (blocked) {
          return Promise.resolve(err(blocked));
        }

        return stored(bucket(attachment).download(attachment.path)).map(
          (file) => ({ attachment, file }),
        );
      }),
    remove: (id) =>
      find(id)
        .andThen((attachment) =>
          listVersions(id).andThen((earlier) =>
            stored(
              bucket(attachment).remove([
                attachment.path,
                ...earlier.map((version) => version.path),
              ]),
            ),
          ),
        )
        .andThen(() =>
          call("delete_attachment", { id }, (value) => value === true),
        ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "attachments",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}

/** A scanner's verdict on one file. */
export interface ScanVerdict {
  readonly status: "clean" | "infected";
  /** Stored as `scan_detail`, such as the matched signature. */
  readonly detail?: string;
}

export interface AttachmentScannerOptions extends BlockTemporalOptions {
  /**
   * A service-role transport: `set_attachment_status()` is granted to
   * `service_role` only.
   */
  readonly transport: BlockTransport;
  /** A service-role `supabase.storage`, to read pending files. */
  readonly storage: AttachmentStorage;
  readonly schema?: string;
  /**
   * Scans the file (ClamAV, a scanning API). A throw records `failed` and
   * rethrows.
   */
  readonly scan: (
    file: Blob,
    attachment: Attachment,
    signal?: AbortSignal,
  ) => ScanVerdict | Promise<ScanVerdict>;
  /** The outbox `typePrefix`. Default `dev.better-supabase`. */
  readonly typePrefix?: string;
}

/** The payload `job` expects. */
export interface AttachmentScanJob {
  readonly attachmentId: string;
}

export interface AttachmentScanner {
  /** Scans one uploaded file and records the verdict. */
  scan(id: string, signal?: AbortSignal): AsyncResult<Attachment>;
  /**
   * A jobs handler: `queue.work('attachment-scans', scanner.job)`. A deleted
   * attachment completes the job; other errors throw so the queue retries.
   */
  readonly job: JobHandler<AttachmentScanJob>;
  /**
   * An outbox sink that scans each `attachment.uploaded` event's file. An event
   * for a deleted attachment is skipped, so it never holds up the events behind
   * it; other errors throw so the relay retries the batch.
   */
  sink(): EventSink;
}

/**
 * Scans uploaded files with the app's `scan` function and records `clean`,
 * `infected` or `failed`. A file already clean or infected is not scanned
 * again, so replayed events and retried jobs are safe.
 */
export function createAttachmentScanner(
  options: AttachmentScannerOptions,
): AttachmentScanner {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema);
  const prefix = `${options.typePrefix ?? "dev.better-supabase"}.`;

  const record = (
    id: string,
    status: "clean" | "infected" | "failed",
    detail: string | undefined,
  ): AsyncResult<Attachment> =>
    call(
      "set_attachment_status",
      { id, status, detail },
      (value) => value,
    ).andThen((value) =>
      Promise.resolve(
        isRecord(value) ? ok(attachmentOf(value)) : err(notFound()),
      ),
    );

  const scan = (id: string, signal?: AbortSignal): AsyncResult<Attachment> =>
    lookup(call, id).andThen((attachment) => {
      if (attachment.status === "clean" || attachment.status === "infected") {
        return Promise.resolve(ok(attachment));
      }

      if (attachment.uploadedAt === undefined) {
        return Promise.resolve(
          err(
            dbError("invalid_request", "The file was not uploaded yet", {
              hint: "ATTACHMENT_NOT_UPLOADED",
            }),
          ),
        );
      }

      return stored(
        options.storage.from(attachment.bucket).download(attachment.path),
      ).andThen(async (file) => {
        let verdict: ScanVerdict;

        try {
          verdict = await options.scan(file, attachment, signal);
        } catch (cause) {
          const failed = await record(id, "failed", errorText(cause));

          return failed.ok
            ? err(
                dbError("raised", `The scan failed: ${errorText(cause)}`, {
                  hint: "ATTACHMENT_SCAN_FAILED",
                }),
              )
            : failed;
        }

        return record(id, verdict.status, verdict.detail);
      });
    });

  return {
    scan,
    job: async (payload, _job, signal) => {
      await settle(scan(payload.attachmentId, signal), attachmentGone);
    },
    sink: () => ({
      async send(events) {
        for (const event of events) {
          const type = event.type.startsWith(prefix)
            ? event.type.slice(prefix.length)
            : event.type;

          if (type !== "attachment.uploaded" || !isRecord(event.data)) {
            continue;
          }

          const id = optionalText(event.data["attachmentId"]);

          if (id !== undefined) {
            await settle(scan(id), attachmentGone);
          }
        }
      },
    }),
  };
}

/** A scanned object in any bucket (`scanned_objects`). */
export interface ScannedObject {
  readonly bucket: string;
  readonly path: string;
  readonly status: AttachmentStatus;
  readonly detail: string | undefined;
  readonly scannedAt: Temporal.Instant | undefined;
}

export interface ObjectScannerOptions extends BlockTemporalOptions {
  /**
   * A service-role transport: `set_object_scan()` is granted to `service_role`
   * only.
   */
  readonly transport: BlockTransport;
  /** A service-role `supabase.storage`, to read the objects. */
  readonly storage: AttachmentStorage;
  readonly schema?: string;
  /** Scans the file. A throw records `failed` and rethrows. */
  readonly scan: (
    file: Blob,
    object: { readonly bucket: string; readonly path: string },
    signal?: AbortSignal,
  ) => ScanVerdict | Promise<ScanVerdict>;
  /** The outbox `typePrefix`. Default `dev.better-supabase`. */
  readonly typePrefix?: string;
}

/** The payload `ObjectScanner.job` expects. */
export interface ObjectScanJob {
  readonly bucket: string;
  readonly path: string;
}

export interface ObjectScanner {
  /**
   * Scans one object and records the verdict; a clean or infected object is not
   * scanned again.
   */
  scan(
    bucket: string,
    path: string,
    signal?: AbortSignal,
  ): AsyncResult<ScannedObject>;
  /**
   * A jobs handler: `queue.work('object-scans', scanner.job)`. An object
   * deleted from storage completes the job; other errors throw.
   */
  readonly job: JobHandler<ObjectScanJob>;
  /**
   * An outbox sink that scans each `object.uploaded` event's object. An event
   * for an object deleted from storage is skipped; other errors throw so the
   * relay retries the batch.
   */
  sink(): EventSink;
}

function scannedOf(value: unknown): ScannedObject {
  const row = recordOf(value, "scanned_objects");
  const status = textOf(row["status"]);

  return {
    bucket: textOf(row["bucket"]),
    path: textOf(row["object_path"]),
    status:
      status === "clean" || status === "infected" || status === "failed"
        ? status
        : "pending",
    detail: optionalText(row["scan_detail"]),
    scannedAt: optionalInstant(row["scanned_at"]),
  };
}

/**
 * The scan gate for objects outside the attachments table, such as a file drive
 * or avatars: scans an object with the app's `scan` function and records the
 * verdict in `scanned_objects`, which storage policies read with
 * `object_clean(bucket_id, name)`. With `options.scanBuckets`, new objects in
 * those buckets get a pending row and an `object.uploaded` event.
 */
export function createObjectScanner(
  options: ObjectScannerOptions,
): ObjectScanner {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema);
  const prefix = `${options.typePrefix ?? "dev.better-supabase"}.`;

  const record = (
    bucket: string,
    path: string,
    status: AttachmentStatus,
    detail: string | undefined,
  ): AsyncResult<ScannedObject> =>
    call("set_object_scan", { bucket, path, status, detail }, scannedOf);

  const scan = (
    bucket: string,
    path: string,
    signal?: AbortSignal,
  ): AsyncResult<ScannedObject> =>
    call("object_scan", { bucket, path }, (value) =>
      isRecord(value) ? scannedOf(value) : undefined,
    ).andThen((current) => {
      if (current?.status === "clean" || current?.status === "infected") {
        return Promise.resolve(ok(current));
      }

      return stored(options.storage.from(bucket).download(path)).andThen(
        async (file) => {
          let verdict: ScanVerdict;

          try {
            verdict = await options.scan(file, { bucket, path }, signal);
          } catch (cause) {
            const failed = await record(
              bucket,
              path,
              "failed",
              errorText(cause),
            );

            return failed.ok
              ? err(
                  dbError("raised", `The scan failed: ${errorText(cause)}`, {
                    hint: "ATTACHMENT_SCAN_FAILED",
                  }),
                )
              : failed;
          }

          return record(bucket, path, verdict.status, verdict.detail);
        },
      );
    });

  return {
    scan,
    job: async (payload, _job, signal) => {
      await settle(scan(payload.bucket, payload.path, signal), objectGone);
    },
    sink: () => ({
      async send(events) {
        for (const event of events) {
          const type = event.type.startsWith(prefix)
            ? event.type.slice(prefix.length)
            : event.type;

          if (type !== "object.uploaded" || !isRecord(event.data)) {
            continue;
          }

          const bucket = optionalText(event.data["bucket"]);
          const path = optionalText(event.data["path"]);

          if (bucket !== undefined && path !== undefined) {
            await settle(scan(bucket, path), objectGone);
          }
        }
      },
    }),
  };
}
