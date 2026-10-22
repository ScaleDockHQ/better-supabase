import type { Section } from "../sections.ts";
import type { Contract, Contracts } from "./contracts.ts";

import { defineSection } from "../sections.ts";

/** The contracts with a record, such as a party's, on its record page. */
export const contractsSection: Section<Contracts, readonly Contract[]> =
  defineSection({
    permissions: { read: "read", write: "write" },
    module: "contracts",
    load: (client: Contracts, subject) => client.forCounterparty(subject),
    events: ["contract.*"],
  });
