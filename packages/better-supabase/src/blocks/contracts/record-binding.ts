import type { RecordBinding } from "../record-bindings.ts";
import type { Contract, Contracts } from "./contracts.ts";

import { defineRecordBinding } from "../record-bindings.ts";

/** The contracts with a record, such as a party's, on its record page. */
export const contractsBinding: RecordBinding<Contracts, readonly Contract[]> =
  defineRecordBinding({
    permissions: { read: "read", write: "write" },
    module: "contracts",
    load: (client: Contracts, subject) => client.forCounterparty(subject),
    events: ["contract.*"],
  });
