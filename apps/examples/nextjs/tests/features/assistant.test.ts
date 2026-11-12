import { describe, expect, it } from "vitest";

import { assistantTour } from "@/features/assistant/assistant-tour";
import { questionsOf } from "@/features/assistant/components/chat-parts";

describe("questionsOf", () => {
  it("reads the clarifying questions of an askQuestions tool input", () => {
    const questions = questionsOf({
      questions: [
        {
          name: "direction",
          title: "Where should the rollout start?",
          choices: ["Internal team", "Everyone"],
        },
      ],
    });

    expect(questions).toHaveLength(1);
    expect(questions[0]?.name).toBe("direction");
  });

  it("drops entries without a name, a title or choices", () => {
    expect(
      questionsOf({
        questions: [{ name: "a" }, { title: "b", choices: [] }, "c"],
      }),
    ).toEqual([]);
  });

  it("returns nothing for input that is not an object", () => {
    expect(questionsOf(null)).toEqual([]);
    expect(questionsOf("text")).toEqual([]);
    expect(questionsOf({ questions: "none" })).toEqual([]);
  });
});

describe("assistantTour", () => {
  it("scripts the user turns the tour button sends", () => {
    const script = assistantTour();

    expect(script.next([])).toMatchObject({ role: "user" });
  });
});
