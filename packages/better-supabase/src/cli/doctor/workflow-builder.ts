import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { lineOf } from "./shared.ts";

// Only names that execute steps: a file that builds the builder's service
// transport or starts runs needs the service role legitimately.
const BUILDER_EXECUTOR = /\b(?:GraphStepCall|executeGraph|nodeRunReporter)\b/;
const ADMIN_CALL = /\badmin\s*\(/;

function adminInBuilderExecutor(context: DoctorContext): FindingInput[] {
  return context.sources.flatMap((file) => {
    if (!BUILDER_EXECUTOR.test(file.text)) return [];
    const line = lineOf(file.text, ADMIN_CALL);
    if (line === undefined) return [];
    return [
      {
        message: `${file.path} runs workflow-builder steps and calls admin(), which bypasses RLS for every step. Resolve the publisher's claims with builder.versions.runAs(call.version) in each step and query as them, so a demoted publisher's workflow stops.`,
        target: `${file.path}:admin`,
        location: { file: file.path, line },
      },
    ];
  });
}

export const WORKFLOW_BUILDER_RULES: readonly Rule[] = [
  {
    code: "BS333",
    severity: "warning",
    title: "admin() inside a workflow-builder executor",
    description:
      "A file that runs workflow-builder steps calls `admin()`. Steps run with the service role's rights instead of the publisher's, so a published workflow keeps running after its publisher loses a permission.",
    check: adminInBuilderExecutor,
  },
];
