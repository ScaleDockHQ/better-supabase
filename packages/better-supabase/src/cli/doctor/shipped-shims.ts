import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { approverForNamesRequest } from "../../sql/index.ts";
import { withoutComments } from "../schema-reader/index.ts";
import { writtenByBlocks } from "../sql-layout.ts";
import { withoutStrings } from "./rls.ts";

const CREATE_FUNCTION =
  /create\s+(?:or\s+replace\s+)?function\s+"?better_supabase"?\s*\.\s*"?(\w+)"?\s*\(/gi;

/** The blocks whose `decider` option the provider's `approverFor` replaces. */
const DECIDER_BLOCKS = ["leave", "expenses", "time-entries"] as const;

const optionOf = (
  context: DoctorContext,
  block: string,
  option: string,
): unknown => context.config.blocks[block]?.options?.[option];

/** `better_supabase.<name>` functions a SQL text creates. */
function createdFunctions(text: string): Set<string> {
  const code = withoutStrings(withoutComments(text));

  return new Set(
    [...code.matchAll(CREATE_FUNCTION)].map((match) =>
      (match[1] ?? "").toLowerCase(),
    ),
  );
}

function shims(context: DoctorContext): FindingInput[] {
  const found: FindingInput[] = [];

  if (
    context.config.blockNames.includes("field-encryption") &&
    context.config.doctor.sealTriggers.length > 0
  ) {
    found.push({
      message: `tooling.doctor.sealTriggers lists ${context.config.doctor.sealTriggers.join(", ")}, so the app seals columns with its own trigger while field-encryption is installed. Mark the columns \`@bsb encrypted\` (or \`encrypted: true\`) and delete the trigger.`,
      target: "tooling.doctor.sealTriggers",
    });
  }

  const approverFor = context.config.authorization?.functions.approverFor;

  if (approverFor !== undefined && approverForNamesRequest(approverFor)) {
    for (const block of DECIDER_BLOCKS) {
      const decider = optionOf(context, block, "decider");

      if (typeof decider === "string" && decider !== "") {
        found.push({
          message: `blocks.${block}.options.decider names ${decider}, and the authorization provider already answers who may decide a request with functions.approverFor. Remove the option so the block reads the provider's function.`,
          target: `blocks.${block}.options.decider`,
        });
      }
    }
  }

  if (
    optionOf(context, "expenses", "approvals") === false &&
    optionOf(context, "expenses", "standaloneApprovals") === true
  ) {
    found.push({
      message:
        "blocks.expenses.options sets approvals: false and standaloneApprovals: true, which rebuilds by hand what the approvals block gives expenses. Remove approvals: false so reports go through the approvals block.",
      target: "blocks.expenses.options.approvals",
    });
  }

  const files = context.sqlFiles ?? [];

  const owned = new Set(
    files
      .filter(writtenByBlocks)
      .flatMap((file) => [...createdFunctions(file.text)]),
  );

  for (const file of files) {
    if (
      writtenByBlocks(file) ||
      file.path.includes("migrations/") ||
      file.path.includes("better-supabase-data/")
    ) {
      continue;
    }

    for (const name of createdFunctions(file.text)) {
      if (owned.has(name)) {
        found.push({
          message: `${file.path} redefines better_supabase.${name}, which a block already creates, so the next \`upgrade\` and the block's own file disagree. Set the block option that changes it, or add the behaviour in your own function.`,
          target: `${file.path}:${name}`,
          location: { file: file.path, line: 1 },
        });
      }
    }
  }

  return found;
}

export const SHIPPED_SHIM_RULES: readonly Rule[] = [
  {
    code: "BS706",
    severity: "warning",
    title: "Shim of a feature the library ships",
    description:
      "The project rebuilds something better-supabase already does: a custom seal trigger listed in `tooling.doctor.sealTriggers` while `field-encryption` is installed (`@bsb encrypted` fits), a `decider` option on leave, expenses or time entries while the authorization provider has `functions.approverFor`, `approvals: false` together with `standaloneApprovals` on expenses, and an app schema file that redefines a `better_supabase` function a block creates. Each one drifts from the block on the next upgrade.",
    check: shims,
  },
];
