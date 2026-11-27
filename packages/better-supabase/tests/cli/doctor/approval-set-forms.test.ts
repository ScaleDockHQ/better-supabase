import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import { APPROVAL_SET_FORM_RULES } from "../../../src/cli/doctor/approval-set-forms.ts";
import { resolveConfig } from "../../../src/config/index.ts";

const targets = (
  config: Parameters<typeof resolveConfig>[0],
  provider?: object,
): string[] => {
  const resolved = resolveConfig(config, "/project");

  // SAFETY: the rule reads only `config`.
  const context = {
    config: provider ? { ...resolved, authorization: provider } : resolved,
  } as unknown as DoctorContext;

  return (
    APPROVAL_SET_FORM_RULES[0]!.check(context) as { target: string }[]
  ).map((finding) => finding.target);
};

describe("BS734", () => {
  it("lists each set form next to the approvals block", () => {
    expect(
      targets(
        {
          blocks: {
            approvals: {},
            leave: {
              options: {
                decider: "public.leave_decides",
                deciderMany: "public.leave_decides_many",
              },
            },
          },
        },
        { functions: { isApproverMany: "authz.approves({requests})" } },
      ),
    ).toEqual([
      "blocks.leave.options.deciderMany",
      "authorization.functions.isApproverMany",
    ]);
  });

  it("says nothing without the approvals block or a set form", () => {
    expect(
      targets(
        { blocks: { leave: { options: { deciderMany: "public.many" } } } },
        { functions: { isApproverMany: "authz.approves({requests})" } },
      ),
    ).toEqual([]);
    expect(
      targets({
        blocks: { approvals: {}, leave: { options: { decider: "public.d" } } },
      }),
    ).toEqual([]);
  });
});
