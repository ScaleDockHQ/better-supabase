import { describe, expect, it, vi } from "vitest";

import { createForms, formSchema } from "../../../src/blocks/forms/index.ts";
import { SIGNUP } from "./fixtures.ts";

function transport(results: Record<string, (args: unknown) => unknown>) {
  const calls: [string, unknown][] = [];

  return {
    calls,
    call(schema: string, fn: string, args: unknown) {
      expect(schema).toBe("app");
      calls.push([fn, args]);
      const result = results[fn];

      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

      return Promise.resolve(result(args));
    },
  };
}

const AT = "2026-10-01T00:00:00Z";

const FORM = {
  id: "f1",
  organizationId: "o",
  key: "signup",
  title: "Sign up",
  description: null,
  status: "open",
  currentVersionId: "v1",
  createdBy: "u1",
  createdAt: AT,
  updatedAt: AT,
};

const VERSION = {
  id: "v1",
  formId: "f1",
  number: 1,
  definition: SIGNUP,
  schema: formSchema(SIGNUP),
  createdBy: "u1",
  createdAt: AT,
};

const SUBMISSION = {
  id: "s1",
  organizationId: "o",
  formId: "f1",
  versionId: "v1",
  subjectType: "lead",
  subjectId: "l1",
  respondentId: "u2",
  answers: { name: "Ada" },
  status: "submitted",
  source: "member",
  reviewedBy: null,
  reviewedAt: null,
  createdAt: AT,
  submittedAt: AT,
  updatedAt: AT,
};

describe("forms client", () => {
  it("creates, updates, publishes and reads forms", async () => {
    const fake = transport({
      create_form: () => ({ ...FORM, status: "draft", currentVersionId: null }),
      update_form: () => FORM,
      publish_form_version: () => VERSION,
      get_form: () => ({ ...FORM, version: VERSION }),
      get_form_version: () => VERSION,
      list_forms: () => [FORM],
    });

    const forms = createForms({ transport: fake, schema: "app" });

    const created = await forms
      .create({ organizationId: "o", key: "signup", title: "Sign up" })
      .orThrow();

    expect(created).toMatchObject({ status: "draft", createdBy: "u1" });
    expect(created.currentVersionId).toBeUndefined();
    expect(created.description).toBeUndefined();
    expect(created.createdAt.toString()).toBe(AT);
    expect(
      (await forms.update({ id: "f1", update: { status: "open" } }).orThrow())
        .status,
    ).toBe("open");

    const version = await forms
      .publish({ formId: "f1", definition: SIGNUP })
      .orThrow();

    expect(version).toMatchObject({ number: 1, definition: SIGNUP });
    expect(version.schema).toEqual(formSchema(SIGNUP));
    expect((await forms.get("f1").orThrow()).version?.id).toBe("v1");
    expect((await forms.getVersion("v1").orThrow()).formId).toBe("f1");
    expect(
      await forms.list({ organizationId: "o", status: "open" }).orThrow(),
    ).toHaveLength(1);
    expect(fake.calls).toEqual([
      [
        "create_form",
        { tenant: "o", key: "signup", title: "Sign up", description: null },
      ],
      [
        "update_form",
        { form_id: "f1", title: null, description: null, status: "open" },
      ],
      ["publish_form_version", { form_id: "f1", definition: SIGNUP }],
      ["get_form", { form_id: "f1" }],
      ["get_form_version", { version_id: "v1" }],
      ["list_forms", { tenant: "o", status: "open" }],
    ]);
  });

  it("reads a form without a version and lists every status by default", async () => {
    const fake = transport({
      get_form: () => ({ ...FORM, version: null }),
      list_forms: () => [],
      list_form_submissions: () => [],
    });

    const forms = createForms({ transport: fake, schema: "app" });
    expect((await forms.get("f1").orThrow()).version).toBeUndefined();
    await forms.list({ organizationId: "o" }).orThrow();
    await forms.listSubmissions({ formId: "f1" }).orThrow();
    expect(fake.calls.slice(1)).toEqual([
      ["list_forms", { tenant: "o", status: null }],
      [
        "list_form_submissions",
        { form_id: "f1", status: null, page_size: null, before: null },
      ],
    ]);
  });

  it("reads a submission's score and the NPS rollup", async () => {
    const fake = transport({
      get_form_submission: () => ({
        ...SUBMISSION,
        score: "3",
        maxScore: 4,
        passed: true,
      }),
      list_form_submissions: () => [
        { ...SUBMISSION, score: 1, maxScore: 4, passed: null },
        { ...SUBMISSION, score: null, maxScore: null, passed: null },
      ],
      form_nps: () => ({
        field: "nps",
        responses: 3,
        promoters: 2,
        passives: 0,
        detractors: 1,
        score: 33.3,
        periods: [
          {
            start: AT,
            responses: 3,
            promoters: 2,
            passives: 0,
            detractors: 1,
            score: 33.3,
          },
        ],
      }),
    });

    const forms = createForms({ transport: fake, schema: "app" });
    expect((await forms.getSubmission("s1").orThrow()).score).toEqual({
      score: 3,
      maxScore: 4,
      passed: true,
    });

    const [unmarked, draft] = await forms
      .listSubmissions({ formId: "f1" })
      .orThrow();

    expect(unmarked?.score).toEqual({ score: 1, maxScore: 4 });
    expect(draft?.score).toBeUndefined();

    const nps = await forms
      .nps({
        formId: "f1",
        field: "nps",
        since: Temporal.Instant.from(AT),
        bucket: "month",
      })
      .orThrow();

    expect(nps).toMatchObject({ field: "nps", score: 33.3, responses: 3 });
    expect(nps.periods[0]?.start.toString()).toBe(AT);
    expect(fake.calls.at(-1)).toEqual([
      "form_nps",
      { form_id: "f1", field: "nps", since: AT, until: null, bucket: "month" },
    ]);
  });

  it("leaves the NPS score out without responses", async () => {
    const fake = transport({
      form_nps: () => ({
        field: "nps",
        responses: 0,
        promoters: 0,
        passives: 0,
        detractors: 0,
        score: null,
        periods: [],
      }),
    });

    const forms = createForms({ transport: fake, schema: "app" });
    const nps = await forms.nps({ formId: "f1" }).orThrow();
    expect(nps.score).toBeUndefined();
    expect(fake.calls[0]).toEqual([
      "form_nps",
      { form_id: "f1", field: null, since: null, until: null, bucket: null },
    ]);
  });

  it("submits, reviews, lists and deletes submissions", async () => {
    const fake = transport({
      submit_form: () => SUBMISSION,
      get_form_submission: () => SUBMISSION,
      list_form_submissions: () => [SUBMISSION],
      review_form_submission: () => ({
        ...SUBMISSION,
        status: "accepted",
        reviewedBy: "u1",
        reviewedAt: "2026-10-02T00:00:00Z",
      }),
      delete_form_submission: () => true,
    });

    const forms = createForms({ transport: fake, schema: "app" });

    const submitted = await forms
      .submit({
        formId: "f1",
        answers: { name: "Ada" },
        subjectType: "lead",
        subjectId: "l1",
        submissionId: "s0",
        draft: true,
      })
      .orThrow();

    expect(submitted).toMatchObject({
      subjectType: "lead",
      respondentId: "u2",
      answers: { name: "Ada" },
      source: "member",
    });
    expect(submitted.reviewedAt).toBeUndefined();
    expect(submitted.submittedAt?.toString()).toBe(AT);
    await forms.submit({ formId: "f1", answers: {} }).orThrow();
    expect((await forms.getSubmission("s1").orThrow()).id).toBe("s1");

    const page = await forms
      .listSubmissions({
        formId: "f1",
        status: "submitted",
        pageSize: 10,
        before: Temporal.Instant.from(AT),
      })
      .orThrow();

    expect(page).toHaveLength(1);

    const reviewed = await forms
      .review({ id: "s1", status: "accepted" })
      .orThrow();

    expect(reviewed.reviewedBy).toBe("u1");
    expect(reviewed.reviewedAt?.toString()).toBe("2026-10-02T00:00:00Z");
    expect(await forms.deleteSubmission("s1").orThrow()).toBe(true);
    expect(fake.calls).toEqual([
      [
        "submit_form",
        {
          form_id: "f1",
          answers: { name: "Ada" },
          subject_type: "lead",
          subject_id: "l1",
          submission_id: "s0",
          draft: true,
        },
      ],
      [
        "submit_form",
        {
          form_id: "f1",
          answers: {},
          subject_type: null,
          subject_id: null,
          submission_id: null,
          draft: false,
        },
      ],
      ["get_form_submission", { submission_id: "s1" }],
      [
        "list_form_submissions",
        { form_id: "f1", status: "submitted", page_size: 10, before: AT },
      ],
      ["review_form_submission", { submission_id: "s1", status: "accepted" }],
      ["delete_form_submission", { submission_id: "s1" }],
    ]);
  });

  it("reads and submits public forms", async () => {
    const { createdBy: _, ...publicVersion } = VERSION;

    const fake = transport({
      get_public_form: () => ({
        id: "f1",
        title: "Sign up",
        description: "Join us",
        version: publicVersion,
      }),
      submit_public_form: () => ({
        id: "s2",
        status: "submitted",
        submittedAt: AT,
      }),
    });

    const forms = createForms({ transport: fake, schema: "app" });
    const form = await forms.getPublic("tok").orThrow();
    expect(form).toMatchObject({ id: "f1", description: "Join us" });
    expect("createdBy" in form.version).toBe(false);

    const sent = await forms
      .submitPublic({ token: "tok", answers: { name: "Ada" }, botToken: "t" })
      .orThrow();

    expect(sent.submittedAt?.toString()).toBe(AT);
    await forms.submitPublic({ token: "tok", answers: {} }).orThrow();
    expect(fake.calls.slice(1)).toEqual([
      [
        "submit_public_form",
        { token: "tok", answers: { name: "Ada" }, bot_token: "t" },
      ],
      ["submit_public_form", { token: "tok", answers: {}, bot_token: null }],
    ]);
  });

  it("rejects a version whose definition has no steps", async () => {
    const fake = transport({
      get_form_version: () => ({ ...VERSION, definition: { fields: [] } }),
    });

    const forms = createForms({ transport: fake, schema: "app" });
    const result = await forms.getVersion("v1");
    expect(result.ok).toBe(false);
  });

  it("runs hooks around a method", async () => {
    const fake = transport({ delete_form_submission: () => false });
    const after = vi.fn();

    const forms = createForms({
      transport: fake,
      schema: "app",
      hooks: { deleteSubmission: { after } },
      logger: { error: vi.fn(), warn: vi.fn(), info: vi.fn(), debug: vi.fn() },
    });

    expect(await forms.deleteSubmission("s1").orThrow()).toBe(false);
    expect(after).toHaveBeenCalledOnce();
  });
});
