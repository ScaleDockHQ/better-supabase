import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import { RULE_CODES } from "../../../src/cli/doctor/rules.ts";
import { WORKFLOW_BUILDER_RULES } from "../../../src/cli/doctor/workflow-builder.ts";

const [rule] = WORKFLOW_BUILDER_RULES;
const check = (sources: { path: string; text: string }[]) =>
  rule!.check({ sources } as unknown as DoctorContext);

describe("BS333", () => {
  it("flags admin() in a file that runs workflow-builder steps", async () => {
    const findings = await check([
      {
        path: "src/workflows/steps.ts",
        text: [
          'import { executeGraph } from "better-supabase/blocks/workflow-builder";',
          'import { server } from "./server";',
          "",
          "export async function lookup() {",
          '  return server.admin().from("contacts").select();',
          "}",
        ].join("\n"),
      },
      {
        path: "src/workflows/runtime.ts",
        text: 'import { nodeRunReporter } from "better-supabase/workflow-sdk/builder";\nconst db = admin();\n',
      },
      {
        path: "src/workflows/step.ts",
        text: "export const step = (call: GraphStepCall) => bs.admin ( );\n",
      },
    ]);
    expect(findings).toEqual([
      expect.objectContaining({
        target: "src/workflows/steps.ts:admin",
        location: { file: "src/workflows/steps.ts", line: 5 },
      }),
      expect.objectContaining({
        target: "src/workflows/runtime.ts:admin",
        location: { file: "src/workflows/runtime.ts", line: 2 },
      }),
      expect.objectContaining({
        target: "src/workflows/step.ts:admin",
        location: { file: "src/workflows/step.ts", line: 1 },
      }),
    ]);
    expect(findings[0]!.message).toContain("builder.versions.runAs");
  });

  it("ignores admin() outside executors and executors without admin()", async () => {
    expect(
      await check([
        { path: "src/admin.ts", text: "const db = server.admin();\n" },
        {
          path: "src/steps.ts",
          text: 'import { executeGraph } from "better-supabase/blocks/workflow-builder";\nconst ok = isAdmin(user);\n',
        },
        {
          path: "src/flows.ts",
          text: 'import { createWorkflow } from "better-supabase/blocks/workflows";\nadmin();\n',
        },
        {
          path: "src/builder-server.ts",
          text: 'import { createWorkflowBuilder, rpcTransport } from "better-supabase/blocks/workflow-builder";\nimport { graphStarter } from "better-supabase/workflow-sdk/builder";\nconst service = rpcTransport(bs.admin().$client);\n',
        },
      ]),
    ).toEqual([]);
  });

  it("is a registered rule", () => {
    expect(RULE_CODES).toContain("BS333");
    expect(rule).toMatchObject({ code: "BS333", severity: "warning" });
  });
});
