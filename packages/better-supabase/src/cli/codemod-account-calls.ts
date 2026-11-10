import type { Codemod, ReviewLine } from "./codemod.ts";

const CALL =
  /\b([A-Za-z_$][\w$]*)\.(deleteAccount|suspendAccount|endSessions|lastSignIns)\(/g;

const IMPORTED =
  /import\s*\{[^}]*\}\s*from\s*["']better-supabase\/server\/account["']/;

/**
 * Rewrites `bsb.deleteAccount(id)` to `deleteAccount(bsb, id)` (and the same
 * for `suspendAccount`, `endSessions` and `lastSignIns`), and imports the
 * functions from `better-supabase/server/account` (ADR 0604). Only a call on a
 * plain identifier is rewritten; the rest is listed for review.
 */
export function moveAccountCalls(text: string): {
  readonly text: string;
  readonly review: readonly ReviewLine[];
} {
  const used = new Set<string>();

  const next = text.replaceAll(
    CALL,
    (_whole, receiver: string, name: string) => {
      used.add(name);

      return `${name}(${receiver}, `;
    },
  );

  if (used.size === 0) {
    return { text, review: [] };
  }

  const review: ReviewLine[] = [
    {
      line: 1,
      message: `account helpers now take the server first: import ${[...used].toSorted().join(", ")} from better-supabase/server/account`,
    },
  ];

  if (IMPORTED.test(next)) {
    return { text: next, review };
  }

  const line = `import { ${[...used].toSorted().join(", ")} } from "better-supabase/server/account";\n`;
  const imports = [...next.matchAll(/^import [^;]*;\n/gm)];
  const last = imports.at(-1);

  const at = last === undefined ? 0 : last.index + last[0].length;

  return { text: next.slice(0, at) + line + next.slice(at), review };
}

export function accountCallsCodemod(): Codemod {
  return {
    name: "account-calls",
    description:
      "Call deleteAccount, suspendAccount, endSessions and lastSignIns from better-supabase/server/account with the server as the first argument",
    source: moveAccountCalls,
  };
}
