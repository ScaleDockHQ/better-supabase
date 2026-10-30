import { describe, expect, it } from "vitest";

import { applyCodemod, CODEMODS } from "../../src/cli/codemod.ts";

const v046 = CODEMODS["0.46"]!;

describe("codemod 0.46", () => {
  it("renames permission keys in strings, outside code", () => {
    const source = `import { can } from "better-supabase/blocks/permissions";

// parties.read stays in prose
const roles = { sales: ["parties.read", "rules.edit", 'support.start'] };
if (can(set, \`controls.manage\`)) show();
const name = parties.read;
`;

    expect(applyCodemod(v046, source, "src/roles.ts").text)
      .toBe(`import { can } from "better-supabase/blocks/permissions";

// parties.read stays in prose
const roles = { sales: ["contacts.read", "automations.write", 'impersonation.start'] };
if (can(set, \`compliance.manage\`)) show();
const name = parties.read;
`);
  });

  it("lists the split and ambiguous keys instead of guessing", () => {
    const source = `const a = can(set, "ai.read");
const b = can(set, "workflow.run");
onBlockEvent("support.*", handler);
const c = can(set, "members.invite");
const d = can(set, "parties.read");
`;

    const result = applyCodemod(v046, source, "src/checks.ts");

    expect(result.text).toContain('"ai.read"');
    expect(result.text).toContain('"workflow.run"');
    expect(result.text).toContain('"support.*"');
    expect(result.review.map((line) => line.line)).toEqual([1, 2, 3, 4]);
  });

  it("renames the oauth-server block's OAuth names", () => {
    const source = `import { createOAuthServer, type OAuthClient } from "better-supabase/blocks/oauth-server";

export const server = createOAuthServer(bsb);
export type Client = OAuthClient;
`;

    expect(applyCodemod(v046, source, "src/oauth.ts").text)
      .toBe(`import { createOauthServer, type OauthClient } from "better-supabase/blocks/oauth-server";

export const server = createOauthServer(bsb);
export type Client = OauthClient;
`);
  });

  it("renames the keys in the app's own SQL", () => {
    const source = `create policy p on public.notes
  using (better_supabase.can('tenant', tenant_id, 'engagements.read'));
select better_supabase.tenant_ids_with('ai.read');
`;

    const result = applyCodemod(v046, source, "supabase/schemas/notes.sql");

    expect(result.text).toContain("'activities.read'");
    expect(result.text).toContain("'ai.read'");
    expect(result.review).toEqual([
      { line: 3, message: expect.stringContaining("one area per AI block") },
    ]);
  });

  it("lists postmortem action items and AI document versions for review", () => {
    const source = `await incidents.savePostmortem(id, { actionItems });
const notes = 1;
select * from better_supabase.ai_document_versions;
`;

    const result = applyCodemod(v046, source, "src/postmortems.ts");

    expect(result.text).toBe(source);
    expect(result.review).toEqual([
      { line: 1, message: expect.stringContaining("addPostmortemAction") },
      { line: 3, message: expect.stringContaining("versions table") },
    ]);
  });
});
