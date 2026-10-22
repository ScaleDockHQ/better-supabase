import type * as ReactModule from "react";

import { describe, expect, it, vi } from "vitest";

import { workItemInputSchema } from "../../src/blocks/work-items/schemas.ts";
import { useRecordForm } from "../../src/react/record-form.ts";
import { recordForm } from "../../src/records/record-form.ts";
import { renderHook } from "../fixtures/hook-runtime.ts";

// vi.mock factories run before the imports above, so they load modules themselves.
vi.mock("react", async (importOriginal) => ({
  ...(await importOriginal<typeof ReactModule>()),
  ...(await import("../fixtures/hook-runtime.ts")).reactHooks,
}));

const form = recordForm(workItemInputSchema, {
  fields: ["title", "priority"],
  customFields: [
    { key: "region", label: "Region", type: "text", required: false },
  ],
});

describe("useRecordForm", () => {
  it("holds the values, validates on submit and passes the split values on", async () => {
    const submitted: unknown[] = [];
    let prevented = false;

    const view = renderHook(
      () =>
        useRecordForm(form, {
          initial: { title: "" },
          onSubmit: (values) => {
            submitted.push(values);
          },
        }),
      undefined,
    );

    await view.result.submit();
    expect(view.result.errors["title"]).toEqual(expect.any(String));
    expect(view.result.pending).toBe(false);
    expect(submitted).toEqual([]);

    view.result.set("title", "Ship it");
    view.result.set("priority", "1");
    view.result.set("region", "eu");
    expect(view.result.values).toEqual({
      title: "Ship it",
      priority: "1",
      region: "eu",
    });

    await view.result.submit({
      preventDefault: () => {
        prevented = true;
      },
    });
    expect(prevented).toBe(true);
    expect(view.result.errors).toEqual({});
    expect(view.result.pending).toBe(false);
    expect(submitted).toEqual([
      { input: { title: "Ship it", priority: 1 }, custom: { region: "eu" } },
    ]);

    view.result.reset();
    expect(view.result.values).toEqual({ title: "" });
  });

  it("starts empty without initial values", () => {
    const view = renderHook(
      () => useRecordForm(form, { onSubmit: () => undefined }),
      undefined,
    );

    expect(view.result.values).toEqual({});
    expect(view.result.pending).toBe(false);
  });
});
