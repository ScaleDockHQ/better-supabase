import type { EInvoiceParty } from "better-supabase/e-invoicing";

import { toUbl } from "better-supabase/e-invoicing";

import { bsb } from "../../../../../lib/supabase/server";

/** The example's own company; an app reads it from its organization settings. */
const SELLER: EInvoiceParty = {
  name: "Example B.V.",
  endpoint: { scheme: "0106", id: "12345678" },
  address: {
    street: "Main 1",
    city: "Utrecht",
    postalCode: "3511 AA",
    country: "NL",
  },
  vatId: "NL123456789B01",
};

/**
 * `POST
 * /api/invoices/:id/ubl?scheme=0208&endpoint=0123456789&name=Buyer&country=BE`:
 * issues a draft and returns it as a Peppol BIS Billing 3.0 UBL document, for
 * the app's access point to send.
 */
export const POST = bsb.route<{ id: string }, true>(
  async (request, { db, params }) => {
    const query = new URL(request.url).searchParams;
    const endpoint = query.get("endpoint");

    if (endpoint === null) {
      return Response.json(
        { error: "Pass the buyer's Peppol endpoint" },
        { status: 400 },
      );
    }

    const invoice = await db.invoices.issue({ invoiceId: params.id });

    if (!invoice.ok) {
      return invoice;
    }

    const document = toUbl(invoice.data, {
      seller: SELLER,
      buyer: {
        name: query.get("name") ?? invoice.data.title,
        endpoint: { scheme: query.get("scheme") ?? "0088", id: endpoint },
        address: { country: query.get("country") ?? "NL" },
      },
    });

    return new Response(document.xml, {
      headers: {
        "content-type": "application/xml",
        "content-disposition": `attachment; filename="${document.id}.xml"`,
        "cache-control": "no-store",
      },
    });
  },
  { requireTenant: true, permission: "invoices.write" },
);
