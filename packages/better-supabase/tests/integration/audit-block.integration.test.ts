import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { exportAuditLog } from "../../src/blocks/audit/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

async function lines(stream: ReadableStream<Uint8Array>) {
  const text = await new Response(stream).text();
  return text
    .trim()
    .split("\n")
    .filter(Boolean)
    .map((line) => JSON.parse(line) as Record<string, unknown>);
}

describe.skipIf(!live)("audit block", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("exports one tenant's entries as NDJSON and OCSF, in pages", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "audit"], {
        modules: { audit: { options: { readPolicy: true } } },
      });
      const owner = await s.user("owner");
      const organization = await s.organization(owner);
      const other = await s.organization(await s.user("other"));
      await s.service();
      for (const [type, tenant] of [
        ["deal.created", organization],
        ["deal.deleted", organization],
        ["api_key.revoked", organization],
        ["deal.created", other],
      ] as const) {
        await s.client.query(
          "select better_supabase.audit_event($1, outcome => 'success', record_id => 'r1', tenant => $2)",
          [type, tenant],
        );
      }

      const ndjson = await lines(
        exportAuditLog(s.sql, { organizationId: organization, batch: 2 }),
      );
      expect(
        ndjson
          .filter((entry) => entry["op"] === "event")
          .map((entry) => entry["eventType"]),
      ).toEqual(["deal.created", "deal.deleted", "api_key.revoked"]);
      expect(new Set(ndjson.map((entry) => entry["organizationId"]))).toEqual(
        new Set([organization]),
      );

      const ocsf = await lines(
        exportAuditLog(s.sql, {
          organizationId: organization,
          format: "ocsf",
          product: { name: "Acme" },
        }),
      );
      expect(
        ocsf
          .filter((event) => event["class_uid"] === 6003)
          .map((event) => event["type_uid"]),
      ).toEqual([600301, 600304, 600304]);

      // With the read policy, a member reads only their own tenant.
      await s.asRole(owner);
      expect(
        await lines(exportAuditLog(s.sql, { organizationId: other })),
      ).toEqual([]);
    } finally {
      await s.close();
    }
  });
});
