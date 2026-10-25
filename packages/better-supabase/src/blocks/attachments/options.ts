import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.attachments.options`. */
export type AttachmentsSqlOptions = {
  readonly bucket?: string;
  readonly requireScan?: boolean;
  readonly maxSize?: number;
  readonly allowedMimeTypes?: readonly string[];
  readonly path?: string;
  readonly scanBuckets?: readonly string[];
  readonly publicBuckets?: readonly string[];
  readonly offline?: boolean;
  readonly extraColumns?: unknown;
};

export const attachmentsSqlOptions: BlockOptionsSchema<AttachmentsSqlOptions> =
  blockOptions<AttachmentsSqlOptions>({
    bucket: option.string({ default: "attachments" }),
    // No default: it is true, or false with offline.
    requireScan: option.boolean({ client: true }),
    maxSize: option.number(),
    allowedMimeTypes: option.strings({ default: [] }),
    path: option.string({ default: "{organization_id}/attachments/{id}" }),
    scanBuckets: option.strings({ default: [] }),
    publicBuckets: option.strings({ default: [], client: true }),
    offline: option.boolean({ client: true }),
    extraColumns: option.unknown(),
  });
