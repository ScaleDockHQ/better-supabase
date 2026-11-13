import type { RecordBinding } from "../record-bindings.ts";
import type { Risk, Risks } from "./risks.ts";

import { defineRecordBinding } from "../record-bindings.ts";

/**
 * The open risks linked to a record, highest residual score first. A risk is
 * linked by a relation from the risk to the record, so it needs the relations
 * block. It reads through `risks.linkedTo`, which takes the organization from
 * the block's `tenant` option. Assessing or closing a risk takes a matrix and
 * levels, so the binding has no writes.
 */
export const risksBinding: RecordBinding<Risks, readonly Risk[]> =
  defineRecordBinding({
    permissions: { read: "read" },
    module: "risks",
    load: (client: Risks, subject) => client.linkedTo({ subject }),
    events: ["risk.*"],
  });
