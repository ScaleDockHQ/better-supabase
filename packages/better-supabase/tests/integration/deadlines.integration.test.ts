import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { TestUser } from "./block-session.ts";

import { createDeadlines } from "../../src/blocks/deadlines/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { temporal } from "../../src/core/temporal-required.ts";
import { evaluateVersion } from "../../src/sql/modules/deadlines-evaluate.ts";
import { GOLDEN } from "../fixtures/deadlines.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const AZ = GOLDEN.find((fixture) => fixture.name === "az");

const FACTS = {
  claimant_contract_tier: "first_tier_sub",
  claimant_capacity: "contractor",
  property_use: "commercial",
  project_sector: "private",
  contract_is_written: true,
  payment_bond_recorded: false,
  first_furnishing_date: "2026-09-01",
  last_furnishing_date: "2026-10-15",
  notice_of_completion_recording_date: null,
  full_payment_date: null,
  lien_recording_date: null,
};

describe.skipIf(!live || AZ === undefined)(
  "deadlines module in Postgres",
  () => {
    const pool = new Pool({ connectionString: dbUrl, max: 1 });
    let session: BlockSession;
    let owner: TestUser;
    let tenant: string;

    beforeAll(async () => {
      session = await BlockSession.open(pool);
      await session.install(["organizations", "outbox", "deadlines"]);
      owner = await session.user("deadlines-owner");
      tenant = await session.organization(owner);
    });

    afterAll(async () => {
      await session.close();
      await pool.end();
    });

    it("computes a subject's deadlines as a member, as the TypeScript evaluator does", async () => {
      const content = AZ?.content ?? { rules: [], groups: [] };
      const { PlainDate } = temporal();

      await session.service();

      const service = createDeadlines({ transport: sqlTransport(session.sql) });

      const draft = await service
        .saveRules({
          jurisdiction: "az",
          kind: "lien",
          content,
          effectiveFrom: PlainDate.from("2020-01-01"),
        })
        .orThrow();

      await service.approveRules({ versionId: draft.id }).orThrow();
      await session.as(owner);

      const deadlines = createDeadlines({
        transport: sqlTransport(session.sql),
        tenant,
      });

      const rows = await deadlines
        .compute({
          subjectType: "job",
          subjectId: "j1",
          jurisdiction: "az",
          kind: "lien",
          facts: FACTS,
          asOf: PlainDate.from("2026-11-07"),
        })
        .orThrow();

      expect(
        rows.map((row) => [
          row.groupKey,
          row.result,
          row.dueOn?.toString() ?? null,
        ]),
      ).toEqual(
        evaluateVersion(content, FACTS, "2026-11-07").map((result) => [
          result.group,
          result.result,
          result.dueOn,
        ]),
      );

      const [notice] = rows;

      const satisfied = await deadlines
        .satisfy({ deadlineId: notice?.id ?? "", action: "served" })
        .orThrow();

      expect(satisfied.state).toBe("satisfied");
      expect(
        await deadlines
          .recompute({
            subjectType: "job",
            subjectId: "j1",
            facts: { full_payment_date: "2027-03-01" },
          })
          .orThrow(),
      ).toBe(3);

      const [release] = await deadlines
        .list({ subjectId: "j1", groupKey: "release_of_lien" })
        .orThrow();

      expect(release?.dueOn?.toString()).toBe("2027-03-22");
    });
  },
);
