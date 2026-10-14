import { beforeEach, describe, expect, it, vi } from "vitest";

import { formSchema } from "../../../../src/blocks/forms/index.ts";
import { SIGNUP } from "../fixtures.ts";

/** One component's hook slots; `render` replays the hooks in call order. */
const slots: unknown[] = [];
let cursor = 0;

vi.mock("react", () => {
  const slot = <T>(init: () => T): [number, T] => {
    const at = cursor++;
    if (!(at in slots)) slots[at] = init();
    // SAFETY: each slot holds the value its hook stored on the first render.
    return [at, slots[at] as T];
  };
  return {
    useState: <T>(initial: T) => {
      const [at, value] = slot(() => initial);
      return [
        value,
        (next: T | ((current: T) => T)) => {
          // SAFETY: the slot holds this hook's state.
          const current = slots[at] as T;
          slots[at] =
            typeof next === "function" ? (next as (c: T) => T)(current) : next;
        },
      ];
    },
    useReducer: <S, A, I>(
      reducer: (s: S, a: A) => S,
      arg: I,
      init: (arg: I) => S,
    ) => {
      const [at, value] = slot(() => init(arg));
      // SAFETY: the slot holds this hook's state.
      return [
        value,
        (action: A) => (slots[at] = reducer(slots[at] as S, action)),
      ];
    },
    useMemo: <T>(fn: () => T) => fn(),
    useCallback: <T>(fn: T) => fn,
  };
});

const { useQuestionnaire } =
  await import("../../../../src/blocks/forms/react/index.ts");

const form = { definition: SIGNUP, schema: formSchema(SIGNUP) };
/** Called as a value, as a component render would call it. */
const questionnaire = useQuestionnaire;

function mount(options: Partial<Parameters<typeof questionnaire>[0]> = {}) {
  const onSubmit = vi.fn();
  const render = () => {
    cursor = 0;
    return questionnaire({ form, onSubmit, ...options });
  };
  return { render, onSubmit };
}

beforeEach(() => {
  slots.length = 0;
});

describe("useQuestionnaire", () => {
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
