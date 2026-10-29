import { describe, expect, it } from "vitest";

import {
  CUSTOM_FIELD_FORM_TYPES,
  CUSTOM_FIELD_TYPES,
  FIELD_FORMAT_NAMES,
  FIELD_FORMATS,
} from "../../../src/core/contracts/field-formats.ts";
import { FORM_FIELD_TYPES } from "../../../src/core/contracts/form-definition.ts";

describe("field formats", () => {
  it("describes every format name", () => {
    expect(Object.keys(FIELD_FORMATS).toSorted()).toEqual(
      [...FIELD_FORMAT_NAMES].toSorted(),
    );
  });

  it("answers every format and custom field type with a forms field type", () => {
    const answers = [
      ...Object.values(FIELD_FORMATS).map((format) => format.formType),
      ...Object.values(CUSTOM_FIELD_FORM_TYPES),
    ];

    for (const type of answers) {
      expect(FORM_FIELD_TYPES).toContain(type);
    }

    expect(Object.keys(CUSTOM_FIELD_FORM_TYPES).toSorted()).toEqual(
      [...CUSTOM_FIELD_TYPES].toSorted(),
    );
  });

  it("names a custom field type after the format that holds the same value", () => {
    const shared = CUSTOM_FIELD_TYPES.filter((type) =>
      FIELD_FORMAT_NAMES.some((format) => format === type),
    );

    expect(shared).toEqual([
      "email",
      "url",
      "rating",
      "currency",
      "bsn",
      "iban",
      "phone_e164",
    ]);
  });

  it("checks emails and urls with patterns Postgres and JavaScript agree on", () => {
    const email = new RegExp(FIELD_FORMATS.email.pattern ?? "", "iu");
    const url = new RegExp(FIELD_FORMATS.url.pattern ?? "", "iu");

    expect(email.test("ada@example.com")).toBe(true);
    expect(email.test("ada@example")).toBe(false);
    expect(url.test("https://example.com/a")).toBe(true);
    expect(url.test("ftp://example.com")).toBe(false);
  });
});
