import type { RecordBinding } from "../record-bindings.ts";
import type { Deal, Deals } from "./deals.ts";

import { defineRecordBinding } from "../record-bindings.ts";

/**
 * The deals of a record, such as a company's, newest first: the subject is the
 * company or contact the deals name (`{ type: "company", id }`). It reads
 * through `deals.list`, which takes the organization from the block's `tenant`
 * option. Deal writes carry money and dates, so the binding has none.
 */
export const dealsBinding: RecordBinding<Deals, readonly Deal[]> =
  defineRecordBinding({
    permissions: { read: "read" },
    module: "deals",
    load: (client: Deals, subject) => client.list({ subject }),
    events: ["deal.*"],
  });
