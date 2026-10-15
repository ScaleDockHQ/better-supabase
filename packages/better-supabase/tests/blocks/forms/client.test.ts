import { describe, expect, it, vi } from "vitest";

import type { QuestionnaireOptions } from "../../../src/blocks/forms/client.ts";

import { createQuestionnaireController } from "../../../src/blocks/forms/client.ts";
import { formSchema } from "../../../src/blocks/forms/index.ts";
import { SIGNUP } from "./fixtures.ts";

const form = { definition: SIGNUP, schema: formSchema(SIGNUP) };

function mount(options: Partial<QuestionnaireOptions> = {}) {
  const onSubmit = vi.fn();
  const controller = createQuestionnaireController({
    form,
    onSubmit,
    ...options,
  });
  const render = () => ({
    ...controller.getSnapshot(),
    ...controller.actions,
  });
  return { render, onSubmit };
}

describe("createQuestionnaireController", () => {
  it("walks the steps and shows issues by field", () => {
    const { render } = mount();
    let view = render();
    expect(view).toMatchObject({
      isFirst: true,
      isLast: false,
      submitting: false,
    });
    expect(view.steps.map((step) => step.key)).toEqual(["contact", "extra"]);
    view.next();
    view = render();
    expect(view.issues).toEqual({
      name: ["is required"],
      email: ["is required"],
    });
    view.setAnswer("name", "Ada");
    view.setAnswer("email", "ada@example.com");
    view = render();
    expect(view.issues).toEqual({});
    view.next();
    view = render();
    expect(view.step?.key).toBe("extra");
    expect(view.isLast).toBe(true);
    view.back();
    view = render();
    expect(view.step?.key).toBe("contact");
    view.goTo("extra");
    view = render();
    expect(view.step?.key).toBe("extra");
  });

  it("submits the pruned answers once the form passes", async () => {
    const { render, onSubmit } = mount({
      initialAnswers: {
        name: "Ada",
        email: "ada@example.com",
        company: "hidden",
      },
    });
    const view = render();
    expect(await view.submit()).toBe(true);
    expect(onSubmit).toHaveBeenCalledWith({
      name: "Ada",
      email: "ada@example.com",
    });
    expect(render().submitting).toBe(false);
  });

  it("keeps every issue of a failed submit until the field changes", async () => {
    const { render, onSubmit } = mount();
    expect(await render().submit()).toBe(false);
    expect(onSubmit).not.toHaveBeenCalled();
    let view = render();
    expect(Object.keys(view.issues)).toEqual(["name", "email"]);
    view.setAnswer("name", "Ada");
    view = render();
    expect(Object.keys(view.issues)).toEqual(["email"]);
    view.reset({ name: "Bo" });
    view = render();
    expect(view).toMatchObject({ answers: { name: "Bo" }, issues: {} });
    view.reset();
    expect(render().answers).toEqual({});
  });

  it("files a whole-form issue under an empty key", async () => {
    const { render } = mount({
      form: { definition: SIGNUP, schema: { type: "array" } },
    });
    expect(await render().submit()).toBe(false);
    expect(render().issues).toEqual({ "": ["must be array"] });
  });

  it("clears submitting when onSubmit throws", async () => {
    const { render } = mount({
      initialAnswers: { name: "Ada", email: "ada@example.com" },
      onSubmit: () => Promise.reject(new Error("down")),
    });
    await expect(render().submit()).rejects.toThrow("down");
    expect(render().submitting).toBe(false);
  });
});
