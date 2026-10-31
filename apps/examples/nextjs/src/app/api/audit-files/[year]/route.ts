import { exportAuditFile, saftAdapter } from "better-supabase/audit-files";

import { bsb } from "../../../../lib/supabase/server";

/** The example's own company; an app reads it from its organization settings. */
const COMPANY = { name: "Example B.V.", registrationNumber: "12345678" };

/**
 * `GET /api/audit-files/2026`: exports the fiscal year of the general ledger as
 * a SAF-T file. Warnings name what the file could not carry.
 */
export const GET = bsb.route<{ year: string }, true>(
  async (_request, { db, params, tenant }) => {
    const { xml, warnings } = await exportAuditFile(
      saftAdapter({}),
      db.accounting,
      {
        organizationId: tenant,
        company: COMPANY,
        currency: "EUR",
        selection: { year: Number(params.year) },
      },
    );

    return new Response(xml, {
      headers: {
        "content-type": "application/xml",
        "content-disposition": `attachment; filename="saft-${params.year}.xml"`,
        "x-audit-warnings": String(warnings.length),
        "cache-control": "no-store",
      },
    });
  },
  { requireTenant: true, permission: "accounting.read" },
);
