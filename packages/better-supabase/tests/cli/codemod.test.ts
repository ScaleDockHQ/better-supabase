import { describe, expect, it } from "vitest";

import { applyCodemod, CODEMODS } from "../../src/cli/codemod.ts";

const v04 = CODEMODS["0.4"]!;
const v05 = CODEMODS["0.5"]!;
const v06 = CODEMODS["0.6"]!;

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

describe("codemod 0.9", () => {
  const v09 = CODEMODS["0.9"]!;

  it("lists the behaviour changes for review", () => {
    const source = [
      'import { supportSessions } from "better-supabase/server";',
      "const support = supportSessions({ store });",
      'const functions = { canApprove: "authz.can_approve({tool}, {tenant})" };',
      "const webhooks = createWebhooks({ transform });",
      "gatewayOptions(context, { user: id });",
      'expect(body.type).toBe("https://bettersupabase.com/problems/forbidden");',
      "const ok = 1;",
    ].join("\n");

    const result = applyCodemod(v09, source);
    expect(result.text).toBe(source);
    expect(result.review.map((entry) => entry.line)).toEqual([2, 3, 4, 5, 6]);
  });

  it("lists the access, workflow and delivery changes for review", () => {
    const source = [
      "const policy = sql`using (better_supabase.token_scope_allows('posts:write'))`;",
      "const ids = sql`select public.member_organization_ids()`;",
      "const start = workflowStarter({ digest }, { runAs });",
      "const builder = createBuilder({ transport });",
      "const notifications = createNotifications({ transport });",
      "await inbox.fanOut(admin, options);",
      'const act = { kind: "agent", sub, tools };',
      "const link = sql`select better_supabase.create_share_link($1, $2, $3, $4)`;",
      "const hook = sql`create function public.before_promotion_activate(promotion uuid)`;",
      "const modules = { comments: { options: {} } };",
      "const ok = 1;",
    ].join("\n");

    const result = applyCodemod(v09, source);
    expect(result.text).toBe(source);
    expect(result.review.map((entry) => entry.line)).toEqual([
      1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
    ]);
    expect(result.review[2]?.message).toContain("runAs");
  });

  it("renames the config types", () => {
    const source = [
      'import type { ModulesConfig, ModuleMode as Mode } from "better-supabase/config";',
      "const blocks: ModulesConfig = {};",
      "let mode: Mode;",
    ].join("\n");

    expect(applyCodemod(v09, source).text).toBe(
      [
        'import type { BlocksConfig, BlockMode as Mode } from "better-supabase/config";',
        "const blocks: BlocksConfig = {};",
        "let mode: Mode;",
      ].join("\n"),
    );
  });

  it("moves sql.modules to blocks only in the config file", () => {
    const source = `export default defineConfig({
  sql: {
    modules: { tenant: true },
  },
});
`;

    const config = applyCodemod(v09, source, "/app/better-supabase.config.ts");

    expect(config.text).toBe(`export default defineConfig({
  blocks: { tenant: true },
});
`);
    expect(
      applyCodemod(v09, config.text, "better-supabase.config.ts").text,
    ).toBe(config.text);
    expect(applyCodemod(v09, source, "/app/src/config.ts").text).toBe(source);
    expect(
      applyCodemod(
        v09,
        `{ "sql": { "modules": ["tenant"] } }`,
        "better-supabase.config.json",
      ).text,
    ).toBe(`{\n  "blocks": [\n    "tenant"\n  ]\n}\n`);
  });

  it("lists a config it can't rewrite", () => {
    const result = applyCodemod(
      v09,
      `export default defineConfig({ sql: { modules: [] }, blocks: [] });`,
      "better-supabase.config.ts",
    );

    expect(result.review).toEqual([
      { line: 1, message: expect.stringContaining("merge `sql.modules`") },
    ]);
  });

  it("lists sql.modules left in an environment block", () => {
    const result = applyCodemod(
      v09,
      `export default defineConfig({
  sql: { modules: ["tenant"] },
  $production: { sql: { modules: ["tenant", "access"] } },
});
`,
      "better-supabase.config.ts",
    );

    expect(result.text).toContain('  blocks: ["tenant"],');
    expect(result.review).toEqual([
      { line: 3, message: expect.stringContaining("environment block") },
    ]);
  });
});
