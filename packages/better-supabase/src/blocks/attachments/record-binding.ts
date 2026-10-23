import type {
  RecordBinding,
  RecordRowInput,
  RecordBindingWrite,
} from "../record-bindings.ts";
import type { Attachment, Attachments } from "./attachments.ts";

import { defineRecordBinding, recordRowInput } from "../record-bindings.ts";

/** A pending write to a record's files, for `useOptimistic`. */
export type AttachmentsOptimisticAction =
  | { readonly type: "add"; readonly attachment: Attachment }
  | { readonly type: "update"; readonly attachment: Attachment }
  | { readonly type: "remove"; readonly id: string };

/**
 * The files with a pending write applied: `add` puts the attachment first (or
 * replaces the one with the same id), `update` swaps the one with the same id
 * where it is (a new version from `replace` or `restore`), `remove` takes it
 * out.
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

    case "update": {
      return state.map((attachment) =>
        attachment.id === action.attachment.id ? action.attachment : attachment,
      );
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

/**
 * The writes of the attachments binding. An upload takes two steps through the
 * browser (`upload`, then `confirm`), so it isn't one.
 */
export type AttachmentsWrites = {
  /** Removes one file. */
  readonly remove: RecordBindingWrite<Attachments, RecordRowInput, boolean>;
};

/** A record's files. */
export const attachmentsBinding: RecordBinding<
  Attachments,
  readonly Attachment[],
  never,
  AttachmentsOptimisticAction,
  AttachmentsWrites
> = defineRecordBinding({
  permissions: { read: "read", write: "upload" },
  load: (client: Attachments, subject) => client.list(subject),
  timeline: (attachments) =>
    attachments.map((attachment) => ({
      id: attachment.id,
      kind: "attachment",
      at: attachment.uploadedAt ?? attachment.createdAt,
      ...(attachment.uploadedBy === undefined
        ? {}
        : { actor: attachment.uploadedBy }),
      row: attachment,
    })),
  events: ["attachment.*"],
  optimistic: attachmentsOptimistic,
  writes: {
    remove: {
      permission: "manage",
      input: recordRowInput,
      run: (client: Attachments, _subject, { id }: RecordRowInput) =>
        client.remove(id),
    },
  },
});
