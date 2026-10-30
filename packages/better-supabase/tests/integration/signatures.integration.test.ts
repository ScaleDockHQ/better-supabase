import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import {
  createSignatures,
  sqlTransport,
} from "../../src/blocks/signatures/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const TABLES = `create schema signatures_it;
create table signatures_it.contracts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  body text not null
);`;

const MODULES = [
  "organizations",
  "outbox",
  "versions",
  "approvals",
  "signatures",
];

const layoutFor = (signer: string): BlockSqlLayout => ({
  subjects: { contract: { table: "signatures_it.contracts", idType: "uuid" } },
  modules: {
    versions: { on: { contract: { columns: ["body"] } } },
    approvals: {
      options: {
        policies: {
          contract: { sign: { steps: [{ approvers: { users: [signer] } }] } },
        },
      },
    },
  },
});

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("signatures", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("signs a frozen version in order, decides the approval step and detects edits", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const ada = await s.user("ada");
      const bob = await s.user("bob");
      const stranger = await s.user("stranger");
      await s.client.query(TABLES);
      await s.install(MODULES, layoutFor(ada.id));
      const tenant = await s.organization(owner, { member: ada, member2: bob });

      const rows = await s.rows<{ id: string }>(
        "insert into signatures_it.contracts (organization_id, body) values ($1, 'Terms v1') returning id",
        [tenant],
      );

      const contract = rows[0]!.id;
      const signatures = createSignatures({ transport: sqlTransport(s.sql) });

      const subject = {
        organizationId: tenant,
        subjectType: "contract",
        subjectId: contract,
      };

      await s.as(owner);

      const approval = await s.value<{ id: string }>(
        "better_supabase.request_approval($1, 'contract', $2, 'sign')",
        [tenant, contract],
      );

      expect(
        await signatures
          .request({ ...subject, signers: [ada.id, stranger.id] })
          .then(hint),
      ).toBe("SIGNATURE_SIGNERS_INVALID");
      expect(
        await signatures
          .request({ ...subject, signers: [ada.id, ada.id] })
          .then(hint),
      ).toBe("SIGNATURE_SIGNERS_INVALID");
      expect(
        await signatures
          .request({ ...subject, signers: [ada.id], meaning: "witnessed" })
          .then(hint),
      ).toBe("SIGNATURE_REQUEST_MEANING_UNKNOWN");

      const request = await signatures
        .request({
          ...subject,
          signers: [ada.id, bob.id],
          order: "sequential",
          approvalRequestId: approval.id,
          message: "Please sign the terms",
          meaning: "approved",
        })
        .orThrow();

      expect(request).toMatchObject({
        status: "pending",
        order: "sequential",
        signers: [ada.id, bob.id],
        approvalRequestId: approval.id,
        meaning: "approved",
      });

      const frozen = await s.rows<{ frozen: boolean }>(
        "select frozen from better_supabase.versions where id = $1",
        [request.versionId],
      );

      expect(frozen[0]?.frozen).toBe(true);

      await s.as(bob);
      expect(
        await signatures.sign(request.id, { method: "click" }).then(hint),
      ).toBe("SIGNATURE_OUT_OF_ORDER");
      await s.as(ada);
      expect(
        await signatures
          .sign(request.id, { method: "typed", typedName: " " })
          .then(hint),
      ).toBe("SIGNATURE_METHOD_INVALID");
      expect(
        await signatures
          .sign(request.id, {
            method: "drawn",
            imageAttachmentId: crypto.randomUUID(),
          })
          .then(hint),
      ).toBe("SIGNATURE_METHOD_INVALID");

      const first = await signatures
        .sign(request.id, { method: "typed", typedName: "Ada Lovelace" })
        .orThrow();

      expect(first).toMatchObject({
        signer: ada.id,
        method: "typed",
        typedName: "Ada Lovelace",
        requestStatus: "pending",
      });
      expect(first.signedHash).toMatch(/^[0-9a-f]{64}$/);
      expect(
        await signatures.sign(request.id, { method: "click" }).then(hint),
      ).toBe("SIGNATURE_ALREADY_SIGNED");

      const decided = await s.rows<{ status: string }>(
        "select status from better_supabase.approval_requests where id = $1",
        [approval.id],
      );

      expect(decided[0]?.status).toBe("approved");

      await s.as(bob);

      const second = await signatures
        .sign(request.id, { method: "click" })
        .orThrow();

      expect(second.requestStatus).toBe("completed");
      const detail = await signatures.get(request.id).orThrow();
      expect(detail).toMatchObject({
        status: "completed",
        meaning: "approved",
      });
      expect(detail.signatures.map((row) => row.signer)).toEqual([
        ada.id,
        bob.id,
      ]);
      expect(detail.verification).toMatchObject({
        valid: true,
        contentMatches: true,
        changedSince: false,
      });
      expect(await signatures.decline(request.id).then(hint)).toBe(
        "SIGNATURE_REQUEST_CLOSED",
      );
      expect(
        (await signatures.list(tenant, { mine: true }).orThrow()).map(
          (row) => row.id,
        ),
      ).toEqual([request.id]);

      await s.service();
      await s.client.query(
        "update signatures_it.contracts set body = 'Terms v2' where id = $1",
        [contract],
      );
      await s.as(owner);
      await s.value(
        "better_supabase.snapshot_version($1, 'contract', $2::text)",
        [tenant, contract],
      );
      const edited = await signatures.get(request.id).orThrow();
      expect(edited.verification).toMatchObject({
        valid: true,
        changedSince: true,
      });
      expect(edited.verification.latestVersionId).not.toBe(request.versionId);

      await s.service();
      await s.client.query(
        "update better_supabase.signatures set typed_name = 'Eve' where id = $1",
        [first.id],
      );
      await s.client.query(
        `update better_supabase.versions set content = '{"body": "Forged"}' where id = $1`,
        [request.versionId],
      );
      await s.as(owner);
      const tampered = await signatures.get(request.id).orThrow();
      expect(tampered.verification).toMatchObject({
        valid: false,
        contentMatches: false,
      });
      expect(
        tampered.verification.signatures.find((row) => row.id === first.id)
          ?.valid,
      ).toBe(false);
      expect(
        await signatures
          .request({
            ...subject,
            signers: [bob.id],
            versionId: request.versionId,
          })
          .orThrow()
          .then((next) => signatures.cancel(next.id).orThrow())
          .then((row) => row.status),
      ).toBe("cancelled");

      const fresh = await signatures
        .request({ ...subject, signers: [ada.id] })
        .orThrow();

      await s.as(bob);
      expect(await signatures.get(fresh.id).then(hint)).toBe("ok");
      expect(await signatures.decline(fresh.id).then(hint)).toBe(
        "SIGNATURE_FORBIDDEN",
      );
      await s.as(stranger);
      expect(await signatures.get(fresh.id).then(hint)).toBe(
        "SIGNATURE_FORBIDDEN",
      );
      expect(await signatures.cancel(fresh.id).then(hint)).toBe(
        "SIGNATURE_FORBIDDEN",
      );
      await s.as(ada);

      const declined = await signatures
        .decline(fresh.id, "Wrong terms")
        .orThrow();

      expect(declined.status).toBe("declined");

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where organization_id = $1 and type like 'signature_request.%' order by position",
        [tenant],
      );

      expect(events.map((row) => row.type)).toEqual([
        "signature_request.requested",
        "signature_request.signed",
        "signature_request.signed",
        "signature_request.completed",
        "signature_request.requested",
        "signature_request.cancelled",
        "signature_request.requested",
        "signature_request.declined",
      ]);

      const completed = await s.rows<{ payload: { meaning: string | null } }>(
        "select payload from better_supabase.outbox_events where organization_id = $1 and type = 'signature_request.completed'",
        [tenant],
      );

      expect(completed[0]?.payload.meaning).toBe("approved");
    } finally {
      await s.close();
    }
  });
});
