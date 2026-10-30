import { describe, expect, it } from "vitest";

import { applyCodemod, CODEMODS } from "../../src/cli/codemod.ts";

const v047 = CODEMODS["0.47"]!;

describe("codemod 0.47", () => {
  it("renames entity keys by the block each entry installs", () => {
    const source = `import { defineConfig } from "better-supabase/config";

export default defineConfig({
  blocks: {
    tasks: { entities: { work_item: { name: "ticket" }, project: "initiative" } },
    // work_item stays in a comment
    support: { block: "tasks", entities: { "work_item": "case" } },
    leave: { entities: { request: "absence", type: "absence_kind" } },
    "access-requests": { entities: { request: "join_request" } },
  },
});
`;

    const result = applyCodemod(v047, source, "better-supabase.config.ts");

    expect(result.text)
      .toBe(`import { defineConfig } from "better-supabase/config";

export default defineConfig({
  blocks: {
    tasks: { entities: { task: { name: "ticket" }, project: "initiative" } },
    // work_item stays in a comment
    support: { block: "tasks", entities: { "task": "case" } },
    leave: { entities: { leave_request: "absence", leave_type: "absence_kind" } },
    "access-requests": { entities: { access_request: "join_request" } },
  },
});
`);
    expect(result.review).toEqual([]);
  });

  it("renames entity keys in a JSON config", () => {
    const source = `{
  "blocks": { "goals": { "entities": { "target": "objective" } } }
}
`;

    expect(applyCodemod(v047, source, "better-supabase.config.json").text)
      .toBe(`{
  "blocks": { "goals": { "entities": { "goal": "objective" } } }
}
`);
  });

  it("lists an entry that sets the old and the new key", () => {
    const source = `export default defineConfig({
  blocks: { tasks: { entities: { task: "ticket", work_item: "case" } } },
});
`;

    const result = applyCodemod(v047, source, "better-supabase.config.ts");

    expect(result.text).toBe(source);
    expect(result.review).toEqual([
      { line: 2, message: expect.stringContaining("keep task") },
    ]);
  });

  it("renames hint codes and the checklist binding in code", () => {
    const source = `import { workItemChecklistBinding } from "better-supabase/blocks/tasks";

if (error.hint === "WORK_ITEM_LOCKED") warn();
if (error.hint === 'ENGAGEMENT_NOT_FOUND') missing();
const binding = workItemChecklistBinding;
`;

    expect(applyCodemod(v047, source, "src/tasks.ts").text)
      .toBe(`import { taskChecklistBinding } from "better-supabase/blocks/tasks";

if (error.hint === "TASK_LOCKED") warn();
if (error.hint === 'ACTIVITY_NOT_FOUND') missing();
const binding = taskChecklistBinding;
`);
  });

  it("lists the ambiguous hint and the renamed subject types", () => {
    const source = `if (error.hint === "ACTIVITY_FORBIDDEN") deny();
await db.rank.move("work_item", id, { group });
const ok = error.hint === "TASK_LOCKED";
`;

    const result = applyCodemod(v047, source, "src/checks.ts");

    expect(result.text).toBe(source);
    expect(result.review.map((line) => line.line)).toEqual([1, 2]);
  });

  it("renames hint codes in the app's own SQL", () => {
    const source = `exception when others then
  if sqlerrm_hint = 'WORK_ITEM_NOT_FOUND' then return null; end if;
select better_supabase.rank_move('work_item', id);
`;

    const result = applyCodemod(v047, source, "supabase/schemas/notes.sql");

    expect(result.text).toContain("'TASK_NOT_FOUND'");
    expect(result.review).toEqual([
      { line: 3, message: expect.stringContaining("`work_item` is `task`") },
    ]);
  });

  it("lists postmortem action items and AI document versions for review", () => {
    const source = `await incidents.savePostmortem(id, { actionItems });
const notes = 1;
select * from better_supabase.ai_document_versions;
`;

    const result = applyCodemod(v047, source, "src/postmortems.ts");

    expect(result.text).toBe(source);
    expect(result.review).toEqual([
      { line: 1, message: expect.stringContaining("addPostmortemAction") },
      { line: 3, message: expect.stringContaining("versions table") },
    ]);
  });

  it("lists the policy acknowledgement calls that moved to the acknowledgements block", () => {
    const source = `await db.$client.rpc("acknowledge_compliance_policy", { policy_id });
if (error.hint === "POLICY_NOT_PUBLISHED") wait();
const keep = await compliance.policies(org);
`;

    const result = applyCodemod(v047, source, "src/policies.ts");

    expect(result.text).toBe(source);
    expect(result.review).toEqual([
      {
        line: 1,
        message: expect.stringContaining(
          "acknowledge('compliance_policy', id)",
        ),
      },
      {
        line: 2,
        message: expect.stringContaining("ACKNOWLEDGEMENT_NO_VERSION"),
      },
    ]);

    const sql = applyCodemod(
      v047,
      "select * from better_supabase.policy_acknowledgements;\n",
      "supabase/schemas/reports.sql",
    );

    expect(sql.review.map((line) => line.line)).toEqual([1]);
  });
});
