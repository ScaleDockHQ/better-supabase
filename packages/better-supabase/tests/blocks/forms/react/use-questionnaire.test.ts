import type * as ReactModule from "react";

import { describe, expect, it, vi } from "vitest";

import { formSchema } from "../../../../src/blocks/forms/index.ts";
import { useQuestionnaire } from "../../../../src/blocks/forms/react/index.ts";
import { renderHook } from "../../../fixtures/hook-runtime.ts";
import { SIGNUP } from "../fixtures.ts";

vi.mock("react", async (importOriginal) => ({
  ...(await importOriginal<typeof ReactModule>()),
  ...(await import("../../../fixtures/hook-runtime.ts")).reactHooks,
}));

const form = { definition: SIGNUP, schema: formSchema(SIGNUP) };

describe("useQuestionnaire", () => {
  it("renders the controller and calls the latest onSubmit", async () => {
    const first = vi.fn();
    const latest = vi.fn();
    const view = renderHook<
      Parameters<typeof useQuestionnaire>[0],
      ReturnType<typeof useQuestionnaire>
    >(useQuestionnaire, {
      form,
      initialAnswers: { name: "Ada" },
      onSubmit: first,
    });
    expect(view.result.answers).toEqual({ name: "Ada" });
    view.result.setAnswer("email", "ada@example.com");
    expect(view.result.answers).toEqual({
      name: "Ada",
      email: "ada@example.com",
    });
    view.rerender({ form, onSubmit: latest });
    expect(await view.result.submit()).toBe(true);
    expect(first).not.toHaveBeenCalled();
    expect(latest).toHaveBeenCalledWith({
      name: "Ada",
      email: "ada@example.com",
    });
    view.unmount();
  });
});
