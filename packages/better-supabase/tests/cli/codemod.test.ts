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
bsb.toORPCError(error);
const name = repository.$table;
const table = db.$table("notes");
`;

    expect(applyCodemod(v04, source).text)
      .toBe(`next.contextForSession(session, { token });
bsb.toOrpcError(error);
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
      `const ctx = await next.server();\napp.get("/", bsb.handle());\nconst x = client.sb;\n`,
    );

    expect(review.map((hint) => hint.line)).toEqual([1, 2, 3]);
    expect(review[0]!.message).toContain("bsb.context()");
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

  it("pins offset pagination where the file reads page numbers", () => {
    const source = `const customers = defineListQuery(betterSupabase, "customers", {
  sorts: { name: { name: "asc" } },
  defaultSort: "name",
});
const notes = defineListQuery(bsb, "notes", { sorts, defaultSort: "new" });
const tags = defineListQuery(bsb, "tags", {});
const kept = defineListQuery(bsb, "tags", { sorts, pagination: "cursor" });
const api = defineResource(bsb, "customers");
const trailing = defineResource(bsb, "notes",);
const listed = defineResource(bsb, "customers", { list: customers });

export const total = (page) => page.page.total;
`;

    const result = applyCodemod(v09, source, "src/lists.ts");

    expect(result.text)
      .toBe(`const customers = defineListQuery(betterSupabase, "customers", {
  pagination: "offset",
  sorts: { name: { name: "asc" } },
  defaultSort: "name",
});
const notes = defineListQuery(bsb, "notes", { pagination: "offset", sorts, defaultSort: "new" });
const tags = defineListQuery(bsb, "tags", { pagination: "offset" });
const kept = defineListQuery(bsb, "tags", { sorts, pagination: "cursor" });
const api = defineResource(bsb, "customers", { pagination: "offset" });
const trailing = defineResource(bsb, "notes", { pagination: "offset" });
const listed = defineResource(bsb, "customers", { list: customers });

export const total = (page) => page.page.total;
`);
    expect(result.review).toEqual([]);
  });

  it("lists the calls it can't pin, and those in files without page numbers", () => {
    const result = applyCodemod(
      v09,
      `const a = defineListQuery(bsb, "customers", { ...shared });
const b = defineListQuery(bsb, "customers", config);
const c = defineResource(bsb, "customers");
const api = defineApi(bsb, { resources: { customers: {} } });
`,
      "src/lists.ts",
    );

    expect(result.text).toContain('defineResource(bsb, "customers");');
    expect(result.review.map((hint) => hint.line)).toEqual([1, 2, 3, 4]);
    expect(result.review[0]!.message).toContain('pagination: "offset"');
    expect(result.review[3]!.message).toContain("defineApi");
  });
});

describe("webhooks-out defaultFormat pin", () => {
  const v09 = CODEMODS["0.9"]!;
  const v011 = CODEMODS["0.11"]!;
  const file = "/app/better-supabase.config.ts";

  const adopted = (inner: string) => `export default defineConfig({
  blocks: {
    "webhooks-out": {
      mode: "adopt",
${inner}    },
  },
});
`;

  it("pins standard with 0.9 and cloudevents with 0.11, and lists the edit", () => {
    const source = adopted(
      '      tables: { endpoints: "public.hooks" },\n      options: { retries: 3 },\n',
    );

    const v9 = applyCodemod(v09, source, file);
    expect(v9.text).toContain('defaultFormat: "standard"');
    expect(v9.review).toEqual([
      expect.objectContaining({
        line:
          v9.text
            .split("\n")
            .findIndex((line) => line.includes("defaultFormat")) + 1,
        message: expect.stringContaining('"standard"'),
      }),
    ]);

    const v11 = applyCodemod(v011, source, file);
    expect(v11.text).toContain('defaultFormat: "cloudevents"');
    expect(applyCodemod(v011, v11.text, file).text).toBe(v11.text);
  });

  it("adds options when the block has none", () => {
    const result = applyCodemod(v011, adopted(""), file);
    expect(result.text).toMatch(
      /options: \{\s*defaultFormat: "cloudevents",?\s*\}/,
    );
  });

  it("leaves a block that maps a format column, sets the format or isn't adopted", () => {
    for (const source of [
      adopted('      columns: { endpoints: { format: "body_format" } },\n'),
      adopted('      options: { defaultFormat: "standard" },\n'),
      adopted("").replace('mode: "adopt"', 'mode: "install"'),
    ]) {
      const result = applyCodemod(v011, source, file);
      expect(result.text).toBe(source);
      expect(result.review).toEqual([]);
    }
  });

  it("pins in a JSON config", () => {
    const result = applyCodemod(
      v011,
      JSON.stringify({ blocks: { "webhooks-out": { mode: "adopt" } } }),
      "better-supabase.config.json",
    );

    expect(JSON.parse(result.text)).toEqual({
      blocks: {
        "webhooks-out": {
          mode: "adopt",
          options: { defaultFormat: "cloudevents" },
        },
      },
    });
    expect(result.review).toHaveLength(1);
  });
});

describe("sql add hint", () => {
  it("lists sql add calls in scripts and shell files with 0.9", () => {
    const v09 = CODEMODS["0.9"]!;

    const scripts = JSON.stringify(
      {
        scripts: {
          blocks: "better-supabase sql add teams",
          gen: "better-supabase gen",
        },
      },
      null,
      2,
    );

    const result = applyCodemod(v09, scripts, "/app/package.json");
    expect(result.review).toEqual([
      expect.objectContaining({
        line: 3,
        message: expect.stringContaining("`add`"),
      }),
    ]);
    expect(
      applyCodemod(v09, "bsb sql add teams\n", "/app/scripts/setup.sh").review,
    ).toEqual([
      expect.objectContaining({ line: 1 }),
      expect.objectContaining({ line: 1 }),
    ]);
  });
});

describe("codemod 0.15", () => {
  const v015 = CODEMODS["0.15"]!;

  it("runs a script once when sql sync and sql upgrade both become upgrade", () => {
    const scripts = (entries: Record<string, string>) =>
      JSON.stringify({ scripts: entries }, null, 2);

    expect(
      applyCodemod(
        v015,
        scripts({
          "gen:check":
            "better-supabase gen --check && better-supabase sql sync --check && better-supabase sql upgrade --check && tsc --noEmit",
          "sql:regenerate":
            "better-supabase sql sync && better-supabase sql upgrade",
        }),
        "/app/package.json",
      ).text,
    ).toBe(
      scripts({
        "gen:check":
          "better-supabase gen --check && better-supabase upgrade --check && tsc --noEmit",
        "sql:regenerate": "better-supabase upgrade",
      }),
    );
  });

  it("runs a workflow step once and keeps different calls", () => {
    const workflow = (run: string) =>
      `jobs:\n  check:\n    steps:\n      - run: ${run}\n`;

    expect(
      applyCodemod(
        v015,
        workflow(
          "pnpm better-supabase sql sync --check && pnpm better-supabase sql upgrade --check",
        ),
        "/app/.github/workflows/ci.yml",
      ).text,
    ).toBe(workflow("pnpm better-supabase upgrade --check"));
    expect(
      applyCodemod(
        v015,
        workflow("pnpm bsb sql sync && pnpm bsb sql upgrade --check"),
        "/app/.github/workflows/ci.yml",
      ).text,
    ).toBe(workflow("pnpm bsb upgrade && pnpm bsb upgrade --check"));
  });

  it("renames the module, subject, carrier and backend exports", () => {
    const source = `import type { SqlModule, ModuleContext, SubjectRef } from "better-supabase/sql";
import type { ShipmentCarrier } from "better-supabase/blocks/shipments";
import { sqlQueueBackend, type QueueBackend } from "better-supabase/jobs";

const ref: SubjectRef = { type: "customer", id };
`;

    expect(applyCodemod(v015, source).text)
      .toBe(`import type { BlockSql, BlockSqlContext, RecordRef } from "better-supabase/sql";
import type { ShippingProvider } from "better-supabase/blocks/shipments";
import { sqlQueueProvider, type QueueProvider } from "better-supabase/jobs";

const ref: RecordRef = { type: "customer", id };
`);
  });

  it("renames generateFeatures to gen.recordTypes", () => {
    const result = applyCodemod(
      v015,
      `export default defineConfig({ generateFeatures: false });\n`,
      "/app/better-supabase.config.ts",
    );

    expect(result.text).toContain("recordTypes: false");
    expect(result.text).not.toContain("generateFeatures");
  });

  it("renames requireTenant to requireTenant", () => {
    const source = `import { bsb } from "@/lib/supabase";

export const run = bsb.action(handler, { requireTenant: true });
`;

    expect(applyCodemod(v015, source).text).toContain(
      "{ requireTenant: true }",
    );
  });

  it("renames the record section exports to record bindings", () => {
    const source = `import { defineSection, loadSections } from "better-supabase/records";
import { commentsSection } from "better-supabase/blocks/comments";

const notes = defineSection({ load });
await loadSections(source, subject, ["comments"]);
`;

    expect(applyCodemod(v015, source).text)
      .toBe(`import { defineRecordBinding, loadBindings } from "better-supabase/records";
import { commentsBinding } from "better-supabase/blocks/comments";

const notes = defineRecordBinding({ load });
await loadBindings(source, subject, ["comments"]);
`);
  });

  it("lists record feature imports and sectionAction calls for review", () => {
    const source = `import { customerRecord } from "@/lib/supabase/features/customer/customer-server";
export const remove = bsb.sectionAction(attachmentsBlock, "remove");
`;

    const { review } = applyCodemod(v015, source);
    expect(review.map((line) => line.line)).toEqual([1, 2]);
    expect(review[0]?.message).toContain("bsb.record");
  });

  it("lists the removed leases maintenance calls for review", () => {
    const source = `await leases.fileMaintenance({ unitId, title: "Tap" });
`;

    const { review } = applyCodemod(v015, source);
    expect(review[0]?.message).toContain("tasks instance");
  });

  it("moves block query keys into the bsb key space", () => {
    const source = `queryClient.invalidateQueries({ queryKey: ["bs-block", "tasks"] });
const owner = query.meta?.bsBlock;
`;

    const result = applyCodemod(v015, source);
    expect(result.text).toContain(`queryKey: ["bsb", "tasks"]`);
    expect(result.review.some((line) => line.message.includes("bsBlock"))).toBe(
      true,
    );
  });

  it("renames the bs instance where a file creates or imports it", () => {
    const created = `import { createNext } from "better-supabase/next";
import { betterSupabase } from "@/lib/supabase";

export const bs = createNext(betterSupabase);
const note = "bs stays in strings"; // and bs in comments
`;

    expect(applyCodemod(v015, created).text)
      .toBe(`import { createNext } from "better-supabase/next";
import { betterSupabase } from "@/lib/supabase";

export const bsb = createNext(betterSupabase);
const note = "bs stays in strings"; // and bs in comments
`);

    const imported = `import { bs } from "@/lib/supabase/server";

export async function load() {
  const { db } = await bs.context();
  return ctx.bs.auth;
}
`;

    expect(applyCodemod(v015, imported).text)
      .toBe(`import { bsb } from "@/lib/supabase/server";

export async function load() {
  const { db } = await bsb.context();
  return ctx.bsb.auth;
}
`);
  });

  it("leaves a bs the file neither declares nor imports", () => {
    const source = `import { thing } from "./local";

const bs = 1;
`;

    expect(applyCodemod(v015, source).text).toBe(source);
  });

  it("renames block subpaths and the exports named after a block", () => {
    const source = `import { createWorkItems, workItemsBlock } from "better-supabase/blocks/work-items";
import { useAccess } from "better-supabase/blocks/access/react";
import { createRules as rules } from "better-supabase/blocks/rules";

const items = createWorkItems(db);
`;

    expect(applyCodemod(v015, source).text)
      .toBe(`import { createTasks, tasksBlock } from "better-supabase/blocks/tasks";
import { useAccess } from "better-supabase/blocks/permissions/react";
import { createAutomations as rules } from "better-supabase/blocks/automations";

const items = createTasks(db);
`);
  });

  it("moves the renderer subpath imports to better-supabase/spec", () => {
    const source = `import { createOpenApi } from "better-supabase/openapi";
import type { AsyncApiOptions } from "better-supabase/asyncapi";
import { defineWorkflow } from 'better-supabase/arazzo';
import { applyOverlays, loadJsonPath } from "better-supabase/overlay";
`;

    expect(applyCodemod(v015, source).text)
      .toBe(`import { createOpenApi } from "better-supabase/spec";
import type { AsyncApiOptions } from "better-supabase/spec";
import { defineWorkflow } from 'better-supabase/spec';
import { applyOverlays, loadJsonPath } from "better-supabase/spec";
`);
  });

  it("moves the plugin imports onto the blocks, lint and the root", () => {
    const source = `import { tenant } from "better-supabase/plugins/tenant";
import { softDelete } from "better-supabase/plugins/soft-delete";
import { rules, strict } from "better-supabase/plugins/rules";
import { validation } from "better-supabase/plugins/validation";

const db = defineSupabase(schema)
  .use(tenant({ claim: "org_id" }))
  .use(softDelete())
  .use(rules(strict()))
  .use(validation({ schemas }));
`;

    const { text, review } = applyCodemod(v015, source);

    expect(text)
      .toBe(`import { membershipsExtension } from "better-supabase/blocks/memberships";
import { trashExtension } from "better-supabase/blocks/trash";
import { guards, strictGuards } from "better-supabase/lint";
import { validation } from "better-supabase";

const db = defineSupabase(schema)
  .use(membershipsExtension({ claim: "org_id" }))
  .use(trashExtension())
  .use(guards(strictGuards()))
  .use(validation({ schemas }));
`);
    expect(review.map((hint) => hint.line)).toEqual(
      expect.arrayContaining([7, 8, 10]),
    );
  });

  it("moves the plugins config key onto the blocks", () => {
    const source = `import { defineConfig } from "better-supabase/config";

export default defineConfig({
  plugins: { softDelete: { column: "archived_at" }, actor: true },
});
`;

    const { text } = applyCodemod(
      v015,
      source,
      "/app/better-supabase.config.ts",
    );

    expect(text).not.toContain("plugins");
    expect(text).toMatch(/trash: \{[^}]*deletedAt: "archived_at"/s);
    expect(text).toContain('"created-by"');
  });

  it("renames blocks, preset blocks and operations in the config", () => {
    const source = `import { defineConfig } from "better-supabase/config";

export default defineConfig({
  preset: { blocks: ["work-items", "audit"] },
  blocks: {
    "work-items": { ownership: "owned" },
    rules: true,
  },
  auth: {
    authorization: { operations: { "jobs.manage": "owner", "audit.read": "admin" } },
  },
});
`;

    expect(applyCodemod(v015, source, "/app/better-supabase.config.ts").text)
      .toBe(`import { defineConfig } from "better-supabase/config";

export default defineConfig({
  preset: { blocks: ["tasks", "audit"] },
  blocks: {
    "tasks": { ownership: "owned" },
    automations: true,
  },
  auth: {
    authorization: { operations: { "queue.manage": "owner", "audit.read": "admin" } },
  },
});
`);
  });

  it("renames block names in a JSON config", () => {
    const source = `${JSON.stringify({ blocks: ["jobs", "audit"], preset: { blocks: ["access"] } }, null, 2)}\n`;

    const { text } = applyCodemod(
      v015,
      source,
      "/app/better-supabase.config.json",
    );

    expect(JSON.parse(text)).toEqual({
      blocks: ["queue", "audit"],
      preset: { blocks: ["permissions"] },
    });
  });

  it("lists event source filters for review", () => {
    const { review } = applyCodemod(
      v015,
      `if (event.source === "better-supabase/work-items") {}\n`,
    );

    expect(review.map((line) => line.message)).toEqual([
      expect.stringContaining("Event sources"),
    ]);
  });

  it("lists cache tags and the debug route for review", () => {
    const { review } = applyCodemod(
      v015,
      `revalidateTag("bs:customers");\nfetch("/api/bs-stats");\n`,
    );

    expect(review.map((line) => line.line)).toEqual([1, 2]);
  });
});
