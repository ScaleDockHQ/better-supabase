import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import {
  createAuditLog,
  exportAuditLog,
} from "../../src/blocks/audit/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
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

  it("lists, reveals and exports through list_audit_events as the caller", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "audit"], {
        modules: {
          audit: { options: { readPolicy: true, restricted: true } },
        },
      });
      const owner = await s.user("owner");
      const outsider = await s.user("outsider");
      const organization = await s.organization(owner);
      await s.service();
      for (const [type, summary] of [
        ["invoice.sent", "=SUM(1)"],
        ["invoice.paid", "Paid, in full"],
        ["member.added", "Added"],
      ] as const) {
        await s.client.query(
          `select better_supabase.audit_event($1, record_id => 'r1', tenant => $2, summary => $3,
             restricted => '{"card": "4242"}')`,
          [type, organization, summary],
        );
      }
      const audit = createAuditLog({ transport: sqlTransport(s.sql) });

      await s.asRole(owner);
      const first = await audit
        .list({ organizationId: organization, limit: 2 })
        .orThrow();
      expect(first.entries.map((entry) => entry.eventType)).toEqual([
        "member.added",
        "invoice.paid",
      ]);
      expect(first.entries[0]).toMatchObject({
        tenant: organization,
        record: "r1",
        summary: "Added",
      });
      const second = await audit
        .list({ organizationId: organization, limit: 2, before: first.next })
        .orThrow();
      expect(second.entries.map((entry) => entry.eventType)).toEqual([
        "invoice.sent",
      ]);
      expect(second.next).toBeUndefined();

      const details = await audit.reveal(first.entries[0]!.id).orThrow();
      expect(details.entry).toBe(first.entries[0]!.id);
      expect(details.metadata ?? details.changes).toBeDefined();

      const csv = await new Response(
        audit.export({ organizationId: organization, format: "csv", batch: 2 }),
      ).text();
      const rows = csv.trim().split("\r\n");
      // The three events and the audit.revealed entry the reveal wrote.
      expect(rows).toHaveLength(5);
      expect(rows[0]!.startsWith("id,occurredAt,op,eventType")).toBe(true);
      expect(csv).toContain(`'=SUM(1)`);
      expect(csv).toContain(`"Paid, in full"`);

      const ocsf = (
        await new Response(
          audit.export({
            organizationId: organization,
            format: "ocsf",
            product: { name: "Example" },
          }),
        ).text()
      )
        .trim()
        .split("\n")
        .map((line) => JSON.parse(line) as Record<string, unknown>);
      expect(ocsf.map((event) => event["class_uid"])).toEqual([
        6003, 6003, 6003, 6003,
      ]);

      const stored = new Map<string, string>();
      const target = await audit
        .exportToStorage({
          organizationId: organization,
          storage: {
            from: () => ({
              upload: async (path, body) => {
                stored.set(path, await body.text());
                return { data: { path }, error: null };
              },
              createSignedUrl: async (path) => ({
                data: { signedUrl: `https://storage.test/${path}` },
                error: null,
              }),
            }),
          },
          bucket: "exports",
          path: `${organization}/audit.ndjson`,
          signedUrlTtl: 60,
        })
        .orThrow();
      expect(target.url).toBe(
        `https://storage.test/${organization}/audit.ndjson`,
      );
      expect(stored.get(target.path)!.trim().split("\n")).toHaveLength(4);

      await s.asRole(outsider);
      expect(
        (await audit.list({ organizationId: organization }).orThrow()).entries,
      ).toEqual([]);
      const hidden = await audit.reveal(first.entries[0]!.id);
      expect(hidden.ok ? undefined : hidden.error).toMatchObject({
        kind: "not_found",
        hint: "AUDIT_ENTRY_NOT_FOUND",
      });
    } finally {
      await s.close();
    }
  });
});
