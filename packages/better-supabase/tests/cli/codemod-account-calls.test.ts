import { describe, expect, it } from "vitest";

import { moveAccountCalls } from "../../src/cli/codemod-account-calls.ts";

describe("codemod account-calls", () => {
  it("passes the server first and adds the import", () => {
    const result = moveAccountCalls(
      'import { ok } from "better-supabase";\n\nexport const f = (id: string) => bsb.deleteAccount(id, { buckets: [] });\n',
    );

    expect(result.text).toContain(
      'import { deleteAccount } from "better-supabase/server/account";',
    );
    expect(result.text).toContain("deleteAccount(bsb, id, { buckets: [] })");
    expect(result.review).toHaveLength(1);
  });

  it("covers every helper and keeps one import", () => {
    const result = moveAccountCalls(
      "await server.suspendAccount(id, { suspended: true });\nawait server.endSessions(id);\nawait server.lastSignIns([id]);\n",
    );

    expect(result.text).toContain("suspendAccount(server, id,");
    expect(result.text).toContain("endSessions(server, id)");
    expect(result.text).toContain("lastSignIns(server, [id])");
    expect(
      result.text.startsWith(
        "import { endSessions, lastSignIns, suspendAccount } from",
      ),
    ).toBe(true);
  });

  it("leaves a file without those calls alone", () => {
    const text = "export const a = 1;\n";

    expect(moveAccountCalls(text)).toEqual({ text, review: [] });
  });
});
