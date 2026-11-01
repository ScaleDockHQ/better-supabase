import type { RecordBinding } from "../record-bindings.ts";
import type { Donations, GivingSummary } from "./donations.ts";

import { defineRecordBinding } from "../record-bindings.ts";

/** A donor's giving this year, such as a contact's: totals, funds and receipts. */
export const givingBinding: RecordBinding<Donations, GivingSummary> =
  defineRecordBinding({
    permissions: { read: "read", write: "manage" },
    module: "donations",
    load: (client: Donations, subject) =>
      client.givingSummary({ donor: subject }),
    events: ["donation.*", "donation_receipt.*"],
  });
