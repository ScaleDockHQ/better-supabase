import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { FormDefinition } from "../../src/core/contracts/form-definition.ts";

import { formScore, npsScore } from "../../src/blocks/forms/scoring.ts";
import { formSchema } from "../../src/core/contracts/form-definition.ts";
import { SIGNUP } from "../blocks/forms/fixtures.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "organizations",
  "outbox",
  "custom-fields",
  "share-links",
  "rate-limit",
  "forms",
];

const DEFINITION = {
  steps: [
    {
      key: "contact",
      title: "Contact",
      fields: [
        { key: "name", label: "Name", type: "text", required: true },
        { key: "email", label: "Email", type: "email", required: true },
        {
          key: "plan",
          label: "Plan",
          type: "option",
          options: [
            { value: "free", label: "Free" },
            { value: "team", label: "Team" },
          ],
        },
      ],
    },
    {
      key: "team",
      title: "Team",
      showIf: { field: "plan", equals: "team" },
      fields: [
        {
          key: "seats",
          label: "Seats",
          type: "integer",
          min: 2,
          required: true,
        },
        { key: "terms", label: "Terms", type: "consent", required: true },
      ],
    },
  ],
};

const QUIZ: FormDefinition = {
  scoring: { passMark: 60 },
  steps: [
    {
      key: "quiz",
      fields: [
        { key: "capital", label: "Capital", type: "text", correct: "Paris" },
        {
          key: "giants",
          label: "Gas giants",
          type: "multi",
          options: [
            { value: "jupiter", label: "Jupiter" },
            { value: "mars", label: "Mars" },
            { value: "saturn", label: "Saturn" },
          ],
          correct: ["jupiter", "saturn"],
          points: 2,
        },
        { key: "nps", label: "Recommend us?", type: "nps" },
      ],
    },
  ],
};

describe.skipIf(!live)("forms", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("publishes versions, validates submissions in Postgres and takes public answers", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const member = await s.user("member");
      await s.install(MODULES);
      const tenant = await s.organization(owner, { member });

      await s.asRole(owner);

      const form = await s.value<{ id: string; status: string }>(
        "better_supabase.create_form($1, 'signup', 'Sign up')",
        [tenant],
      );

      expect(form.status).toBe("draft");

      const version = await s.value<{
        number: number;
        schema: unknown;
        definition: unknown;
      }>("better_supabase.publish_form_version($1, $2)", [form.id, DEFINITION]);

      expect(version.number).toBe(1);
      expect(version.schema).toEqual(formSchema(DEFINITION as never));
      expect(
        await s.hint("better_supabase.publish_form_version($1, $2)", [
          form.id,
          { steps: [{ key: "a", fields: [{ key: "x", label: "X" }] }] },
        ]),
      ).toBe("FORM_DEFINITION_INVALID");
      await s.value("better_supabase.update_form($1, null, null, 'open')", [
        form.id,
      ]);

      await s.asRole(member);
      expect(
        await s.hint("better_supabase.submit_form($1, $2)", [
          form.id,
          { name: "Ada", email: "not-an-email" },
        ]),
      ).toBe("JSON_SCHEMA_INVALID");
      expect(
        await s.hint("better_supabase.submit_form($1, $2)", [
          form.id,
          { name: "Ada", email: "ada@example.test", plan: "team" },
        ]),
      ).toBe("JSON_SCHEMA_INVALID");

      const draft = await s.value<{ id: string; status: string }>(
        "better_supabase.submit_form($1, $2, null, null, null, true)",
        [form.id, { name: "Ada" }],
      );

      expect(draft.status).toBe("draft");

      const submitted = await s.value<{ id: string; status: string }>(
        "better_supabase.submit_form($1, $2, null, null, $3)",
        [
          form.id,
          {
            name: "Ada",
            email: "ada@example.test",
            plan: "team",
            seats: 3,
            terms: true,
          },
          draft.id,
        ],
      );

      expect(submitted).toMatchObject({ id: draft.id, status: "submitted" });
      expect(
        await s.hint("better_supabase.review_form_submission($1, 'accepted')", [
          draft.id,
        ]),
      ).toBe("FORM_FORBIDDEN");

      await s.asRole(owner);

      const reviewed = await s.value<{ status: string }>(
        "better_supabase.review_form_submission($1, 'accepted')",
        [draft.id],
      );

      expect(reviewed.status).toBe("accepted");

      const list = await s.value<unknown[]>(
        "better_supabase.list_form_submissions($1)",
        [form.id],
      );

      expect(list).toHaveLength(2 - 1);

      await s.service();
      const token = "public-form-token-0123456789abcdef";
      await s.client.query(
        `insert into better_supabase.share_links (tenant_id, subject_type, subject_id, token_hash, role)
         values ($1, 'form', $2, encode(extensions.digest(convert_to($3, 'utf8'), 'sha256'), 'hex'), 'respond')`,
        [tenant, form.id, token],
      );
      await s.asRole("anon");

      const pub = await s.value<{ id: string; version: { number: number } }>(
        "better_supabase.get_public_form($1)",
        [token],
      );

      expect(pub).toMatchObject({ id: form.id, version: { number: 1 } });

      const answered = await s.value<{ status: string }>(
        "better_supabase.submit_public_form($1, $2)",
        [token, { name: "Lin", email: "lin@example.test", plan: "free" }],
      );

      expect(answered.status).toBe("submitted");
      expect(
        await s.hint("better_supabase.get_public_form($1)", ["wrong-token"]),
      ).toBe("FORM_LINK_INVALID");

      await s.service();
      expect(
        await s.rows<{ type: string }>(
          `select type from better_supabase.outbox_events where payload ->> 'formId' = $1 or payload ->> 'id' = $1 order by created_at, type`,
          [form.id],
        ),
      ).toEqual(
        expect.arrayContaining([
          { type: "form.created" },
          { type: "form_version.published" },
          { type: "form_submission.submitted" },
          { type: "form_submission.reviewed" },
        ]),
      );
    } finally {
      await s.close();
    }
  });

  it("scores submissions in Postgres against a hidden answer key and rolls up NPS", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const member = await s.user("member");
      await s.install(MODULES);
      const tenant = await s.organization(owner, { member });
      await s.asRole(owner);

      const form = await s.value<{ id: string }>(
        "better_supabase.create_form($1, 'quiz', 'Quiz')",
        [tenant],
      );

      const published = await s.value<{ definition: FormDefinition }>(
        "better_supabase.publish_form_version($1, $2)",
        [form.id, QUIZ],
      );

      expect(published.definition).toEqual(QUIZ);
      expect(
        await s.hint("better_supabase.publish_form_version($1, $2)", [
          form.id,
          {
            steps: [
              {
                key: "q",
                fields: [{ key: "x", label: "X", type: "nps", correct: 9 }],
              },
            ],
          },
        ]),
      ).toBe("FORM_DEFINITION_INVALID");
      await s.value("better_supabase.update_form($1, null, null, 'open')", [
        form.id,
      ]);

      await s.asRole(member);

      const seen = await s.value<{ version: { definition: FormDefinition } }>(
        "better_supabase.get_form($1)",
        [form.id],
      );

      expect(JSON.stringify(seen.version.definition)).not.toContain("correct");
      expect(
        await s.hint("select * from better_supabase.form_answer_keys"),
      ).toMatch(/GRANT SELECT ON better_supabase\.form_answer_keys/);

      const answers = [
        { capital: " paris", giants: ["saturn", "jupiter"], nps: 10 },
        { capital: "Lyon", giants: ["jupiter"], nps: 9 },
        { capital: "Paris", giants: ["mars"], nps: 3 },
      ];

      const graded: unknown[] = [];

      for (const answer of answers) {
        const row = await s.value<{ id: string }>(
          "better_supabase.submit_form($1, $2)",
          [form.id, answer],
        );

        const read = await s.value<{
          score: number;
          maxScore: number;
          passed: boolean;
        }>("better_supabase.get_form_submission($1)", [row.id]);

        graded.push({
          score: read.score,
          maxScore: read.maxScore,
          passed: read.passed,
        });
      }

      expect(graded).toEqual(answers.map((answer) => formScore(QUIZ, answer)));

      const draft = await s.value<{ id: string }>(
        "better_supabase.submit_form($1, $2, null, null, null, true)",
        [form.id, { capital: "Paris" }],
      );

      const unscored = await s.value<{ score: unknown }>(
        "better_supabase.get_form_submission($1)",
        [draft.id],
      );

      expect(unscored.score).toBeNull();
      expect(await s.hint("better_supabase.form_nps($1)", [form.id])).toBe(
        "FORM_FORBIDDEN",
      );

      await s.asRole(owner);

      const nps = await s.value<Record<string, unknown>>(
        "better_supabase.form_nps($1, null, null, null, 'month')",
        [form.id],
      );

      expect(nps).toMatchObject({
        field: "nps",
        responses: 3,
        promoters: 2,
        passives: 0,
        detractors: 1,
        score: npsScore({ promoters: 2, passives: 0, detractors: 1 }),
      });
      expect(nps["periods"]).toHaveLength(1);
      expect(
        await s.hint("better_supabase.form_nps($1, null, null, null, 'hour')", [
          form.id,
        ]),
      ).toBe("FORM_NPS_BUCKET_INVALID");
      expect(
        await s.value(
          "better_supabase.form_nps($1, 'nps', now() + interval '1 day')",
          [form.id],
        ),
      ).toMatchObject({ responses: 0, score: null, periods: [] });

      await s.service();
      expect(
        await s.rows<{ payload: { score: number } }>(
          `select payload from better_supabase.outbox_events where type = 'form_submission.submitted' and payload ->> 'formId' = $1 order by created_at limit 1`,
          [form.id],
        ),
      ).toEqual([
        {
          payload: expect.objectContaining({
            score: 3,
            maxScore: 3,
            passed: true,
          }),
        },
      ]);
    } finally {
      await s.close();
    }
  });

  it("generates the same schema as formSchema for every field type and copies custom fields in", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      await s.install(MODULES);
      const tenant = await s.organization(owner);
      await s.service();

      const [{ id: definition }] = (await s.rows<{ id: string }>(
        `insert into better_supabase.field_definitions (tenant_id, entity, key, label, type, required)
         values ($1, 'lead', 'source', 'Source', 'option', true) returning id`,
        [tenant],
      )) as [{ id: string }];

      await s.asRole(owner);

      const form = await s.value<{ id: string }>(
        "better_supabase.create_form($1, 'everything', 'Everything')",
        [tenant],
      );

      const version = await s.value<{ schema: unknown }>(
        "better_supabase.publish_form_version($1, $2)",
        [form.id, SIGNUP],
      );

      expect(version.schema).toEqual(formSchema(SIGNUP));

      const linked = await s.value<{
        definition: FormDefinition;
        schema: unknown;
      }>("better_supabase.publish_form_version($1, $2)", [
        form.id,
        {
          steps: [
            {
              key: "lead",
              fields: [
                {
                  key: "source",
                  customField: definition,
                  options: [
                    { value: "web", label: "Web" },
                    { value: "event", label: "Event" },
                  ],
                },
              ],
            },
          ],
        },
      ]);

      expect(linked.definition.steps[0]!.fields[0]).toMatchObject({
        key: "source",
        label: "Source",
        type: "option",
        required: true,
        options: [
          { value: "web", label: "Web" },
          { value: "event", label: "Event" },
        ],
      });
      expect(linked.schema).toEqual(formSchema(linked.definition));
      expect(
        await s.hint("better_supabase.publish_form_version($1, $2)", [
          form.id,
          {
            steps: [
              {
                key: "lead",
                fields: [{ key: "source", customField: definition }],
              },
            ],
          },
        ]),
      ).toBe("FORM_DEFINITION_INVALID");
      expect(
        await s.hint("better_supabase.publish_form_version($1, $2)", [
          form.id,
          {
            steps: [
              {
                key: "lead",
                fields: [{ key: "source", customField: crypto.randomUUID() }],
              },
            ],
          },
        ]),
      ).toBe("FORM_DEFINITION_INVALID");
    } finally {
      await s.close();
    }
  });
});
