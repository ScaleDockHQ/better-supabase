import type { RecordBinding } from "../record-bindings.ts";
import type { Score, Scores } from "./scores.ts";

import { defineRecordBinding } from "../record-bindings.ts";

/** A record's current scores, such as a lead score or account health. */
export const scoresBinding: RecordBinding<Scores, readonly Score[]> =
  defineRecordBinding({
    permissions: { read: "read", write: "compute" },
    module: "scores",
    load: (client: Scores, subject) => client.list({ on: subject }),
    events: ["score.changed"],
  });
