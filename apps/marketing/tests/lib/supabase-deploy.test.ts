import { encodePreset, namedPreset } from "better-supabase/preset";
import { describe, expect, test } from "vitest";

import { previewFiles } from "../../lib/preview-provider";
import {
  deployBlocker,
  deployQuery,
  generatePassword,
  suggestedProjectName,
} from "../../lib/supabase-deploy";

describe("deployQuery", () => {
  const files = [
    { path: "supabase/tests/900_x.test.sql", module: "x", contents: "test" },
    {
      path: "supabase/better-supabase-data/900_x.sql",
      module: "x",
      contents: "data",
    },
    { path: "supabase/schemas/900_a.sql", module: "a", contents: "schema a" },
    { path: "supabase/schemas/901_b.sql", module: "b", contents: "schema b" },
  ];

  test("puts schema files before data files and leaves tests out", () => {
    expect(deployQuery(files)).toBe(
      [
        "-- supabase/schemas/900_a.sql\nschema a\n",
        "-- supabase/schemas/901_b.sql\nschema b\n",
        "-- supabase/better-supabase-data/900_x.sql\ndata\n",
      ].join("\n"),
    );
  });

  test("renders a preset's schema", () => {
    const query = deployQuery(previewFiles(encodePreset(namedPreset("saas"))));

    expect(query).toContain("create table");
    expect(query).not.toContain("plan(");
  });
});

test("deployBlocker blocks provider access only", () => {
  const preset = namedPreset("saas");

  expect(deployBlocker(preset)).toBeUndefined();
  expect(deployBlocker({ ...preset, access: "provider" })).toContain(
    "authorization provider",
  );
});

test("generatePassword returns 32 base64url characters", () => {
  const password = generatePassword();

  expect(password).toMatch(/^[\w-]{32}$/u);
  expect(generatePassword()).not.toBe(password);
});

test("suggestedProjectName uses the preset name", () => {
  expect(suggestedProjectName("saas")).toBe("my-saas-app");
  expect(suggestedProjectName(undefined)).toBe("my-app");
});
