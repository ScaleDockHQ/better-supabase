import { describe, expect, it } from "vitest";

import { cliCallHints, rewriteCliCalls } from "../../src/cli/codemod-calls.ts";
import { applyCodemod, CODEMODS } from "../../src/cli/codemod.ts";
import { migrateCliCall } from "../../src/cli/core/moved.ts";

const v09 = CODEMODS["0.9"]!;

describe("rewriteCliCalls", () => {
  it("rewrites package.json scripts and keeps the rest of the line", () => {
    const source = `{
  "name": "app",
  "scripts": {
    "gen": "better-supabase gen --tasks types && next build",
    "check": "pnpm exec bsb doctor --strict",
    "api": "npx better-supabase@0.8 openapi emit --out api.json"
  },
  "dependencies": { "better-supabase": "^0.8.0" }
}
`;

    expect(rewriteCliCalls(source, migrateCliCall)).toBe(`{
  "name": "app",
  "scripts": {
    "gen": "better-supabase gen --only types && next build",
    "check": "pnpm exec bsb doctor --fail-on warning",
    "api": "npx better-supabase@0.8 spec emit openapi --out api.json"
  },
  "dependencies": { "better-supabase": "^0.8.0" }
}
`);
  });

  it("rewrites workflow steps up to a comment", () => {
    const source = `jobs:
  check:
    steps:
      - run: pnpm better-supabase spec check # drift
      - run: pnpm --filter better-supabase gen --tasks x
`;

    expect(rewriteCliCalls(source, migrateCliCall)).toBe(`jobs:
  check:
    steps:
      - run: pnpm better-supabase spec emit --check # drift
      - run: pnpm --filter better-supabase gen --tasks x
`);
  });

  it("rewrites a call that ends the text and skips a bin without arguments", () => {
    expect(rewriteCliCalls("bsb \nbsb doctor --strict", migrateCliCall)).toBe(
      "bsb \nbsb doctor --fail-on warning",
    );
  });

  it("returns the text unchanged when no call moved", () => {
    const source = "better-supabase gen && bsb doctor\n";

    expect(rewriteCliCalls(source, migrateCliCall)).toBe(source);
    expect(cliCallHints(source, migrateCliCall)).toEqual([]);
  });

  it("lists calls in other shell files with the new spelling", () => {
    expect(
      cliCallHints(
        "set -e\nbetter-supabase env --print > .env\n",
        migrateCliCall,
      ),
    ).toEqual([
      {
        line: 2,
        message:
          "This call uses a renamed command or flag: run `better-supabase dev env --out - > .env`",
      },
    ]);
  });
});

describe("codemod 0.9 on scripts", () => {
  it("rewrites package.json and workflows but not source files", () => {
    const script = '{ "scripts": { "d": "better-supabase doctor --strict" } }';

    expect(applyCodemod(v09, script, "apps/web/package.json").text).toContain(
      "doctor --fail-on warning",
    );
    expect(
      applyCodemod(
        v09,
        "run: bsb adopt --from a,b\n",
        ".github/workflows/db.yml",
      ).text,
    ).toBe("run: bsb add --adopt --tables a,b\n");

    const code = 'exec("better-supabase doctor --strict");\n';

    expect(applyCodemod(v09, code, "src/run.ts").text).toBe(code);
  });

  it("lists shell files for review and leaves them as they are", () => {
    const shell = "better-supabase introspect --format snapshot\n";
    const result = applyCodemod(v09, shell, "scripts/ci.sh");

    expect(result.text).toBe(shell);
    expect(result.review).toHaveLength(1);
  });

  it("leaves script files alone in codemods without CLI renames", () => {
    const script = '{ "scripts": { "d": "better-supabase doctor --strict" } }';

    expect(applyCodemod(CODEMODS["0.6"]!, script, "package.json")).toEqual({
      text: script,
      review: [],
    });
  });
});
