import type { RecordBinding } from "../record-bindings.ts";
import type { Lease, Leases } from "./leases.ts";

import { defineRecordBinding } from "../record-bindings.ts";

/** A party's leases, such as a contact's, with rent due and deposits held. */
export const leasesBinding: RecordBinding<Leases, readonly Lease[]> =
  defineRecordBinding({
    permissions: { read: "read", write: "manage" },
    module: "leases",
    load: (client: Leases, subject) => client.list({ party: subject }),
    events: ["lease.*"],
  });
