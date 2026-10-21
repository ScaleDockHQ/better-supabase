import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.attachments.options`. */
export type AttachmentsSqlOptions = {
  readonly bucket?: string;
  readonly requireScan?: boolean;
  readonly maxSize?: number;
  readonly allowedMimeTypes?: readonly string[];
  readonly subjects?: unknown;
  readonly path?: string;
  readonly scanBuckets?: readonly string[];
  readonly extraColumns?: unknown;
};

export const attachmentsSqlOptions: BlockOptionsSchema<AttachmentsSqlOptions> =
  blockOptions<AttachmentsSqlOptions>({
    bucket: option.string({ default: "attachments" }),
    requireScan: option.boolean({ default: true, client: true }),
    maxSize: option.number(),
    allowedMimeTypes: option.strings({ default: [] }),
    subjects: option.unknown(),
    path: option.string({ default: "{organization_id}/attachments/{id}" }),
    scanBuckets: option.strings({ default: [] }),
    extraColumns: option.unknown(),
  });
