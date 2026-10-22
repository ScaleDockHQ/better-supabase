import type { ModuleContext } from "../context.ts";

export const BUCKET: RegExp = /^[a-z0-9][a-z0-9_.-]{0,99}$/;

export interface BucketOptions {
  readonly bucket: string;
  readonly maxSize: number;
  readonly mimeTypes: readonly string[];
}

export function bucketOptions(ctx: ModuleContext): BucketOptions {
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
