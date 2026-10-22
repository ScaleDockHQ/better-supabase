import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../src/sql/module-types.ts";
import type { TestUser } from "./block-session.ts";

import {
  createAutomationsAdmin,
  defineRuleFields,
} from "../../src/blocks/automations/index.ts";
import { createContacts } from "../../src/blocks/contacts/index.ts";
import {
  createLeadScoring,
  leadRuleFields,
} from "../../src/blocks/lead-scoring/index.ts";
import { createScores } from "../../src/blocks/scores/index.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const layout: BlockSqlLayout = {
  subjects: withBlockSubjects({}, ["parties"], {}),
};

const people = defineRuleFields("person", {
  lifecycle: { type: "select", options: ["lead", "customer"] },
});

describe.skipIf(!live)("lead-scoring module in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  let session: BlockSession;
  let owner: TestUser;
  let member: TestUser;
  let outsider: TestUser;
  let tenant: string;
  let dee: string;

  const leadsFor = (organizationId: string) =>
    createLeadScoring({
      transport: sqlTransport(session.sql),
      tenant: organizationId,
    });

  const stale = async (subjectId: string): Promise<boolean | undefined> => {
    const [row] = await session.rows<{ stale: boolean }>(
      "select stale from better_supabase.lead_score_checks where subject_id = $1",
      [subjectId],
    );

    return row?.stale;
  };

  beforeAll(async () => {
    session = await BlockSession.open(pool);
    await session.install(
      [
        "organizations",
        "outbox",
        "subjects",
        "parties",
        "rules",
        "scores",
        "lead-scoring",
      ],
      layout,
    );
    owner = await session.user("leads-owner");
    member = await session.user("leads-member");
    outsider = await session.user("leads-outsider");
    tenant = await session.organization(owner, { member });
    await session.organization(outsider);
    await session.service();

    const rules = createAutomationsAdmin({
      transport: sqlTransport(session.sql),
    });

    await rules
      .syncFields({
        subjectType: "person",
        fields: [...people.fields, ...leadRuleFields("person").fields],
      })
      .orThrow();

    await session.as(owner);
    dee = (
      await createContacts({ transport: sqlTransport(session.sql) })
        .savePerson(tenant, {
          name: "Dee Lead",
          email: "dee@lead.test",
          lifecycle: "lead",
        })
        .orThrow()
    ).id;
    await createScores({ transport: sqlTransport(session.sql), tenant })
      .saveModel({
        key: "lead",
        name: "Lead score",
        subjectType: "person",
        rules: [
          {
            id: "lead",
            points: 10,
            conditions: {
              id: "g",
              type: "group",
              combinator: "and",
              rules: [
                {
                  id: "r",
                  type: "rule",
                  path: ["lifecycle"],
                  operator: "is",
                  value: "lead",
                },
              ],
            },
          },
        ],
        metrics: [
          { id: "sent", source: "field", field: "mail.sent", weight: 5 },
        ],
        bands: [{ label: "warm", min: 10 }],
      })
      .orThrow();
  });

  afterAll(async () => {
    await session.close();
    await pool.end();
  });

  it("reads a person's lead fields and scores them", async () => {
    await session.service();
    expect(await stale(dee)).toBe(true);

    await session.as(owner);
    const leads = leadsFor(tenant);
    const person = { type: "person", id: dee };

    expect(await leads.fields(person).orThrow()).toMatchObject({
      lifecycle: "lead",
      segments: [],
      mail: {},
    });
    expect(
      await leads.fields({ type: "person", id: "not-a-uuid" }).orThrow(),
    ).toBeNull();
    expect(await leads.score(person).orThrow()).toMatchObject({
      modelKey: "lead",
      modelVersion: 1,
      subject: person,
      score: 10,
      band: "warm",
      changed: true,
    });

    await session.service();
    expect(await stale(dee)).toBe(false);
  });

  it("rescores changed people in the due run", async () => {
    await session.service();
    await session.client.query(
      "update better_supabase.people set lifecycle = 'customer' where id = $1",
      [dee],
    );
    expect(await stale(dee)).toBe(true);
    expect(await leadsFor(tenant).scoreDue().orThrow()).toBe(1);
    expect(await stale(dee)).toBe(false);

    const [current] = await session.rows<{ score: string }>(
      "select score::text from better_supabase.scores where subject_id = $1 and is_current",
      [dee],
    );

    expect(Number(current?.score)).toBe(0);
    expect(await leadsFor(tenant).scoreDue().orThrow()).toBe(0);
  });

  it("checks permissions, subjects and organizations", async () => {
    await session.as(owner);
    const leads = leadsFor(tenant);

    expect((await leads.score({ type: "company", id: dee })).error?.hint).toBe(
      "LEAD_SCORING_SUBJECT",
    );
    expect(
      (await leads.score({ type: "person", id: crypto.randomUUID() })).error
        ?.hint,
    ).toBe("LEAD_SCORING_NOT_FOUND");

    await session.as(member);
    expect(
      (await leadsFor(tenant).score({ type: "person", id: dee })).error?.hint,
    ).toBe("LEAD_SCORING_FORBIDDEN");
    expect((await leadsFor(tenant).scoreDue()).error?.hint).toBe(
      "LEAD_SCORING_FORBIDDEN",
    );

    await session.as(outsider);
    expect(
      (await leadsFor(tenant).fields({ type: "person", id: dee })).error?.hint,
    ).toBe("LEAD_SCORING_FORBIDDEN");

    await session.asRole(outsider);
    expect(
      await session.rows(
        "select 1 from better_supabase.lead_score_checks where tenant_id = $1",
        [tenant],
      ),
    ).toEqual([]);
  });
});
