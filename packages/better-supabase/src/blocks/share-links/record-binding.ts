import type { EntitySchema } from "../entity-schema.ts";
import type {
  RecordBinding,
  RecordRowInput,
  RecordBindingWrite,
} from "../record-bindings.ts";
import type { CreatedShareLink, ShareLink, ShareLinks } from "./share-links.ts";

import { toInstant } from "../../core/block-helpers.ts";
import { entitySchema } from "../entity-schema.ts";
import { defineRecordBinding, recordRowInput } from "../record-bindings.ts";

/**
 * What creating a share link from a record page takes. `expiresAt` is an ISO
 * 8601 string, because a Server Action argument can't be a `Temporal.Instant`.
 */
export interface ShareLinkInput {
  readonly role?: string;
  readonly expiresAt?: string;
  readonly maxUses?: number;
}

/** The input schema of the share links binding's `create`. */
export const shareLinkInput: EntitySchema<ShareLinkInput> =
  entitySchema<ShareLinkInput>({
    title: "ShareLinkInput",
    fields: {
      role: { kind: "string", optional: true, minLength: 1 },
      expiresAt: { kind: "datetime", optional: true },
      maxUses: { kind: "integer", optional: true, minimum: 1 },
    },
  });

/** The writes of the share links binding. */
export type ShareLinksWrites = {
  /** A new link to the record; its token is in the result, once. */
  readonly create: RecordBindingWrite<
    ShareLinks,
    ShareLinkInput,
    CreatedShareLink
  >;
  /** Revokes one link; its creator or a member with `share_links.create`. */
  readonly revoke: RecordBindingWrite<ShareLinks, RecordRowInput, boolean>;
};

/** The share links to a record the caller created or may read. */
export const shareLinksBinding: RecordBinding<
  ShareLinks,
  readonly ShareLink[],
  never,
  never,
  ShareLinksWrites
> = defineRecordBinding({
  permissions: { read: "read", write: "create" },
  module: "share-links",
  load: (client: ShareLinks, subject) => client.list(subject),
  events: ["share_link.*"],
  writes: {
    create: {
      input: shareLinkInput,
      run: (client: ShareLinks, subject, input: ShareLinkInput) =>
        client.create(subject, {
          ...(input.role === undefined ? {} : { role: input.role }),
          ...(input.maxUses === undefined ? {} : { maxUses: input.maxUses }),
          ...(input.expiresAt === undefined
            ? {}
            : { expiresAt: toInstant(input.expiresAt) }),
        }),
    },
    revoke: {
      input: recordRowInput,
      run: (client: ShareLinks, _subject, { id }: RecordRowInput) =>
        client.revoke(id),
    },
  },
});
