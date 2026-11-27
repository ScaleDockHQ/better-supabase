import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

/** The blocks whose `decider` option has a set form, `deciderMany`. */
const SET_FORM_BLOCKS = ["leave", "expenses", "time-entries"] as const;

const PARITY =
  "It must answer exactly what the per-request form answers: an id it adds lets the caller read and decide that request through the approvals read policy. `better-supabase upgrade` writes the pgTAP test `900_better_supabase_approvals_eligible_ids.test.sql`, which compares approval_eligible_ids_in with approval_eligible for every user; run it against data that exercises the set form.";

function setForms(context: DoctorContext): FindingInput[] {
  if (!context.config.blockNames.includes("approvals")) {
    return [];
  }

  const found: FindingInput[] = SET_FORM_BLOCKS.flatMap((block) => {
    const many = context.config.blocks[block]?.options?.["deciderMany"];

    return typeof many === "string" && many !== ""
      ? [
          {
            message: `blocks.${block}.options.deciderMany names ${many}, the set form of options.decider. ${PARITY}`,
            target: `blocks.${block}.options.deciderMany`,
          },
        ]
      : [];
  });

  const isApproverMany = context.config.authorization?.functions.isApproverMany;

  if (isApproverMany !== undefined) {
    found.push({
      message: `authorization.functions.isApproverMany is the set form of isApprover. ${PARITY}`,
      target: "authorization.functions.isApproverMany",
    });
  }

  return found;
}

export const APPROVAL_SET_FORM_RULES: readonly Rule[] = [
  {
    code: "BS734",
    severity: "info",
    title: "A set form decides who reads approval requests",
    description:
      "`options.deciderMany` on leave, expenses or time entries, and the provider's `functions.isApproverMany`, answer many approval requests in one call inside `approval_eligible_ids_in`, which the approvals read policy uses. A set form that returns more ids than its per-request form (`decider`, `isApprover`) widens who reads and decides those requests. Doctor lists each one and points at the generated pgTAP test `900_better_supabase_approvals_eligible_ids.test.sql`, which compares the set with `approval_eligible` for every user.",
    check: setForms,
  },
];
