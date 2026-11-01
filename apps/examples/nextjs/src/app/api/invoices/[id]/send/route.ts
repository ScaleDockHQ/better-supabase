import type { EInvoiceChannel } from "better-supabase/e-invoicing";

import {
  eInvoiceChannelOf,
  peppolBis3Format,
} from "better-supabase/e-invoicing";

import { bsb } from "../../../../../lib/supabase/server";

/**
 * A stand-in for the app's access point: it accepts every document. Replace
 * `send` with a `fetch` call to the access point and add `lookup`, `status` and
 * `receive` when it supports them.
 */
const accessPoint: EInvoiceChannel = eInvoiceChannelOf({
  apiVersion: 1,
  key: "example",
  send: () => Promise.resolve({ messageId: crypto.randomUUID() }),
});

const format = peppolBis3Format({
  parties: (invoice, { endpoints }) => ({
    seller: {
      name: "Example B.V.",
      endpoint: endpoints?.seller ?? { scheme: "0106", id: "12345678" },
      address: { city: "Utrecht", postalCode: "3511 AA", country: "NL" },
      vatId: "NL123456789B01",
    },
    buyer: {
      name: invoice.title,
      endpoint: endpoints?.buyer ?? { scheme: "0088", id: "0000000000000" },
      address: { country: "NL" },
    },
  }),
});

/**
 * `POST /api/invoices/:id/send`: issues a draft and sends it to its buyer's
 * participant id and logs the delivery. The buyer's company needs an id set
 * with `db.invoices.setEInvoiceEndpoint`.
 */
export const POST = bsb.route<{ id: string }, true>(
  async (_request, { db, params }) => {
    const invoice = await db.invoices.issue(params.id);

    if (!invoice.ok) {
      return invoice;
    }

    const sent = await db.invoices.sendEInvoice(invoice.data, {
      format,
      channel: accessPoint,
    });

    return sent.ok ? Response.json(sent.data.delivery) : sent;
  },
  { requireTenant: true, permission: "invoices.send" },
);
