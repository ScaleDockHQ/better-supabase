import type { Section } from "../sections.ts";
import type { Donations, GivingSummary } from "./donations.ts";

import { defineSection } from "../sections.ts";

/** A donor's giving this year, such as a contact's: totals, funds and receipts. */
export const givingSection: Section<Donations, GivingSummary> = defineSection({
  permissions: { read: "read", write: "manage" },
  module: "donations",
  load: (client: Donations, subject) => client.givingSummary(subject),
  events: ["donation.*", "donation_receipt.*"],
});
