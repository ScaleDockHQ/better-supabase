import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";

export const BUCKET: RegExp = /^[a-z0-9][a-z0-9_.-]{0,99}$/;

export interface BucketOptions {
  readonly bucket: string;
  readonly maxSize: number;
  readonly mimeTypes: readonly string[];
}

export function bucketOptions(ctx: BlockSqlContext): BucketOptions {
  const bucket = ctx.text("bucket", "attachments");

  if (!BUCKET.test(bucket)) {
    throw new TypeError(
      "blocks.attachments.options.bucket must be 1 to 100 lowercase letters, digits, dots, dashes or underscores",
    );
  }

  const maxSize = ctx.number("maxSize", 50 * 1024 * 1024);

  if (!Number.isInteger(maxSize) || maxSize < 1) {
    throw new TypeError(
      "blocks.attachments.options.maxSize must be a whole number of bytes above zero",
    );
  }

  return { bucket, maxSize, mimeTypes: ctx.list("allowedMimeTypes", []) };
}

/**
 * `options.publicBuckets`: the module's buckets Storage serves without a signed
 * URL. Their files are readable once uploaded, so they need `requireScan:
 * false`.
 */
export function publicBucketsOf(
  ctx: BlockSqlContext,
  buckets: readonly string[],
): ReadonlySet<string> {
  const listed = ctx.list("publicBuckets", []);

  for (const id of listed) {
    if (!buckets.includes(id)) {
      throw new TypeError(
        `blocks.attachments.options.publicBuckets: "${id}" is not one of the attachment buckets (${buckets.join(", ")})`,
      );
    }
  }

  if (listed.length > 0 && ctx.flag("requireScan", true)) {
    throw new TypeError(
      "blocks.attachments.options.publicBuckets needs requireScan: false: a public bucket serves a file before any scan",
    );
  }

  return new Set(listed);
}

/** The `storage.buckets` rows for each bucket id and its allowed MIME types. */
export function bucketInsert(
  ctx: BlockSqlContext,
  rows: ReadonlyMap<string, readonly string[]>,
  maxSize: number,
): string {
  const open = publicBucketsOf(ctx, [...rows.keys()]);

  const values = [...rows].map(([id, types]) => {
    const mimeArray =
      types.length === 0
        ? "null"
        : `array[${types.map(sqlString).join(", ")}]::text[]`;

    return `(${sqlString(id)}, ${sqlString(id)}, ${String(open.has(id))}, ${String(maxSize)}, ${mimeArray})`;
  });

  // options.publicBuckets sets public on every run; the rest stays as set.
  return `insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ${values.join(",\n  ")}
on conflict (id) do update set public = excluded.public;`;
}
