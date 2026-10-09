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
  it("renames the 0.5 event types in string literals only", () => {
    const source = `onBlockEvent(sb, "org.member_added", handle);
onBlockEvent(sb, 'org.*', handle);
const sql = \`select * from outbox_events where type = 'org.switched'\`;
const org = { created: "org.created.v2", key: "my.org.created" };
`;
    expect(applyCodemod(v06, source).text)
      .toBe(`onBlockEvent(sb, "organization.member_added", handle);
onBlockEvent(sb, 'organization.*', handle);
const sql = \`select * from outbox_events where type = 'organization.switched'\`;
const org = { created: "org.created.v2", key: "my.org.created" };
`);
  });

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

  it("lists bucket path calls with values and leaves path strings alone", () => {
    const source = `const path = logos.path({ organizationId, version });
const joined = node.path("a");
const dir = join(root, "path({");
`;
    const result = applyCodemod(v06, source);
    expect(result.text).toBe(source);
    expect(result.review.map((entry) => entry.line)).toEqual([1]);
    expect(result.review[0]?.message).toContain("`path(values)`");
  });

  it("renames kit and org exports and flags the moved subpaths", () => {
    const source = `import { createOrgs, type OrgsOptions } from "better-supabase/orgs";
import { onKitEvent } from "better-supabase/events";
import { createInbox } from "better-supabase/jobs";
const orgs = createOrgs(transport);
onKitEvent(sb, "org.created", handle);
const db = defineSupabase(schema, { maxUrlLength: 4000 });
`;
    const result = applyCodemod(v06, source);
    expect(result.text)
      .toBe(`import { createOrganizations, type OrganizationsOptions } from "better-supabase/orgs";
import { onBlockEvent } from "better-supabase/events";
import { createInbox } from "better-supabase/jobs";
const orgs = createOrganizations(transport);
onBlockEvent(sb, "organization.created", handle);
const db = defineSupabase(schema, { urlLengthLimit: 4000 });
`);
    expect(result.review.map((entry) => entry.line)).toEqual([1, 3, 3]);
  });
});
