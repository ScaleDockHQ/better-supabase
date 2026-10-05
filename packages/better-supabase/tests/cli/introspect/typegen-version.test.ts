import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

import { TYPEGEN_VERSION } from "../../../src/cli/introspect/typegen-version.ts";
import { TYPEGEN_MISSING } from "../../../src/cli/introspect/typegen.ts";

const workspace = await readFile(
  resolve(import.meta.dirname, "../../../../../pnpm-workspace.yaml"),
  "utf8",
);
const pins = [
  ...workspace.matchAll(/^\s+"@supabase\/postgrest-typegen": (\S+)$/gm),
].map((match) => match[1]);

describe("the postgrest-typegen pin", () => {
  it("is the exact version in the default and peers catalogs", () => {
    expect(pins).toEqual([TYPEGEN_VERSION, TYPEGEN_VERSION]);
  });

  it("names the pinned version in the install message", () => {
    expect(TYPEGEN_MISSING).toBe(
      `better-supabase needs the "@supabase/postgrest-typegen" package to read your schema and generate types. Install it: pnpm add -D @supabase/postgrest-typegen@${TYPEGEN_VERSION}`,
    );
  });
});
