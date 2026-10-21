import { describe, expect, test } from "vitest";

import {
  previewFiles,
  deployBlocker,
  deployQuery,
  generatePassword,
  newDeployId,
  suggestedProjectName,
} from "../../src/create/index.ts";
import { encodePreset, namedPreset } from "../../src/preset/index.ts";

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

  test("writes the deploy id on the first line", () => {
    const id = newDeployId();
    const query = deployQuery(files, { id });

    expect(query.split("\n")[0]).toBe(`-- better-supabase deploy ${id}`);
    expect(query.endsWith(deployQuery(files))).toBe(true);
  });

  test.each(["", "a\nselect 1;", "a b", "x".repeat(65)])(
    "rejects the id %j",
    (id) => {
      expect(() => deployQuery(files, { id })).toThrow(TypeError);
    },
  );
});

test("newDeployId returns a fresh UUID", () => {
  const id = newDeployId();

  expect(id).toMatch(
    /^[\da-f]{8}-[\da-f]{4}-4[\da-f]{3}-[89ab][\da-f]{3}-[\da-f]{12}$/u,
  );
  expect(newDeployId()).not.toBe(id);
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
