import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

import { TYPEGEN_VERSION } from "../../../src/cli/introspect/typegen-version.ts";
import {
  TYPEGEN_MISSING,
  typegenVersion,
  typegenVersionNotice,
} from "../../../src/cli/introspect/typegen.ts";
import { satisfies } from "../../../src/cli/peers.ts";

const workspace = await readFile(
  resolve(import.meta.dirname, "../../../../../pnpm-workspace.yaml"),
  "utf8",
);
const pins = [
  ...workspace.matchAll(/^\s+"@supabase\/postgrest-typegen": (\S.*)$/gm),
].map((match) => match[1]!.replaceAll('"', ""));

describe("the postgrest-typegen pin", () => {
  it("is exact in the default catalog and a range around it in the peers catalog", () => {
    const [catalog, peer] = pins;
    expect(pins).toHaveLength(2);
    expect(catalog).toBe(TYPEGEN_VERSION);
    expect(peer).not.toBe(TYPEGEN_VERSION);
    expect(satisfies(TYPEGEN_VERSION, peer!)).toBe(true);
  });

  it("names the pinned version in the install message", () => {
    expect(TYPEGEN_MISSING).toBe(
      `better-supabase needs the "@supabase/postgrest-typegen" package to read your schema and generate types. Install it: pnpm add -D @supabase/postgrest-typegen@${TYPEGEN_VERSION}`,
    );
  });

  it("reads the installed release", async () => {
    expect(await typegenVersion()).toBe(TYPEGEN_VERSION);
  });

  it("prints a notice only for another release", () => {
    expect(typegenVersionNotice(TYPEGEN_VERSION)).toBeUndefined();
    expect(typegenVersionNotice(undefined)).toBeUndefined();
    expect(typegenVersionNotice("0.4.1")).toBe(
      `Notice: @supabase/postgrest-typegen@0.4.1 is installed; this better-supabase release is tested against ${TYPEGEN_VERSION}. database.types.ts can differ from \`supabase gen types\` output until both use the same release. Pin it: pnpm add -D @supabase/postgrest-typegen@${TYPEGEN_VERSION}`,
    );
  });
});
