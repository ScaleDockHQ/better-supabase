import type * as ReactModule from "react";

import { formSchema } from "better-supabase/blocks/forms";
import { describe, expect, it, vi } from "vitest";

import { useQuestionnaire } from "../../items/hooks/use-forms.ts";
import { SIGNUP } from "../fixtures/forms.ts";
import { renderHook } from "../fixtures/hook-runtime.ts";

vi.mock(import("react"), async (importOriginal) => {
  const { reactHooks } = await import("../fixtures/hook-runtime.ts");

  return {
    ...(await importOriginal()),
    // SAFETY: the stand-in implements the part of React the hooks call.
    ...(reactHooks as unknown as Partial<typeof ReactModule>),
  };
});

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
    view.result.setAnswer({ key: "email", value: "ada@example.com" });
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
