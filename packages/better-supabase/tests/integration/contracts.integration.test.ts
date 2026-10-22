import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createContracts } from "../../src/blocks/contracts/index.ts";
import { createSignatures } from "../../src/blocks/signatures/index.ts";
import { money } from "../../src/commerce/money.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const TABLES = `create schema contracts_it;
create table contracts_it.vendors (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  name text not null
);`;

const MODULES = [
  "organizations",
  "outbox",
  "notifications",
  "queue",
  "subjects",
  "versions",
  "signatures",
  "reminders",
  "contracts",
];

const layout: BlockSqlLayout = {
  subjects: withBlockSubjects(
    { vendor: { table: "contracts_it.vendors", idType: "uuid" } },
    ["contracts"],
    {},
  ),
};

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

const day = (text: string): Temporal.PlainDate => Temporal.PlainDate.from(text);

describe.skipIf(!live)("contracts", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("runs a contract from draft through signature to renewal and termination", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const rep = await s.user("rep");
      const outsider = await s.user("outsider");
      await s.client.query(TABLES);
      await s.install(MODULES, layout);
      const org = await s.organization(owner, { member: rep });
      const other = await s.organization(outsider);

      const vendors = await s.rows<{ id: string }>(
        "insert into contracts_it.vendors (organization_id, name) values ($1, 'Initech'), ($2, 'Elsewhere') returning id",
        [org, other],
      );

      const vendor = vendors[0]!.id;
      const foreign = vendors[1]!.id;
      const transport = sqlTransport(s.sql);
      const contracts = createContracts({ transport });
      const signatures = createSignatures({ transport });

      await s.as(rep);
      expect(
        await contracts
          .create(org, {
            title: "Poached",
            counterparty: { type: "vendor", id: foreign },
          })
          .then(hint),
      ).toBe("CONTRACT_INVALID");

      const draft = await contracts
        .create(org, {
          title: "Hosting agreement",
          counterparty: { type: "vendor", id: vendor },
          value: money(2_400_000n, "EUR"),
          startsOn: day("2025-01-01"),
          endsOn: day("2025-12-31"),
          autoRenew: true,
          noticeDays: 60,
        })
        .orThrow();

      expect(draft).toMatchObject({
        status: "draft",
        ownerId: rep.id,
        autoRenew: true,
        renewalMonths: 12,
        noticeDays: 60,
        counterparty: { type: "vendor", id: vendor },
      });
      expect(draft.value?.amount).toBe(2_400_000n);
      expect(draft.noticeDeadline?.toString()).toBe("2025-11-01");

      const edited = await contracts
        .update(draft.id, { title: "Hosting agreement 2025" })
        .orThrow();

      expect(edited.title).toBe("Hosting agreement 2025");

      expect(
        (await contracts.transition(draft.id, "submit").orThrow()).status,
      ).toBe("in_review");
      expect(
        await contracts
          .sendForSignature(draft.id, { signers: [owner.id] })
          .then(hint),
      ).toBe("CONTRACT_FORBIDDEN");

      await s.as(owner);

      const out = await contracts
        .sendForSignature(draft.id, { signers: [owner.id] })
        .orThrow();

      expect(out.status).toBe("out_for_signature");
      expect(
        await contracts.update(draft.id, { title: "Changed" }).then(hint),
      ).toBe("CONTRACT_LOCKED");

      await signatures
        .sign(out.signatureRequestId ?? "", {
          method: "typed",
          typedName: "Owner",
        })
        .orThrow();
      const active = await contracts.get(draft.id).orThrow();
      expect(active.status).toBe("active");
      expect(active.signedAt).toBeDefined();

      const reminders = await s.rows<{ user_id: string }>(
        "select user_id from better_supabase.reminders where subject_type = 'contract' and subject_id = $1",
        [draft.id],
      );

      expect(reminders.map((row) => row.user_id)).toEqual([rep.id]);

      const obligation = await contracts
        .saveObligation(draft.id, {
          title: "Quarterly uptime report",
          dueOn: day("2025-03-31"),
          ownerId: rep.id,
        })
        .orThrow();

      expect(obligation).toMatchObject({ status: "open", overdue: true });

      await s.as(rep);
      expect(
        (await contracts.setObligationStatus(obligation.id, "done").orThrow())
          .status,
      ).toBe("done");
      expect(
        await contracts.obligations(org, { openOnly: true }).orThrow(),
      ).toEqual([]);

      await s.asRole(outsider);
      expect(await contracts.list(org).orThrow()).toEqual([]);

      await s.service();
      expect(await contracts.runRenewals(day("2026-01-02")).orThrow()).toEqual({
        renewed: 1,
        expired: 0,
      });

      await s.as(owner);
      const renewed = await contracts.get(draft.id).orThrow();
      expect(renewed.endsOn?.toString()).toBe("2026-12-31");
      expect(renewed.renewedCount).toBe(1);

      const ended = await contracts
        .transition(draft.id, "terminate", "Moved to another host")
        .orThrow();

      expect(ended).toMatchObject({
        status: "terminated",
        terminationReason: "Moved to another host",
      });
      expect(await contracts.transition(draft.id, "terminate").then(hint)).toBe(
        "CONTRACT_TRANSITION_INVALID",
      );

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where type like 'contract.%' order by position",
      );

      expect(events.map((row) => row.type)).toEqual(
        expect.arrayContaining([
          "contract.created",
          "contract.status_changed",
          "contract.renewed",
        ]),
      );
    } finally {
      await s.close();
    }
  });
});
