import type { RecordBinding } from "../record-bindings.ts";
import type { FieldChange, FieldHistory } from "./field-history.ts";

import { defineRecordBinding } from "../record-bindings.ts";

/** A record's column changes, newest first. */
export const fieldHistoryBinding: RecordBinding<
  FieldHistory,
  FieldChange[],
  { readonly field?: string; readonly before?: string; readonly limit?: number }
> = defineRecordBinding({
  permissions: { read: "read" },
  module: "field-history",
  load: (
    client: FieldHistory,
    subject,
    options?: {
      readonly field?: string;
      readonly before?: string;
      readonly limit?: number;
    },
  ) => client.of({ subject, ...options }),
  timeline: (changes) =>
    changes.map((change) => ({
      id: change.id,
      kind: "field_change",
      at: change.changedAt,
      ...(change.changedBy === undefined ? {} : { actor: change.changedBy }),
      row: change,
    })),
});
