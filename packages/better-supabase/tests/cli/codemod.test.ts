import { describe, expect, it } from "vitest";

import { applyCodemod, CODEMODS, codeRanges } from "../../src/cli/codemod.ts";

const v04 = CODEMODS["0.4"]!;
const v05 = CODEMODS["0.5"]!;
const v06 = CODEMODS["0.6"]!;

describe("codeRanges", () => {
  it("leaves out strings, template literals and comments", () => {
    const text = `a "b\\"c" d 'e' \`f\` // g\nh /* i */ j`;
    expect(
      codeRanges(text)
        .map(([start, end]) => text.slice(start, end))
        .join("|"),
    ).toBe(`a | d | | |\nh | j`);
  });

  it("ends an unterminated string at the end of its line", () => {
    const text = `a "b\nc`;
    expect(codeRanges(text).map(([s, e]) => text.slice(s, e))).toEqual([
      "a ",
      "\nc",
    ]);
  });
});

describe("codemod 0.4", () => {
  it("renames imports from better-supabase and their uses", () => {
    const source = `import { createBrowser, type BetterBrowser } from "better-supabase/react";
import { Postgres as PG, createPostgres } from "better-supabase/postgres";
import type { Queries } from "./local";
export { BetterEnv } from "better-supabase/hono";

const client: BetterBrowser = createBrowser(betterSupabase);
const pg: PG = createPostgres();
const note = "createBrowser stays in strings"; // and createBrowser in comments
type Q = Queries;
obj.createBrowser();
`;
    expect(applyCodemod(v04, source).text)
      .toBe(`import { createClient, type BetterClient } from "better-supabase/react";
import { BetterPostgres as PG, createPostgres } from "better-supabase/postgres";
import type { Queries } from "./local";
export { HonoEnv } from "better-supabase/hono";

const client: BetterClient = createClient(betterSupabase);
const pg: PG = createPostgres();
const note = "createBrowser stays in strings"; // and createBrowser in comments
type Q = Queries;
obj.createBrowser();
`);
  });

  it("renames members, keeping db.$table(name)", () => {
    const source = `next.serverFor(session, { token });
bs.toORPCError(error);
const name = repository.$table;
const table = db.$table("notes");
`;
    expect(applyCodemod(v04, source).text)
      .toBe(`next.contextForSession(session, { token });
bs.toOrpcError(error);
const name = repository.$tableName;
const table = db.$table("notes");
`);
  });

  it("renames the provider's browser prop", () => {
    const source = `<BetterSupabaseProvider onError={(e) => e > 1} browser={browser}>
  <Other browser={browser} />
</BetterSupabaseProvider>`;
    expect(applyCodemod(v04, source).text)
      .toBe(`<BetterSupabaseProvider onError={(e) => e > 1} client={browser}>
  <Other browser={browser} />
</BetterSupabaseProvider>`);
  });

  it("lists the changes it leaves for review", () => {
    const { review } = applyCodemod(
      v04,
      `const ctx = await next.server();\napp.get("/", bs.handle());\nconst x = client.sb;\n`,
    );
    expect(review.map((hint) => hint.line)).toEqual([1, 2, 3]);
    expect(review[0]!.message).toContain("bs.context()");
  });
});

describe("codemod 0.5", () => {
  it("renames createMcp's scopes key at the top level of the options", () => {
    const source = `const mcp = createMcp(betterSupabase, {
  name: "crm",
  scopes: ["read"],
  tools: { scopes: 1 },
  description: scopes,
});
const short = createMcp(betterSupabase, { scopes, other });
other({ scopes: [] });
`;
    expect(applyCodemod(v05, source).text)
      .toBe(`const mcp = createMcp(betterSupabase, {
  name: "crm",
  advertisedScopes: ["read"],
  tools: { scopes: 1 },
  description: scopes,
});
const short = createMcp(betterSupabase, { advertisedScopes: scopes, other });
other({ scopes: [] });
`);
  });

  it("leaves a file without matches as it is", () => {
    const source = "const value = 1;\n";
    expect(applyCodemod(v05, source)).toEqual({ text: source, review: [] });
  });
});

describe("codemod 0.6", () => {
  it("lists $rpc calls for review and changes nothing", () => {
    const source = `const rows = await db.$rpc("list_customers", {}).orThrow();
const typed = db.$rpc<"x">("x");
const label = "$rpc in a string";
`;
    const result = applyCodemod(v06, source);
    expect(result.text).toBe(source);
    expect(result.review.map((entry) => entry.line)).toEqual([1, 2]);
    expect(result.review[0]?.message).toContain("raw: true");
  });

  it("lists bucket publicUrl calls and leaves the webhook helper alone", () => {
    const source = `const url = storage.publicUrl(path);
const allow = publicUrl({ allowHosts: [] });
`;
    const result = applyCodemod(v06, source);
    expect(result.text).toBe(source);
    expect(result.review.map((entry) => entry.line)).toEqual([1]);
    expect(result.review[0]?.message).toContain("Result");
  });
});
