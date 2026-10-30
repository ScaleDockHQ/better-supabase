import { describe, expect, it, vi } from "vitest";

import type {
  MailMessage,
  MailSendDraft,
} from "../../../src/blocks/mail-sync/mail-sync.ts";

import {
  createSequences,
  fillPlaceholders,
  sequenceDraft,
  sequenceEnrollInputSchema,
  sequenceInputSchema,
  sequencesBlock,
  sequencesEvents,
} from "../../../src/blocks/sequences/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult } from "../../../src/core/result.ts";
import { fakeTransport } from "../inbox/fixtures.ts";

const AT = "2026-01-01T00:00:00Z";

const sequenceRow = {
  id: "s1",
  organizationId: "org",
  key: "welcome",
  name: "Welcome",
  description: null,
  status: "active",
  exitOnReply: true,
  accountId: "acc",
  steps: [
    {
      id: "intro",
      kind: "email",
      subject: "Hi {{name}}",
      text: "Hello {{name}}",
      html: "<p>{{name}}</p>",
      templateVersionId: "tv1",
      track: false,
    },
    { id: "pause", kind: "wait", minutes: 60 },
    { id: "call", kind: "task", title: "Call", body: "Ring", dueInMinutes: 30 },
    { id: "bare", kind: "task", title: "Bare" },
    { id: "plain", kind: "email", subject: "Plain" },
    { id: "odd", kind: "wait" },
  ],
  version: 2,
  counts: { active: 1, paused: 0, completed: 3, exited: 2, replied: 1 },
  createdBy: "u1",
  createdAt: AT,
  updatedAt: AT,
};

const enrollmentRow = {
  id: "e1",
  organizationId: "org",
  sequenceId: "s1",
  subjectType: "person",
  subjectId: "p1",
  address: "ada@example.test",
  name: null,
  accountId: "acc",
  threadId: null,
  step: "intro",
  nextRunAt: AT,
  status: "active",
  exitReason: null,
  attempts: 0,
  lastError: null,
  variables: { name: "Ada" },
  enrolledBy: "u1",
  completedSteps: [],
  createdAt: AT,
  updatedAt: AT,
};

const exited = {
  ...enrollmentRow,
  status: "exited",
  exitReason: "manual",
  step: null,
  nextRunAt: null,
  variables: null,
};

const email = (overrides: Record<string, unknown> = {}) => ({
  enrollmentId: "e1",
  accountId: "acc",
  threadId: "t1",
  to: { address: "ada@example.test", name: "Ada" },
  step: sequenceRow.steps[0],
  variables: { name: "Ada" },
  ...overrides,
});

const message = { id: "m1" } as MailMessage;

describe("createSequences", () => {
  it("saves, reads and deletes sequences", async () => {
    const { transport, call } = fakeTransport({
      save_sequence: sequenceRow,
      list_sequences: [{ ...sequenceRow, description: "Hi", counts: null }],
      get_sequence: sequenceRow,
      delete_sequence: true,
    });

    const sequences = createSequences({ transport, tenant: "org" });

    const saved = await sequences
      // SAFETY: an undefined key on purpose, to check that it is left out.
      .upsert({
        key: "welcome",
        name: "Welcome",
        description: undefined,
      } as never)
      .orThrow();

    expect(saved).toMatchObject({
      id: "s1",
      status: "active",
      exitOnReply: true,
      accountId: "acc",
      version: 2,
      counts: { completed: 3, replied: 1 },
      createdBy: "u1",
    });
    expect(saved.description).toBeUndefined();
    expect(saved.steps).toEqual([
      sequenceRow.steps[0],
      { id: "pause", kind: "wait", minutes: 60 },
      {
        id: "call",
        kind: "task",
        title: "Call",
        body: "Ring",
        dueInMinutes: 30,
      },
      { id: "bare", kind: "task", title: "Bare" },
      { id: "plain", kind: "email", subject: "Plain" },
      { id: "odd", kind: "wait", minutes: 0 },
    ]);
    expect(call).toHaveBeenCalledWith("better_supabase", "save_sequence", {
      tenant: "org",
      sequence: { key: "welcome", name: "Welcome" },
    });

    const [listed] = await sequences.list().orThrow();

    expect(listed?.description).toBe("Hi");
    expect(listed?.counts).toEqual({
      active: 0,
      paused: 0,
      completed: 0,
      exited: 0,
      replied: 0,
    });
    expect(call).toHaveBeenLastCalledWith("better_supabase", "list_sequences", {
      tenant: "org",
      status: null,
    });
    await sequences.list({ status: "archived" }).orThrow();
    expect(call).toHaveBeenLastCalledWith("better_supabase", "list_sequences", {
      tenant: "org",
      status: "archived",
    });

    expect((await sequences.get("s1").orThrow()).key).toBe("welcome");
    expect(await sequences.delete("s1").orThrow()).toBe(true);
  });

  it("defaults the fields a sparse row leaves out", async () => {
    const { transport } = fakeTransport({
      get_sequence: {
        ...sequenceRow,
        accountId: null,
        createdBy: null,
        exitOnReply: false,
        version: undefined,
      },
    });

    const got = await createSequences({ transport }).get("s1").orThrow();

    expect(got).toMatchObject({ exitOnReply: false, version: 1 });
    expect(got.accountId).toBeUndefined();
    expect(got.createdBy).toBeUndefined();
  });

  it("enrolls records and changes their runs", async () => {
    const { transport, call } = fakeTransport({
      enroll_in_sequence: enrollmentRow,
      change_sequence_enrollment: exited,
      list_sequence_enrollments: [enrollmentRow],
    });

    const sequences = createSequences({ transport, tenant: "org" });

    const run = await sequences
      .enroll(
        "s1",
        { type: "person", id: "p1" },
        { variables: { name: "Ada" } },
      )
      .orThrow();

    expect(run).toMatchObject({
      id: "e1",
      address: "ada@example.test",
      accountId: "acc",
      step: "intro",
      enrolledBy: "u1",
      variables: { name: "Ada" },
    });
    expect(run.name).toBeUndefined();
    expect(run.exitReason).toBeUndefined();
    expect(run.nextRunAt?.toString()).toBe(AT);
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "enroll_in_sequence",
      {
        sequence_id: "s1",
        subject_type: "person",
        subject_id: "p1",
        attrs: { variables: { name: "Ada" } },
      },
    );
    await sequences.enroll("s1", { type: "person", id: "p1" }).orThrow();

    const ended = await sequences.exit("e1").orThrow();

    expect(ended).toMatchObject({ status: "exited", exitReason: "manual" });
    expect(ended.variables).toEqual({});
    expect(ended.step).toBeUndefined();
    expect(ended.nextRunAt).toBeUndefined();
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "change_sequence_enrollment",
      { enrollment_id: "e1", action: "exit" },
    );
    await sequences.pause("e1").orThrow();
    await sequences.resume("e1").orThrow();
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "change_sequence_enrollment",
      { enrollment_id: "e1", action: "resume" },
    );

    expect(await sequences.enrollments().orThrow()).toHaveLength(1);
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "list_sequence_enrollments",
      { tenant: "org", filter: {} },
    );
    await sequences
      .enrollments({
        sequenceId: "s1",
        subject: { type: "person", id: "p1" },
        status: "active",
        limit: 10,
        before: Temporal.Instant.from(AT),
      })
      .orThrow();
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "list_sequence_enrollments",
      {
        tenant: "org",
        filter: {
          sequence: "s1",
          subjectType: "person",
          subjectId: "p1",
          status: "active",
          limit: 10,
          before: AT,
        },
      },
    );
  });

  it("needs a tenant for the organization's lists", async () => {
    const { transport } = fakeTransport({});
    const result = await createSequences({ transport }).list();

    expect(result.ok).toBe(false);
  });

  it("sends the due emails through the mailer and reports each one", async () => {
    const service = fakeTransport({
      run_due_sequences: {
        ran: 2,
        emails: [
          email(),
          email({
            enrollmentId: "e2",
            threadId: null,
            to: { address: "b@x.test" },
          }),
          email({ enrollmentId: "e3", accountId: null }),
        ],
      },
      sequence_step_sent: true,
      sequence_step_failed: true,
    });

    const send = vi.fn((_account: string, draft: MailSendDraft) =>
      JSON.stringify(draft.to).includes("b@x.test")
        ? AsyncResult.err<MailMessage>(dbError("network", "down"))
        : AsyncResult.ok(message),
    );

    const sequences = createSequences({
      transport: fakeTransport({}).transport,
      service: service.transport,
      mailer: { send },
    });

    expect(await sequences.runDue({ limit: 5 }).orThrow()).toEqual({
      ran: 2,
      sent: 1,
      failed: 2,
    });
    expect(service.call).toHaveBeenCalledWith(
      "better_supabase",
      "run_due_sequences",
      { max_count: 5 },
    );
    expect(send).toHaveBeenCalledWith("acc", {
      to: [{ address: "ada@example.test", name: "Ada" }],
      subject: "Hi Ada",
      text: "Hello Ada",
      html: "<p>Ada</p>",
      threadId: "t1",
      templateVersionId: "tv1",
      track: false,
    });
    expect(service.call).toHaveBeenCalledWith(
      "better_supabase",
      "sequence_step_sent",
      { enrollment_id: "e1", step: "intro", message_id: "m1" },
    );
    expect(service.call).toHaveBeenCalledWith(
      "better_supabase",
      "sequence_step_failed",
      { enrollment_id: "e2", step: "intro", error: "down" },
    );
    expect(service.call).toHaveBeenCalledWith(
      "better_supabase",
      "sequence_step_failed",
      expect.objectContaining({ enrollment_id: "e3" }),
    );
  });

  it("fails each email without a mailer and stops when a report fails", async () => {
    const { transport, call } = fakeTransport({
      run_due_sequences: { emails: [email()] },
      sequence_step_failed: true,
    });

    expect(await createSequences({ transport }).runDue().orThrow()).toEqual({
      ran: 0,
      sent: 0,
      failed: 1,
    });
    expect(call).toHaveBeenCalledWith("better_supabase", "run_due_sequences", {
      max_count: 50,
    });
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "sequence_step_failed",
      expect.objectContaining({ error: expect.stringContaining("mailer") }),
    );

    const broken = fakeTransport({ run_due_sequences: { emails: [email()] } });

    const result = await createSequences({
      transport: broken.transport,
      mailer: { send: () => AsyncResult.ok(message) },
    }).runDue();

    expect(result.ok).toBe(false);
  });
});

describe("sequence drafts", () => {
  it("fills placeholders and escapes them in HTML", () => {
    const vars = { name: "<Ada>", n: 2, ok: true, none: null, obj: {} };

    expect(
      fillPlaceholders("{{ name }} {{n}} {{ok}} {{none}}{{obj}}{{x}}", vars),
    ).toBe("<Ada> 2 true ");
    expect(
      fillPlaceholders(
        "<b>{{name}}</b> & {{q}}",
        { name: `<A&"'>`, q: "x" },
        true,
      ),
    ).toBe("<b>&lt;A&amp;&quot;&#39;&gt;</b> & x");
    expect(
      sequenceDraft({
        to: { address: "a@x.test" },
        step: { id: "s", kind: "email", subject: "Hi" },
        variables: {},
      }),
    ).toEqual({ to: [{ address: "a@x.test" }], subject: "Hi" });
  });
});

describe("sequences manifest", () => {
  it("validates input and declares the block", async () => {
    const validate = sequenceInputSchema["~standard"].validate;

    expect(
      (await validate({ key: "welcome", name: "Welcome" })).issues,
    ).toBeUndefined();
    expect((await validate({ key: "" })).issues).toBeDefined();
    expect(
      (await sequenceEnrollInputSchema["~standard"].validate({ address: "a" }))
        .issues,
    ).toBeDefined();
    expect(sequencesBlock.name).toBe("sequences");
    expect(sequencesEvents.types).toContain("sequence.created");
  });
});
