import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { MailProvider } from "../../src/blocks/mail-sync/index.ts";
import type { CredentialProvider } from "../../src/credentials/provider.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";
import type { TestUser } from "./block-session.ts";

import { createMailSync } from "../../src/blocks/mail-sync/index.ts";
import { createParties } from "../../src/blocks/parties/index.ts";
import { createSequences } from "../../src/blocks/sequences/index.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { AsyncResult } from "../../src/core/result.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const layout: BlockSqlLayout = {
  subjects: withBlockSubjects({}, ["parties"], {}),
};

const MODULES = [
  "organizations",
  "outbox",
  "notifications",
  "subjects",
  "parties",
  "engagements",
  "mail-sync",
  "pipelines",
  "work-items",
  "enrollments",
  "sequences",
];

const credentials: CredentialProvider = {
  apiVersion: 1,
  name: "vault",
  getToken: () =>
    AsyncResult.ok({ token: "t", headers: { authorization: "Bearer t" } }),
  capabilities: () => ({
    userSubjects: true,
    authorization: false,
    revoke: true,
    inbound: false,
  }),
  revoke: () => AsyncResult.ok(true),
};

function gmail(): MailProvider & { sent: unknown[] } {
  const sent: unknown[] = [];

  return {
    apiVersion: 1,
    name: "gmail",
    sent,
    list: () => AsyncResult.ok({ messages: [], cursor: "c1", more: false }),
    send: (input) => {
      sent.push(input);

      const id = `s${String(sent.length)}`;

      return AsyncResult.ok({
        externalId: id,
        threadId: "st1",
        messageId: `<${id}@acme.test>`,
      });
    },
  };
}

const STEPS = [
  {
    id: "hello",
    kind: "email",
    subject: "Hi {{firstName}}",
    text: "Hello {{firstName}}",
  },
  { id: "pause", kind: "wait", minutes: 60 },
  { id: "call", kind: "task", title: "Call the lead" },
] as const;

describe.skipIf(!live)("sequences module in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  const provider = gmail();
  let session: BlockSession;
  let owner: TestUser;
  let member: TestUser;
  let outsider: TestUser;
  let tenant: string;
  let mailbox: string;
  let ann: string;
  let ben: string;

  const mail = () =>
    createMailSync({
      transport: sqlTransport(session.sql),
      credentials,
      providers: [provider],
    });

  const sequencesFor = (organizationId: string, mailer = true) =>
    createSequences({
      transport: sqlTransport(session.sql),
      tenant: organizationId,
      ...(mailer ? { mailer: mail() } : {}),
    });

  const due = (enrollmentId: string) =>
    session.client.query(
      "update better_supabase.sequence_enrollments set next_run_at = now() - interval '1 minute' where enrollment_id = $1",
      [enrollmentId],
    );

  beforeAll(async () => {
    session = await BlockSession.open(pool);
    await session.install(MODULES, layout);
    owner = await session.user("sequences-owner");
    member = await session.user("sequences-member");
    outsider = await session.user("sequences-outsider");
    tenant = await session.organization(owner, { member });
    await session.organization(outsider);

    await session.as(owner);
    const parties = createParties({ transport: sqlTransport(session.sql) });

    ann = (
      await parties
        .savePerson(tenant, { name: "Ann Lead", email: "ann@lead.test" })
        .orThrow()
    ).id;
    ben = (
      await parties
        .savePerson(tenant, { name: "Ben Lead", email: "ben@lead.test" })
        .orThrow()
    ).id;
    mailbox = (
      await mail()
        .connect(tenant, {
          provider: "gmail",
          address: "sales@acme.test",
          credentialRef: { provider: "vault", tenant, key: "gmail" },
        })
        .orThrow()
    ).id;
  });

  afterAll(async () => {
    await session.close();
    await pool.end();
  });

  it("saves sequences and checks their steps", async () => {
    await session.as(owner);
    const sequences = sequencesFor(tenant);

    const sequence = await sequences
      .save({
        key: "intro",
        name: "Intro",
        status: "active",
        accountId: mailbox,
        steps: STEPS,
      })
      .orThrow();

    expect(sequence).toMatchObject({
      key: "intro",
      status: "active",
      exitOnReply: true,
      accountId: mailbox,
      version: 1,
      counts: { active: 0, paused: 0, completed: 0, exited: 0, replied: 0 },
    });
    expect(sequence.steps.map((step) => step.kind)).toEqual([
      "email",
      "wait",
      "task",
    ]);

    const renamed = await sequences
      .save({ id: sequence.id, name: "Intro sequence" })
      .orThrow();

    expect(renamed).toMatchObject({ name: "Intro sequence", version: 1 });

    const bad = [
      { key: "empty", name: "Empty", status: "active" },
      { key: "call", name: "Call", steps: [{ id: "s1", kind: "call" }] },
      {
        key: "twice",
        name: "Twice",
        steps: [
          { id: "s1", kind: "wait", minutes: 5 },
          { id: "s1", kind: "wait", minutes: 5 },
        ],
      },
    ] as const;

    const hints: (string | undefined)[] = [];

    for (const input of bad) {
      // SAFETY: invalid inputs on purpose, to reach the SQL checks.
      hints.push((await sequences.save(input as never)).error?.hint);
    }

    expect(hints).toEqual([
      "SEQUENCE_INVALID",
      "SEQUENCE_INVALID",
      "SEQUENCE_INVALID",
    ]);
    expect(await sequences.list().orThrow()).toEqual([
      expect.objectContaining({ key: "intro" }),
    ]);
    expect((await sequences.get(sequence.id).orThrow()).name).toBe(
      "Intro sequence",
    );
  });

  it("enrolls people, sends the email steps and runs the rest", async () => {
    await session.as(owner);
    const [sequence] = await sequencesFor(tenant).list().orThrow();

    await session.as(member);
    const sequences = sequencesFor(tenant);

    expect(
      (await sequences.save({ key: "mine", name: "Mine" })).error?.hint,
    ).toBe("SEQUENCE_FORBIDDEN");

    const run = await sequences
      .enroll(
        sequence!.id,
        { type: "person", id: ann },
        { variables: { firstName: "Ann" } },
      )
      .orThrow();

    expect(run).toMatchObject({
      address: "ann@lead.test",
      step: "hello",
      status: "active",
      accountId: mailbox,
      variables: { firstName: "Ann" },
    });
    expect(
      (
        await sequences
          .enroll(sequence!.id, { type: "person", id: ann })
          .orThrow()
      ).id,
    ).toBe(run.id);
    expect((await sequences.runDue()).error?.hint).toBe("SEQUENCE_FORBIDDEN");

    await session.service();
    const runner = sequencesFor(tenant);

    expect(await runner.runDue().orThrow()).toEqual({
      ran: 0,
      sent: 1,
      failed: 0,
    });
    expect(provider.sent).toEqual([
      expect.objectContaining({
        from: { address: "sales@acme.test" },
        draft: {
          to: [{ address: "ann@lead.test", name: "Ann Lead" }],
          subject: "Hi Ann",
          text: "Hello Ann",
        },
      }),
    ]);
    expect(await runner.runDue().orThrow()).toEqual({
      ran: 0,
      sent: 0,
      failed: 0,
    });

    await due(run.id);
    expect(await runner.runDue().orThrow()).toEqual({
      ran: 2,
      sent: 0,
      failed: 0,
    });

    await session.as(member);

    const [done] = await sequences
      .enrollments({ subject: { type: "person", id: ann } })
      .orThrow();

    expect(done?.status).toBe("completed");
    // The session is one transaction, so every step finishes at the same now().
    expect(done?.completedSteps.toSorted()).toEqual(["call", "hello", "pause"]);
    expect(done?.step).toBeUndefined();

    await session.service();

    const tasks = await session.rows<{ title: string }>(
      "select title from better_supabase.work_items where tenant_id = $1",
      [tenant],
    );

    expect(tasks).toEqual([{ title: "Call the lead" }]);
  });

  it("pauses, resumes and ends runs on a reply", async () => {
    await session.as(owner);
    const [sequence] = await sequencesFor(tenant).list().orThrow();

    await session.as(member);
    const sequences = sequencesFor(tenant);

    const run = await sequences
      .enroll(sequence!.id, { type: "person", id: ben })
      .orThrow();

    expect((await sequences.pause(run.id).orThrow()).status).toBe("paused");
    expect((await sequences.resume(run.id).orThrow()).status).toBe("active");

    await session.service();
    await session.client.query("select api.ingest_mail($1, $2::jsonb, null)", [
      mailbox,
      JSON.stringify([
        {
          externalId: "r1",
          threadId: "rt1",
          from: { address: "Ben@Lead.test" },
          to: [{ address: "sales@acme.test" }],
          subject: "Re: Hi",
          sentAt: "2026-10-01T09:00:00Z",
        },
      ]),
    ]);

    await session.as(member);

    const [replied] = await sequences
      .enrollments({ subject: { type: "person", id: ben } })
      .orThrow();

    expect(replied).toMatchObject({ status: "exited", exitReason: "replied" });
    expect((await sequences.exit(run.id)).error?.hint).toBe("SEQUENCE_INVALID");
    expect((await sequences.pause(crypto.randomUUID())).error?.hint).toBe(
      "SEQUENCE_ENROLLMENT_NOT_FOUND",
    );

    await session.as(owner);
    expect(
      (await sequencesFor(tenant).get(sequence!.id).orThrow()).counts,
    ).toMatchObject({ completed: 1, exited: 1, replied: 1 });
  });

  it("reports sends that fail and keeps other organizations out", async () => {
    await session.as(owner);
    const owned = sequencesFor(tenant, false);
    const [sequence] = await owned.list().orThrow();

    const cat = await createParties({ transport: sqlTransport(session.sql) })
      .savePerson(tenant, { name: "Cat Lead", email: "cat@lead.test" })
      .orThrow();

    await owned.enroll(sequence!.id, { type: "person", id: cat.id }).orThrow();

    await session.service();
    expect(await sequencesFor(tenant, false).runDue().orThrow()).toEqual({
      ran: 0,
      sent: 0,
      failed: 1,
    });

    await session.as(owner);

    const [failed] = await owned
      .enrollments({ subject: { type: "person", id: cat.id } })
      .orThrow();

    expect(failed).toMatchObject({ status: "active", attempts: 1 });
    expect(failed?.lastError).toContain("no mailer");

    const paused = await owned
      .save({ key: "draft", name: "Draft", steps: [STEPS[1]] })
      .orThrow();

    expect(
      (await owned.enroll(paused.id, { type: "person", id: cat.id })).error
        ?.hint,
    ).toBe("SEQUENCE_NOT_ACTIVE");

    await session.as(outsider);
    const others = sequencesFor(tenant);

    expect((await others.get(sequence!.id)).error?.hint).toBe(
      "SEQUENCE_NOT_FOUND",
    );
    expect((await others.list()).error?.hint).toBe("SEQUENCE_FORBIDDEN");
    expect((await others.delete(sequence!.id)).error?.hint).toBe(
      "SEQUENCE_FORBIDDEN",
    );

    await session.as(owner);
    expect(await owned.delete(paused.id).orThrow()).toBe(true);
    expect(await owned.delete(paused.id).orThrow()).toBe(false);
    expect(await owned.list({ status: "archived" }).orThrow()).toEqual([]);
  });
});
