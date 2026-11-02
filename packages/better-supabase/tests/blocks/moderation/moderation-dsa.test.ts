import { describe, expect, it } from "vitest";

import { createModeration } from "../../../src/blocks/moderation/index.ts";

const AT = "2026-10-22T10:00:00Z";

const NOTICE = {
  id: "n1",
  organizationId: "org-1",
  subjectType: "comment",
  subjectId: "c1",
  explanation: "Illegal",
  trusted: true,
  status: "received",
  createdAt: AT,
};

const FULL_NOTICE = {
  ...NOTICE,
  itemId: "i1",
  url: "https://example.com/c1",
  notifierName: "Ann",
  notifierEmail: "ann@example.com",
  notifierId: "u9",
  outcome: "Hidden",
  decidedBy: "u3",
  decidedAt: AT,
  status: "actioned",
};

const STATEMENT = {
  id: "s1",
  organizationId: "org-1",
  itemId: "i1",
  restriction: "removal",
  facts: "Facts",
  createdAt: AT,
};

const FULL_STATEMENT = {
  ...STATEMENT,
  legalGround: "Law",
  termsGround: "Terms",
  automatedDetection: true,
  automatedDecision: true,
  redress: ["internal", 4],
  issuedBy: "u3",
};

const FLAGGER = {
  id: "f1",
  organizationId: "org-1",
  userId: "u5",
  name: "Hotline",
  awardedBy: "u3",
  revokedAt: AT,
  createdAt: AT,
};

const APPEAL = {
  id: "ap1",
  organizationId: "org-1",
  reasons: "Wrong",
  status: "open",
  createdAt: AT,
};

const FULL_APPEAL = {
  ...APPEAL,
  statementId: "s1",
  noticeId: "n1",
  appellantId: "u1",
  outcome: "Fine",
  decidedBy: "u3",
  decidedAt: AT,
  status: "reversed",
};

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    transport: {
      call(
        _schema: string,
        fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push([fn, { ...args }]);

        return Promise.resolve(results[fn]);
      },
    },
  };
}

describe("createModeration notices and statements", () => {
  it("submits, lists and decides notices", async () => {
    const fake = fakeTransport({
      submit_notice: NOTICE,
      list_notices: [NOTICE, FULL_NOTICE],
      decide_notice: FULL_NOTICE,
    });

    const moderation = createModeration({
      transport: fake.transport,
      tenant: "org-1",
    });

    const sent = await moderation
      .submitNotice({
        subject: { type: "comment", id: "c1" },
        notice: {
          explanation: "Illegal",
          url: "https://example.com/c1",
          notifierName: "Ann",
          notifierEmail: "ann@example.com",
        },
      })
      .orThrow();

    expect(sent).toMatchObject({ id: "n1", trusted: true });
    expect(sent.url).toBeUndefined();

    await moderation
      .submitNotice({
        subject: { type: "comment", id: "c1" },
        notice: { explanation: "Illegal" },
      })
      .orThrow();

    const listed = await moderation
      .notices({ status: "received", pageSize: 5 })
      .orThrow();

    expect(listed[1]).toMatchObject({
      itemId: "i1",
      notifierId: "u9",
      outcome: "Hidden",
      status: "actioned",
    });
    expect(listed[1]?.decidedAt?.toString()).toBe(AT);
    expect(await moderation.notices().orThrow()).toHaveLength(2);

    const decided = await moderation
      .decideNotice({ noticeId: "n1", decision: "hide", outcome: "Hidden" })
      .orThrow();

    expect(decided.decidedBy).toBe("u3");
    await moderation
      .decideNotice({ noticeId: "n1", decision: "reject" })
      .orThrow();

    expect(fake.calls.map(([fn]) => fn)).toEqual([
      "submit_notice",
      "submit_notice",
      "list_notices",
      "list_notices",
      "decide_notice",
      "decide_notice",
    ]);
    expect(fake.calls[1]?.[1]).toMatchObject({
      url: null,
      notifier_name: null,
      notifier_email: null,
    });
    expect(fake.calls[3]?.[1]).toEqual({
      tenant: "org-1",
      status: null,
      page_size: null,
    });
    expect(fake.calls[5]?.[1]).toEqual({
      notice_id: "n1",
      decision: "reject",
      outcome: null,
    });
  });

  it("issues and lists statements of reasons", async () => {
    const fake = fakeTransport({
      issue_statement: FULL_STATEMENT,
      list_statements: [STATEMENT, { ...STATEMENT, redress: "none" }],
    });

    const moderation = createModeration({
      transport: fake.transport,
      tenant: "org-1",
    });

    const full = await moderation
      .issueStatement({
        itemId: "i1",
        statement: {
          restriction: "removal",
          facts: "Facts",
          legalGround: "Law",
          termsGround: "Terms",
          automatedDetection: true,
          automatedDecision: true,
          redress: ["internal"],
        },
      })
      .orThrow();

    expect(full).toMatchObject({
      legalGround: "Law",
      termsGround: "Terms",
      automatedDetection: true,
      automatedDecision: true,
      issuedBy: "u3",
    });
    expect(full.redress).toHaveLength(2);

    await moderation
      .issueStatement({
        itemId: "i1",
        statement: { restriction: "demotion", facts: "F" },
      })
      .orThrow();

    const listed = await moderation.statements("i1").orThrow();

    expect(listed[0]).toMatchObject({ automatedDetection: false, redress: [] });
    expect(listed[0]?.legalGround).toBeUndefined();
    expect(listed[1]?.redress).toEqual([]);

    expect(fake.calls[0]?.[1]).toMatchObject({
      legal_ground: "Law",
      automated_detection: true,
      redress: ["internal"],
    });
    expect(fake.calls[1]?.[1]).toMatchObject({
      legal_ground: null,
      terms_ground: null,
      automated_detection: false,
      automated_decision: false,
      redress: null,
    });
    expect(fake.calls[2]).toEqual(["list_statements", { item_id: "i1" }]);
  });

  it("rejects an unknown restriction, notice status or non-record row", async () => {
    const moderation = createModeration({
      transport: fakeTransport({
        issue_statement: { ...STATEMENT, restriction: "banish" },
        submit_notice: { ...NOTICE, status: "weird" },
        list_notices: [42],
        list_statements: "nope",
      }).transport,
      tenant: "org-1",
    });

    expect(
      (
        await moderation.issueStatement({
          itemId: "i1",
          statement: { restriction: "removal", facts: "F" },
        })
      ).ok,
    ).toBe(false);
    expect(
      (
        await moderation.submitNotice({
          subject: { type: "comment", id: "c1" },
          notice: { explanation: "x" },
        })
      ).ok,
    ).toBe(false);
    expect((await moderation.notices()).ok).toBe(false);
    expect((await moderation.statements("i1")).ok).toBe(false);
  });
});

describe("createModeration flaggers, appeals and reports", () => {
  it("awards and revokes trusted flaggers", async () => {
    const fake = fakeTransport({ set_trusted_flagger: FLAGGER });

    const moderation = createModeration({
      transport: fake.transport,
      tenant: "org-1",
    });

    const awarded = await moderation
      .setTrustedFlagger({ userId: "u5", name: "Hotline", awardedBy: "u3" })
      .orThrow();

    expect(awarded).toMatchObject({ awardedBy: "u3", name: "Hotline" });
    expect(awarded.revokedAt?.toString()).toBe(AT);

    await moderation
      .setTrustedFlagger({ userId: "u5", name: "Hotline" })
      .orThrow();
    await moderation.revokeTrustedFlagger("u5").orThrow();

    expect(fake.calls.map(([, args]) => args)).toEqual([
      {
        tenant: "org-1",
        user_id: "u5",
        name: "Hotline",
        awarded_by: "u3",
        active: true,
      },
      {
        tenant: "org-1",
        user_id: "u5",
        name: "Hotline",
        awarded_by: null,
        active: true,
      },
      {
        tenant: "org-1",
        user_id: "u5",
        name: null,
        awarded_by: null,
        active: false,
      },
    ]);
  });

  it("files and decides appeals", async () => {
    const fake = fakeTransport({
      file_appeal: APPEAL,
      decide_appeal: FULL_APPEAL,
    });

    const moderation = createModeration({
      transport: fake.transport,
      tenant: "org-1",
    });

    await moderation
      .appeal({ target: { statementId: "s1" }, reasons: "Wrong" })
      .orThrow();
    await moderation
      .appeal({ target: { noticeId: "n1" }, reasons: "Wrong" })
      .orThrow();

    const decided = await moderation
      .decideAppeal({ appealId: "ap1", outcome: "reversed", reason: "Fine" })
      .orThrow();

    expect(decided).toMatchObject({
      statementId: "s1",
      noticeId: "n1",
      appellantId: "u1",
      outcome: "Fine",
      status: "reversed",
    });
    expect(decided.decidedAt?.toString()).toBe(AT);
    await moderation
      .decideAppeal({ appealId: "ap1", outcome: "upheld" })
      .orThrow();

    expect(fake.calls.map(([, args]) => args)).toEqual([
      { statement_id: "s1", notice_id: null, reasons: "Wrong" },
      { statement_id: null, notice_id: "n1", reasons: "Wrong" },
      { appeal_id: "ap1", outcome: "reversed", reason: "Fine" },
      { appeal_id: "ap1", outcome: "upheld", reason: null },
    ]);
  });

  it("reads the transparency report", async () => {
    const fake = fakeTransport({
      transparency_report: "metric,dimension,value\nnotices,all,1\n",
    });

    const moderation = createModeration({
      transport: fake.transport,
      tenant: "org-1",
    });

    const csv = await moderation
      .transparencyReport({
        start: Temporal.Instant.from("2026-10-01T00:00:00Z"),
        end: Temporal.Instant.from("2026-11-01T00:00:00Z"),
      })
      .orThrow();

    expect(csv).toContain("notices,all,1");
    expect(fake.calls[0]).toEqual([
      "transparency_report",
      {
        tenant: "org-1",
        period_start: "2026-10-01T00:00:00Z",
        period_end: "2026-11-01T00:00:00Z",
      },
    ]);
  });

  it("rejects malformed appeal, flagger and action rows", async () => {
    const moderation = createModeration({
      transport: fakeTransport({
        file_appeal: { ...APPEAL, status: "pending" },
        set_trusted_flagger: { ...FLAGGER, createdAt: "not a date" },
        moderation_item: {
          id: "i1",
          organizationId: "org-1",
          subjectType: "comment",
          subjectId: "c1",
          status: "hidden",
          createdAt: AT,
          updatedAt: AT,
          actions: [
            {
              id: "a1",
              action: "submit",
              fromStatus: "gone",
              toStatus: "visible",
              createdAt: AT,
            },
          ],
        },
        report_content: { id: "r1", status: "bogus", createdAt: AT },
      }).transport,
      tenant: "org-1",
    });

    expect(
      (await moderation.appeal({ target: { noticeId: "n1" }, reasons: "x" }))
        .ok,
    ).toBe(false);
    expect(
      (await moderation.setTrustedFlagger({ userId: "u5", name: "H" })).ok,
    ).toBe(false);
    expect((await moderation.item({ type: "comment", id: "c1" })).ok).toBe(
      false,
    );
    expect(
      (
        await moderation.report({
          subject: { type: "comment", id: "c1" },
          report: { reason: "r" },
        })
      ).ok,
    ).toBe(false);
  });

  it("fails the tenant-scoped DSA calls without a tenant", async () => {
    const fake = fakeTransport({});
    const moderation = createModeration({ transport: fake.transport });

    expect(
      (
        await moderation.submitNotice({
          subject: { type: "comment", id: "c1" },
          notice: { explanation: "x" },
        })
      ).ok,
    ).toBe(false);
    expect((await moderation.notices()).ok).toBe(false);
    expect(
      (await moderation.setTrustedFlagger({ userId: "u", name: "n" })).ok,
    ).toBe(false);
    expect((await moderation.revokeTrustedFlagger("u")).ok).toBe(false);
    expect((await moderation.bans()).ok).toBe(false);
    expect(
      (
        await moderation.transparencyReport({
          start: Temporal.Instant.from(AT),
          end: Temporal.Instant.from(AT),
        })
      ).ok,
    ).toBe(false);
    expect(
      (await moderation.statuses({ subjectType: "c", ids: ["a"] })).ok,
    ).toBe(false);
    expect((await moderation.item({ type: "c", id: "a" })).ok).toBe(false);
    expect(fake.calls).toEqual([]);
  });
});
