import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { FilterQuery } from "../../src/list/index.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createAssignment } from "../../src/blocks/assignment/index.ts";
import { createParties } from "../../src/blocks/parties/index.ts";
import {
  createRulesAdmin,
  defineRuleFields,
} from "../../src/blocks/rules/index.ts";
import { createSegments } from "../../src/blocks/segments/index.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const layout: BlockSqlLayout = {
  subjects: withBlockSubjects({}, ["parties"], {}),
};

const MODULES = [
  "organizations",
  "outbox",
  "subjects",
  "rules",
  "parties",
  "segments",
  "assignment",
];

const companyFields = defineRuleFields("company", {
  name: { type: "text" },
  lifecycle: { type: "select", options: ["lead", "customer"] },
});

const lifecycleIs = (value: string): FilterQuery => ({
  id: "root",
  type: "group",
  combinator: "and",
  rules: [
    { id: "r1", type: "rule", path: ["lifecycle"], operator: "is", value },
  ],
});

describe.skipIf(!live)("segments and assignment", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("materializes a segment and routes records through queues", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const rep = await s.user("rep");
      const stranger = await s.user("stranger");
      await s.install(MODULES, layout);
      const org = await s.organization(owner, { member: rep });
      const other = await s.organization(stranger);
      const transport = sqlTransport(s.sql);

      await s.service();
      await createRulesAdmin({ transport }).syncFields(companyFields).orThrow();

      const parties = createParties({ transport });
      const segments = createSegments({ transport });
      const assignment = createAssignment({ transport });

      await s.as(owner);

      const acme = await parties
        .saveCompany(org, { name: "Acme", lifecycle: "customer" })
        .orThrow();

      const beta = await parties
        .saveCompany(org, { name: "Beta", lifecycle: "lead" })
        .orThrow();

      const customers = await segments
        .save(org, {
          subjectType: "company",
          name: "Customers",
          conditions: lifecycleIs("customer"),
        })
        .orThrow();

      expect(customers.refreshedAt).toBeUndefined();
      expect(await segments.refresh(customers.id).orThrow()).toEqual({
        entered: 1,
        left: 0,
        memberCount: 1,
      });
      expect(
        (await segments.members(customers.id).orThrow()).map(
          (member) => member.subjectId,
        ),
      ).toEqual([acme.id]);
      expect(
        (await segments.of({ type: "company", id: acme.id }).orThrow())[0]
          ?.segmentId,
      ).toBe(customers.id);

      const renamed = await segments
        .save(org, { id: customers.id, conditions: lifecycleIs("lead") })
        .orThrow();

      expect(renamed.refreshedAt).toBeUndefined();
      expect(await segments.refresh(customers.id).orThrow()).toEqual({
        entered: 1,
        left: 1,
        memberCount: 1,
      });
      expect(
        (await segments.save(org, { name: "" })).ok,
        "a segment without a subject type",
      ).toBe(false);

      await s.as(rep);
      expect(await segments.list(org).orThrow()).toHaveLength(1);
      expect((await segments.refresh(customers.id)).ok).toBe(false);

      await s.as(stranger);
      expect((await segments.list(org)).ok).toBe(false);
      expect(await segments.get(customers.id).orThrow()).toBeUndefined();
      expect(await segments.list(other).orThrow()).toEqual([]);

      await s.service();
      expect(
        await segments.refreshDue({ staleAfter: "1 hour" }).orThrow(),
      ).toEqual({ segments: 0, entered: 0, left: 0 });

      await s.as(owner);

      const queue = await assignment
        .saveQueue(org, {
          name: "Leads",
          subjectType: "company",
          strategy: "round_robin",
          conditions: lifecycleIs("lead"),
        })
        .orThrow();

      const staffed = await assignment
        .setMembers(queue.id, [{ userId: owner.id }, { userId: rep.id }])
        .orThrow();

      expect(staffed.members.map((member) => member.userId).toSorted()).toEqual(
        [owner.id, rep.id].toSorted(),
      );
      expect(
        (await assignment.setMembers(queue.id, [{ userId: stranger.id }])).ok,
      ).toBe(false);

      await s.service();

      const first = await assignment
        .assign(org, {
          type: "company",
          id: beta.id,
          fields: { lifecycle: "lead" },
        })
        .orThrow();

      const second = await assignment
        .assign(org, {
          type: "company",
          id: "x2",
          fields: { lifecycle: "lead" },
        })
        .orThrow();

      expect(first?.queueId).toBe(queue.id);
      expect(new Set([first?.userId, second?.userId])).toEqual(
        new Set([owner.id, rep.id]),
      );
      expect(
        await assignment
          .assign(org, { type: "company", id: acme.id, fields: {} })
          .orThrow(),
      ).toBeUndefined();

      await s.as(rep);
      expect(
        await assignment
          .history(org, { type: "company", id: beta.id })
          .orThrow(),
      ).toHaveLength(1);
      expect(
        (
          await assignment.queues(org, { subjectType: "company" }).orThrow()
        )[0]?.members.reduce((sum, member) => sum + member.assignedCount, 0),
      ).toBe(2);
      expect((await assignment.removeQueue(queue.id)).ok).toBe(false);

      await s.as(owner);
      expect(await assignment.removeQueue(queue.id).orThrow()).toBe(true);
      expect(await segments.remove(customers.id).orThrow()).toBe(true);
      expect(await segments.remove(customers.id).orThrow()).toBe(false);
    } finally {
      await s.close();
    }
  });
});
