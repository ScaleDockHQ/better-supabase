import { describe, expect, it } from "vitest";

import {
  type FormDefinition,
  conditionHolds,
  finishQuestionnaire,
  formSchema,
  initialQuestionnaire,
  pruneAnswers,
  type QuestionnaireAction,
  type QuestionnaireState,
  questionnaireReducer,
  questionnaireSteps,
  stepIssues,
  visibleFields,
  visibleSteps,
} from "../../../src/blocks/forms/index.ts";
import { SIGNUP } from "./fixtures.ts";

const form = { definition: SIGNUP, schema: formSchema(SIGNUP) };

const run = (state: QuestionnaireState, ...actions: QuestionnaireAction[]) =>
  actions.reduce(
    (current, action) => questionnaireReducer(form, current, action),
    state,
  );

const answer = (key: string, value: unknown): QuestionnaireAction => ({
  type: "answer",
  key,
  // SAFETY: test values are JSON.
  value: value as never,
});

describe("conditions", () => {
  it("follows the semantics of the generated if", () => {
    expect(conditionHolds(undefined, {})).toBe(true);
    expect(conditionHolds({ field: "plan", equals: "team" }, {})).toBe(false);
    expect(
      conditionHolds({ field: "plan", equals: "team" }, { plan: "team" }),
    ).toBe(true);
    expect(
      conditionHolds({ field: "plan", in: ["a", "team"] }, { plan: "team" }),
    ).toBe(true);
    expect(conditionHolds({ field: "plan", in: ["a"] }, { plan: "team" })).toBe(
      false,
    );

    for (const empty of [null, "", []]) {
      expect(conditionHolds({ field: "x", filled: true }, { x: empty })).toBe(
        false,
      );
    }

    expect(conditionHolds({ field: "x", filled: true }, { x: false })).toBe(
      true,
    );
  });

  it("shows steps and fields whose showIf holds", () => {
    expect(visibleSteps(SIGNUP, {}).map((step) => step.key)).toEqual([
      "contact",
      "extra",
    ]);
    expect(visibleSteps(SIGNUP, { plan: "team" })).toHaveLength(3);
    expect(
      visibleFields(SIGNUP.steps[0]!, {}).map((field) => field.key),
    ).toEqual(["name", "email", "plan"]);
  });

  it("prunes hidden answers until nothing changes", () => {
    const definition: FormDefinition = {
      steps: [
        {
          key: "a",
          fields: [
            { key: "x", label: "X", type: "bool" as const },
            {
              key: "y",
              label: "Y",
              type: "text" as const,
              showIf: { field: "x", equals: true },
            },
            {
              key: "z",
              label: "Z",
              type: "text" as const,
              showIf: { field: "y", filled: true },
            },
          ],
        },
      ],
    };

    expect(pruneAnswers(definition, { x: false, y: "a", z: "b" })).toEqual({
      x: false,
    });
    expect(pruneAnswers(definition, { x: true, y: "a", z: "b" })).toEqual({
      x: true,
      y: "a",
      z: "b",
    });
  });

  it("reports only the issues of a step's visible fields", () => {
    expect(
      stepIssues(form.schema, SIGNUP.steps[0]!, {}).map((i) => i.path),
    ).toEqual([["name"], ["email"]]);
    expect(stepIssues(form.schema, SIGNUP.steps[2]!, {})).toEqual([]);
  });
});

describe("questionnaireReducer", () => {
  it("moves through the visible steps and blocks on issues", () => {
    let state = initialQuestionnaire(form);
    expect(state).toEqual({
      step: "contact",
      answers: {},
      completed: [],
      issues: [],
    });
    state = run(state, { type: "next" });
    expect(state.step).toBe("contact");
    expect(state.issues.map((issue) => issue.path?.[0])).toEqual([
      "name",
      "email",
    ]);
    state = run(state, answer("name", "Ada"));
    expect(state.issues.map((issue) => issue.path?.[0])).toEqual(["email"]);
    state = run(
      state,
      answer("email", "ada@example.com"),
      answer("plan", "team"),
      { type: "next" },
    );
    expect(state.issues.map((issue) => issue.path?.[0])).toEqual(["company"]);
    state = run(state, answer("company", "Acme"), { type: "next" });
    expect(state).toMatchObject({
      step: "team",
      completed: ["contact"],
      issues: [],
    });
    state = run(state, answer("seats", 3), answer("terms", true), {
      type: "next",
    });
    expect(state.step).toBe("extra");
    state = run(state, { type: "next" }, { type: "next" });
    expect(state).toMatchObject({
      step: "extra",
      completed: ["contact", "team", "extra"],
    });
    state = run(state, { type: "back" });
    expect(state.step).toBe("team");
    state = run(state, { type: "back" }, { type: "back" });
    expect(state.step).toBe("contact");
  });

  it("skips a step that becomes hidden", () => {
    let state = run(
      initialQuestionnaire(form),
      answer("name", "Ada"),
      answer("email", "ada@example.com"),
      { type: "next" },
    );

    expect(state.step).toBe("extra");
    state = run(state, answer("plan", "team"), { type: "back" });
    expect(state.step).toBe("team");
  });

  it("goes only to steps whose earlier steps are done", () => {
    const start = initialQuestionnaire(form, BASE_ANSWERS);
    expect(run(start, { type: "goTo", step: "extra" }).step).toBe("contact");
    expect(run(start, { type: "goTo", step: "missing" }).step).toBe("contact");
    const done = run(start, { type: "next" });
    expect(run(done, { type: "goTo", step: "contact" }).step).toBe("contact");
    expect(
      run(
        done,
        { type: "goTo", step: "extra" },
        { type: "goTo", step: "contact" },
      ).step,
    ).toBe("contact");
  });

  it("removes an answer and resets", () => {
    const state = run(
      initialQuestionnaire(form),
      answer("name", "Ada"),
      answer("name", undefined),
    );

    expect(state.answers).toEqual({});
    expect(
      run(state, { type: "reset", answers: { name: "Bo" } }).answers,
    ).toEqual({ name: "Bo" });
  });

  it("moves back when an answer hides the step on screen", () => {
    const team = run(
      initialQuestionnaire(form, {
        ...BASE_ANSWERS,
        plan: "team",
        company: "Acme",
      }),
      { type: "next" },
    );

    expect(team.step).toBe("team");
    expect(run(team, answer("plan", "free")).step).toBe("contact");

    const definition = {
      steps: [
        { key: "a", showIf: { field: "x", filled: true as const }, fields: [] },
        { key: "b", fields: [{ key: "x", label: "X", type: "text" as const }] },
      ],
    };

    const own = { definition, schema: formSchema(definition) };
    const state = { step: "a", answers: { x: "1" }, completed: [], issues: [] };
    expect(questionnaireReducer(own, state, answer("x", undefined)).step).toBe(
      "b",
    );
    const gone = { step: "a", answers: {}, completed: [], issues: [] };
    expect(
      questionnaireReducer(
        { definition: { steps: [definition.steps[0]!] }, schema: {} },
        gone,
        answer("y", 1),
      ).step,
    ).toBe("a");
  });

  it("ignores next on a step that is no longer visible", () => {
    const hidden = { step: "team", answers: {}, completed: [], issues: [] };
    expect(run(hidden, { type: "next" })).toBe(hidden);
  });

  it("starts on the first step when none is visible", () => {
    const definition = {
      steps: [
        {
          key: "only",
          showIf: { field: "x", filled: true as const },
          fields: [],
        },
      ],
    };

    expect(
      initialQuestionnaire({ definition, schema: formSchema(definition) }).step,
    ).toBe("only");
    expect(
      initialQuestionnaire({
        definition: { steps: [] },
        schema: { type: "object" },
      }).step,
    ).toBe("");
  });
});

const BASE_ANSWERS = { name: "Ada", email: "ada@example.com" };

describe("questionnaire views", () => {
  it("lists the steps in the shape a Stepper renders", () => {
    const state = run(initialQuestionnaire(form, BASE_ANSWERS), {
      type: "next",
    });

    expect(questionnaireSteps(form, state)).toEqual([
      expect.objectContaining({
        key: "contact",
        title: "Contact",
        description: "Who you are",
        completed: true,
        active: false,
      }),
      expect.objectContaining({ key: "extra", completed: false, active: true }),
    ]);
    expect(questionnaireSteps(form, state)[1]).not.toHaveProperty("title");
  });

  it("finishes with pruned answers or every issue", () => {
    expect(
      finishQuestionnaire(
        form,
        initialQuestionnaire(form, { ...BASE_ANSWERS, company: "x" }),
      ),
    ).toEqual({ ok: true, answers: BASE_ANSWERS });
    const failed = finishQuestionnaire(form, initialQuestionnaire(form));
    expect(failed.ok).toBe(false);
    expect(!failed.ok && failed.issues).toHaveLength(2);
  });
});
