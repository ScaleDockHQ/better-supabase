import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { ModuleLayout } from "../../src/sql/module-types.ts";

import { createLeases, sqlTransport } from "../../src/blocks/leases/index.ts";
import { createParties } from "../../src/blocks/parties/index.ts";
import { money } from "../../src/commerce/money.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "organizations",
  "outbox",
  "audit",
  "subjects",
  "relations",
  "parties",
  "assets",
  "ledger",
  "leases",
];

const layout: ModuleLayout = {
  subjects: withBlockSubjects({}, ["parties"], {}),
};

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

const day = (text: string): Temporal.PlainDate => Temporal.PlainDate.from(text);

describe.skipIf(!live)("leases", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("posts rent once per period, takes payments and releases the deposit on termination", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const ada = await s.user("ada");
      await s.install(MODULES, layout);
      const tenant = await s.organization(owner, { member: ada });
      const transport = sqlTransport(s.sql);
      const leases = createLeases({ transport, tenant });

      await s.as(owner);

      const company = await createParties({ transport })
        .saveCompany(tenant, { name: "Acme" })
        .orThrow();

      const unit = await s.value<{ id: string }>(
        "better_supabase.create_asset($1, 'unit', 'Flat 2A')",
        [tenant],
      );

      const draft = await leases
        .create({
          unitId: unit.id,
          party: { type: "company", id: company.id },
          startsOn: day("2026-01-01"),
          endsOn: day("2027-01-01"),
          rent: money(100_000n, "EUR"),
          deposit: money(200_000n, "EUR"),
        })
        .orThrow();

      expect(draft.status).toBe("draft");
      expect(
        await leases
          .create({
            unitId: unit.id,
            party: { type: "company", id: crypto.randomUUID() },
            startsOn: day("2026-01-01"),
            rent: money(100n, "EUR"),
          })
          .then(hint),
      ).toBe("LEASE_PARTY_INVALID");

      const active = await leases.activate(draft.id).orThrow();

      expect(active.status).toBe("active");
      expect(active.depositHeld).toEqual(money(200_000n, "EUR"));
      expect(
        await leases.postDueRent({ through: day("2026-03-15") }).orThrow(),
      ).toBe(3);
      expect(
        await leases.postDueRent({ through: day("2026-03-15") }).orThrow(),
      ).toBe(0);

      const charges = await leases.charges(draft.id).orThrow();

      expect(charges.map((charge) => charge.periodStart.toString())).toEqual([
        "2026-03-01",
        "2026-02-01",
        "2026-01-01",
      ]);

      const paid = await leases
        .recordPayment(draft.id, {
          amount: money(150_000n, "EUR"),
          reference: "bank-1",
        })
        .orThrow();

      expect(paid.balanceDue).toEqual(money(150_000n, "EUR"));
      expect(
        (
          await leases
            .recordPayment(draft.id, {
              amount: money(150_000n, "EUR"),
              reference: "bank-1",
            })
            .orThrow()
        ).balanceDue,
      ).toEqual(money(150_000n, "EUR"));

      await s.as(ada);

      const request = await leases
        .fileMaintenance({
          unitId: unit.id,
          leaseId: draft.id,
          title: "Leaking tap",
          priority: "high",
        })
        .orThrow();

      expect(request).toMatchObject({ status: "open", priority: "high" });
      expect(await leases.get(draft.id).then(hint)).toBe("LEASE_NOT_FOUND");
      expect(await leases.postDueRent().then(hint)).toBe("LEASES_FORBIDDEN");

      await s.as(owner);

      const ended = await leases
        .terminate(draft.id, {
          on: day("2026-04-01"),
          reason: "Moved out",
          depositDeduction: money(50_000n, "EUR"),
        })
        .orThrow();

      expect(ended.status).toBe("terminated");
      expect(ended.depositHeld).toEqual(money(0n, "EUR"));

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where organization_id = $1 and (type like 'lease.%' or type like 'maintenance_request.%') order by position",
        [tenant],
      );

      expect(events.map((event) => event.type)).toEqual([
        "lease.created",
        "lease.activated",
        "lease.charged",
        "lease.charged",
        "lease.charged",
        "lease.paid",
        "maintenance_request.filed",
        "lease.terminated",
      ]);
    } finally {
      await s.close();
    }
  });
});
