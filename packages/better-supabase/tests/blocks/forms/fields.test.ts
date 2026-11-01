import * as v from "valibot";
import { describe, expect, it } from "vitest";

import { createForms } from "../../../src/blocks/forms/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const FORM = {
  id: "f1",
  organizationId: "o",
  key: "signup",
  title: "Sign up",
  status: "draft",
  createdAt: "2026-10-01T09:00:00Z",
  updatedAt: "2026-10-01T09:00:00Z",
  fields: { category: "hr" },
};

const Fields = v.object({ category: v.picklist(["hr", "sales"]) });

describe("forms fields", () => {
  it("sends fields on create and update and parses every read", async () => {
    const t = fieldsTransport({
      create_form: () => FORM,
      update_form: () => FORM,
      list_forms: () => [FORM],
      get_form: () => ({ ...FORM, version: null }),
    });

    const forms = createForms({ transport: t, fields: Fields });

    const created = await forms
      .create({
        organizationId: "o",
        key: "signup",
        title: "Sign up",
        fields: { category: "hr" },
      })
      .orThrow();

    expect(created.fields.category).toBe("hr");
    await forms
      .update({ id: "f1", update: { fields: { category: "sales" } } })
      .orThrow();
    expect((await forms.get("f1").orThrow()).fields.category).toBe("hr");
    expect(
      (await forms.list({ organizationId: "o" }).orThrow()).map(
        (form) => form.fields,
      ),
    ).toEqual([{ category: "hr" }]);
    expect(t.calls.slice(0, 2)).toEqual([
      [
        "create_form",
        {
          tenant: "o",
          key: "signup",
          title: "Sign up",
          description: null,
          fields: { category: "hr" },
        },
      ],
      [
        "update_form",
        {
          form_id: "f1",
          title: null,
          description: null,
          status: null,
          fields: { category: "sales" },
        },
      ],
    ]);
  });

  it("refuses a bad field before the call", async () => {
    const t = fieldsTransport({ create_form: () => FORM });

    const created = await createForms({ transport: t, fields: Fields }).create({
      organizationId: "o",
      key: "signup",
      title: "Sign up",
      fields: { category: "legal" as never },
    });

    expect(created.ok ? undefined : created.error.kind).toBe("validation");
    expect(t.calls).toEqual([]);
  });
});
