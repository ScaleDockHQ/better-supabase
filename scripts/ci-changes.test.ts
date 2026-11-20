import { describe, expect, it } from "vitest";

import { classify } from "./ci-changes.ts";

const NONE = { stack: false, docs: false, vite: false };

describe("classify", () => {
  it("turns nothing on for paths no gated job reads", () => {
    expect(
      classify(["apps/marketing/app/page.tsx", "docs/agents/ci.md"]),
    ).toEqual(NONE);
    expect(classify([])).toEqual(NONE);
  });

  it("maps the library to every job", () => {
    expect(classify(["packages/better-supabase/src/core/define.ts"])).toEqual({
      stack: true,
      docs: true,
      vite: true,
    });
  });

  it("maps a docs page to the docs build only", () => {
    expect(classify(["apps/docs/content/docs/index.mdx"])).toEqual({
      ...NONE,
      docs: true,
    });
  });

  it("maps the schema and the stack action to the stack only", () => {
    expect(classify(["supabase/schemas/a.sql"])).toEqual({
      ...NONE,
      stack: true,
    });
    expect(classify([".github/actions/supabase-stack/action.yml"])).toEqual({
      ...NONE,
      stack: true,
    });
  });

  it("keeps a workflow edit from turning anything on, except ci.yml", () => {
    expect(classify([".github/workflows/database.yml"])).toEqual(NONE);
    expect(classify([".github/workflows/ci.yml"])).toEqual({
      ...NONE,
      stack: true,
    });
  });

  it("turns everything on for the lockfile and for an unknown path", () => {
    const all = { stack: true, docs: true, vite: true };

    expect(classify(["pnpm-lock.yaml"])).toEqual(all);
    expect(classify(["somewhere/new/file.ts"])).toEqual(all);
  });
});
