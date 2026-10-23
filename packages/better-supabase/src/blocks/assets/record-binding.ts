import type { RecordBinding } from "../record-bindings.ts";
import type { Asset, Assets } from "./assets.ts";

import { defineRecordBinding } from "../record-bindings.ts";

/** The assets a record holds, such as a party's devices or vehicles. */
export const assetsBinding: RecordBinding<Assets, readonly Asset[]> =
  defineRecordBinding({
    permissions: { read: "read", write: "assign" },
    module: "assets",
    load: (client: Assets, subject) => client.assignedTo(subject),
    events: ["asset.*"],
  });
