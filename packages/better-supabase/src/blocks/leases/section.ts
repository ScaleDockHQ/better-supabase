import type { Section } from "../sections.ts";
import type { Lease, Leases } from "./leases.ts";

import { defineSection } from "../sections.ts";

/** A party's leases, such as a contact's, with rent due and deposits held. */
export const leasesSection: Section<Leases, readonly Lease[]> = defineSection({
  permissions: { read: "read", write: "manage" },
  module: "leases",
  load: (client: Leases, subject) => client.list({ party: subject }),
  events: ["lease.*"],
});
