import { MagicString } from "magic-string";
import { walk } from "oxc-walker";

import type { Codemod, ReviewLine } from "./codemod.ts";

import { lineColumn } from "./config-document/index.ts";
import { parseSource } from "./config-document/parse.ts";
import { addNamedImports } from "./import-edits.ts";

const HELPERS = new Set([
  "deleteAccount",
  "suspendAccount",
  "endSessions",
  "lastSignIns",
]);

const MODULE = "better-supabase/server/account";

/**
 * Rewrites `bsb.deleteAccount(id)` to `deleteAccount(bsb, id)` (and the same
 * for `suspendAccount`, `endSessions` and `lastSignIns`), and imports the
 * functions from `better-supabase/server/account` (ADR 0604). Only a call on a
 * plain identifier is rewritten; a call on `ctx.bsb` or another expression is
 * listed for review, since the receiver is not a name the codemod can pass.
 */
export function moveAccountCalls(text: string): {
  readonly text: string;
  readonly review: readonly ReviewLine[];
} {
  const parsed = parseSource(text);

  if (parsed.errors.length > 0) {
    return { text, review: [] };
  }

  const out = new MagicString(text);
  const used = new Set<string>();
  const review: ReviewLine[] = [];

  walk(parsed.program, {
    enter(node) {
      if (
        node.type !== "CallExpression" ||
        node.callee.type !== "MemberExpression" ||
        node.callee.computed ||
        node.callee.property.type !== "Identifier" ||
        !HELPERS.has(node.callee.property.name)
      ) {
        return;
      }

      const { name } = node.callee.property;
      const { object } = node.callee;

      if (object.type !== "Identifier") {
        review.push({
          line: lineColumn(text, node.start).line,
          message: `${name} now takes the server first; pass it as the first argument and import ${name} from ${MODULE}`,
        });

        return;
      }

      used.add(name);

      const [first] = node.arguments;

      out.overwrite(
        node.callee.start,
        first === undefined ? node.end - 1 : first.start,
        first === undefined
          ? `${name}(${object.name}`
          : `${name}(${object.name}, `,
      );
    },
  });

  if (used.size === 0) {
    return { text, review };
  }

  const names = [...used].toSorted();

  review.unshift({
    line: 1,
    message: `account helpers now take the server first: import ${names.join(", ")} from ${MODULE}`,
  });

  addNamedImports(out, parsed.program, MODULE, names);

  return { text: out.toString(), review };
}

export function accountCallsCodemod(): Codemod {
  return {
    name: "account-calls",
    description:
      "Call deleteAccount, suspendAccount, endSessions and lastSignIns from better-supabase/server/account with the server as the first argument",
    source: moveAccountCalls,
  };
}
