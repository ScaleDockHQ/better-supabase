import type { RecordBinding } from "../record-bindings.ts";
import type { Invoice, Invoices } from "./invoices.ts";

import { defineRecordBinding } from "../record-bindings.ts";

/**
 * The invoices of a record, such as a company's, newest first: the subject is
 * the company or contact the invoices name (`{ type: "company", id }`). It
 * reads through `invoices.list`, which takes the organization from the block's
 * `tenant` option. Invoice writes carry money and dates, so the binding has
 * none.
 */
export const invoicesBinding: RecordBinding<Invoices, readonly Invoice[]> =
  defineRecordBinding({
    permissions: { read: "read" },
    module: "invoices",
    load: (client: Invoices, subject) => client.list({ subject }),
    events: ["invoice.*"],
  });
