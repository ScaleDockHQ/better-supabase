import { describe, expect, it } from "vitest";

import type { EntityFormField } from "../../src/list/entity-ui.ts";

import { defineEntityForm } from "../../src/list/entity-ui.ts";

const field = (
  name: string,
  kind: EntityFormField["kind"],
  more: Partial<EntityFormField> = {},
): EntityFormField => ({
  name,
  label: name,
  kind,
  optional: false,
  nullable: false,
  ...more,
});

const form = defineEntityForm({
  entity: "risks.risk",
  fields: [
    field("title", "text", { minLength: 2, maxLength: 5 }),
    field("level", "number", { minimum: 1, maximum: 5, optional: true }),
    field("state", "enum", { values: ["open", "closed"], optional: true }),
    field("owner", "uuid", { optional: true, nullable: true }),
    field("urgent", "boolean"),
    field("meta", "json", { optional: true }),
  ],
});

describe("defineEntityForm", () => {
  it("converts form data to the action input", () => {
    const data = new FormData();

    data.set("title", " Fire ");
    data.set("level", "3");
    data.set("state", "open");
    data.set("owner", "");
    data.set("urgent", "on");
    data.set("meta", '{"a":1}');

    expect(form.parse(data)).toStrictEqual({
      ok: true,
      value: {
        title: "Fire",
        level: 3,
        state: "open",
        owner: null,
        urgent: true,
        meta: { a: 1 },
      },
    });
  });

  it("leaves out an empty optional field and reads an absent box as false", () => {
    expect(form.parse({ title: "Fire" })).toStrictEqual({
      ok: true,
      value: { title: "Fire", owner: null, urgent: false },
    });
  });

  it("names each field that is wrong", () => {
    const result = form.parse({
      title: "x",
      level: "9",
      state: "gone",
      owner: "nope",
      meta: "{",
    });

    expect(result.ok).toBe(false);
    expect(
      result.ok ? [] : result.issues.map((issue) => issue.path?.[0]),
    ).toStrictEqual(["title", "level", "state", "owner", "meta"]);
  });

  it("checks length, number and required", () => {
    expect(form.parse({ title: "toolong" }).ok).toBe(false);
    expect(form.parse({}).ok).toBe(false);
    expect(form.parse({ title: "ok", level: "abc" }).ok).toBe(false);
    expect(form.parse({ title: "ok", level: "0" }).ok).toBe(false);
  });

  it("checks the length of a text field in both directions", () => {
    const text = defineEntityForm({
      entity: "x.y",
      fields: [
        field("note", "date", { minLength: 3, maxLength: 4, optional: true }),
      ],
    });

    expect(text.parse({ note: "ab" }).ok).toBe(false);
    expect(text.parse({ note: "abcde" }).ok).toBe(false);
    expect(text.parse({ note: "abc" }).ok).toBe(true);
  });

  it("checks the upper bound of a number", () => {
    expect(form.parse({ title: "ok", level: "6" }).ok).toBe(false);
    expect(form.parse({ title: "ok", level: "5" }).ok).toBe(true);
  });

  it("keeps the fields it was given", () => {
    expect(form.entity).toBe("risks.risk");
    expect(form.fields).toHaveLength(6);
  });
});
