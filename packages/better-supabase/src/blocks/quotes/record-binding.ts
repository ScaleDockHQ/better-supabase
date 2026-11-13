import type { RecordBinding } from "../record-bindings.ts";
import type { Quote, Quotes } from "./quotes.ts";

import { defineRecordBinding } from "../record-bindings.ts";

/**
 * The quotes of a record, such as a company's, newest first: the subject is the
 * company or contact the quotes name (`{ type: "company", id }`). It reads
 * through `quotes.list`, which takes the organization from the block's `tenant`
 * option. Quote writes carry money, lines and dates, so the binding has none.
 */
export const quotesBinding: RecordBinding<Quotes, readonly Quote[]> =
  defineRecordBinding({
    permissions: { read: "read" },
    module: "quotes",
    load: (client: Quotes, subject) => client.list({ subject }),
    events: ["quote.*"],
  });
