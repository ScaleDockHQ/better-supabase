import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";

import { createQualifications } from "../../src/blocks/qualifications/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = ["organizations", "outbox", "notifications", "qualifications"];

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

const today = (): Temporal.PlainDate => Temporal.Now.plainDateISO("UTC");

describe.skipIf(!live)("qualifications", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("reports gaps, qualified holders and expiry for a required licence", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const driver = await s.user("driver");
      const outsider = await s.user("outsider");
      await s.install(MODULES);
      const org = await s.organization(owner, { member: driver });

      const qualifications = createQualifications({
        transport: sqlTransport(s.sql),
      });

      await s.as(owner);

      const forklift = await qualifications
        .saveType(org, {
          key: "forklift",
          name: "Forklift licence",
          holderTypes: ["member"],
          validForMonths: 12,
        })
        .orThrow();

      expect(
        await qualifications
          .saveType(org, {
            key: "bad",
            name: "Bad",
            holderTypes: ["member"],
            validForMonths: 300,
          })
          .then(hint),
      ).toBe("QUALIFICATION_TYPE_INVALID");

      await qualifications
        .addRequirement(forklift.id, "role", "member")
        .orThrow();

      expect(await qualifications.gaps(org).orThrow()).toEqual([
        expect.objectContaining({
          holderId: driver.id,
          typeKey: "forklift",
          status: "missing",
        }),
      ]);

      await s.as(driver);
      expect(
        await qualifications
          .grant(org, {
            typeKey: "forklift",
            holderType: "member",
            holderId: driver.id,
          })
          .then(hint),
      ).toBe("QUALIFICATION_FORBIDDEN");
      expect(await qualifications.gaps(org).then(hint)).toBe(
        "QUALIFICATION_FORBIDDEN",
      );

      await s.as(owner);

      const grantedOn = today().subtract({ days: 350 });

      const holding = await qualifications
        .grant(org, {
          typeKey: "forklift",
          holderType: "member",
          holderId: driver.id,
          grantedOn,
        })
        .orThrow();

      expect(holding).toMatchObject({ source: "manual", status: "expiring" });
      expect(holding.expiresOn?.toString()).toBe(
        grantedOn.add({ months: 12 }).toString(),
      );
      expect(
        await qualifications.qualifiedHolders(org, "forklift").orThrow(),
      ).toEqual([driver.id]);
      expect(
        await qualifications
          .qualifiedHolders(org, "forklift", { on: today().add({ days: 60 }) })
          .orThrow(),
      ).toEqual([]);

      await s.as(driver);
      expect(
        await qualifications.gaps(org, { holderId: driver.id }).orThrow(),
      ).toEqual([expect.objectContaining({ status: "expiring" })]);
      expect(await qualifications.of("member", driver.id).orThrow()).toEqual([
        expect.objectContaining({ id: holding.id }),
      ]);

      await s.service();
      expect(await qualifications.notifyExpiring().orThrow()).toBe(1);
      expect(await qualifications.notifyExpiring().orThrow()).toBe(0);

      await s.as(owner);

      const revoked = await qualifications
        .revoke(holding.id, "Failed the check")
        .orThrow();

      expect(revoked).toMatchObject({
        status: "revoked",
        revokeReason: "Failed the check",
      });
      expect(
        await qualifications.gaps(org, { status: "missing" }).orThrow(),
      ).toHaveLength(1);

      await s.asRole(outsider);
      expect(await qualifications.types(org).orThrow()).toEqual([]);

      await s.service();

      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where type like 'qualification%'",
      );

      expect(new Set(events.map((row) => row.type))).toEqual(
        new Set([
          "qualification_type.created",
          "qualification.granted",
          "qualification.expiry_warned",
          "qualification.revoked",
        ]),
      );
    } finally {
      await s.close();
    }
  });
});
