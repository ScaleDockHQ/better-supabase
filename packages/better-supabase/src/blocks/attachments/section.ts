import type { Section } from "../sections.ts";
import type { Attachment, Attachments } from "./attachments.ts";

import { defineSection } from "../sections.ts";

/** A pending write to a record's files, for `useOptimistic`. */
export type AttachmentsOptimisticAction =
  | { readonly type: "add"; readonly attachment: Attachment }
  | { readonly type: "remove"; readonly id: string };

/**
 * The files with a pending write applied: `add` puts the attachment first (or
 * replaces the one with the same id), `remove` takes it out.
 */
export function attachmentsOptimistic(
  state: readonly Attachment[],
  action: AttachmentsOptimisticAction,
): readonly Attachment[] {
  switch (action.type) {
    case "add": {
      return [
        action.attachment,
        ...state.filter((attachment) => attachment.id !== action.attachment.id),
      ];
    }

    case "remove": {
      return state.filter((attachment) => attachment.id !== action.id);
    }

    default: {
      const never: never = action;

      return never;
    }
  }
}

/** A record's files. */
export const attachmentsSection: Section<
  Attachments,
  readonly Attachment[],
  never,
  AttachmentsOptimisticAction
> = defineSection({
  permissions: { read: "read", write: "upload" },
  load: (client: Attachments, subject) => client.list(subject),
  events: ["attachment.*"],
  optimistic: attachmentsOptimistic,
});
