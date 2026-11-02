import { describe, expect, it } from "vitest";

import {
  findObjectInputCalls,
  rewriteObjectInputCalls,
} from "../../src/cli/codemod-object-inputs.ts";

const rewrite = (source: string): string =>
  rewriteObjectInputCalls(source).text;

describe("merged options", () => {
  it("adds nothing for an empty options object and trims a trailing comma", () => {
    expect(rewrite("await accounting.accounts(orgId, {});")).toBe(
      "await accounting.accounts({ organizationId: orgId });",
    );
    expect(rewrite("await accounting.accounts(orgId, { kind, });")).toBe(
      "await accounting.accounts({ organizationId: orgId, kind });",
    );
  });

  it("keeps a variable that already has the parameter's name", () => {
    expect(rewrite("await accounting.fxRate(organizationId, a, b, day);")).toBe(
      "await accounting.fxRate({ organizationId, base: a, quote: b, onDate: day });",
    );
  });
});

describe("argument splitting", () => {
  it("keeps commas inside strings, brackets and templates together", () => {
    expect(
      rewrite('await accounting.closeFiscalYear("a,b", [1, 2].length);'),
    ).toBe(
      'await accounting.closeFiscalYear({ organizationId: "a,b", fiscalYear: [1, 2].length });',
    );
    const placeholder = ["$", "{b}"].join("");

    expect(
      rewrite(`await accounting.closeFiscalYear(\`a,${placeholder}\`, year);`),
    ).toBe(
      `await accounting.closeFiscalYear({ organizationId: \`a,${placeholder}\`, fiscalYear: year });`,
    );
  });

  it("lets an arrow function's > close no angle bracket", () => {
    expect(
      rewrite("await accounting.closeFiscalYear(org, (x) => x + 1);"),
    ).toBe(
      "await accounting.closeFiscalYear({ organizationId: org, fiscalYear: (x) => x + 1 });",
    );
  });

  it("skips a call whose angle brackets do not balance", () => {
    expect(
      findObjectInputCalls("accounting.closeFiscalYear(a < b, c);"),
    ).toEqual([]);
  });

  it("skips a call that never closes", () => {
    expect(findObjectInputCalls("accounting.closeFiscalYear(a, b")).toEqual([]);
  });

  it("ignores an empty call and a call with too many arguments", () => {
    expect(findObjectInputCalls("accounting.closeFiscalYear();")).toEqual([]);
    expect(
      findObjectInputCalls("accounting.closeFiscalYear(a, b, c);"),
    ).toEqual([]);
  });
});

describe("one argument", () => {
  it("rewrites a lone argument that is clearly the old first one", () => {
    expect(rewrite("await accounting.budgets(orgId);")).toBe(
      "await accounting.budgets({ organizationId: orgId });",
    );
  });

  it("leaves a lone argument that is an object or an input variable", () => {
    expect(rewrite("await accounting.budgets({ organizationId });")).toBe(
      "await accounting.budgets({ organizationId });",
    );
    expect(rewrite("await accounting.budgets(input);")).toBe(
      "await accounting.budgets(input);",
    );
  });

  it("leaves a lone argument when the receiver is unknown", () => {
    expect(rewrite("await thing.budgets(orgId);")).toBe(
      "await thing.budgets(orgId);",
    );
  });
});

describe("receivers", () => {
  it("accepts a call straight on $blocks and rejects another block's client", () => {
    expect(rewrite("await $blocks.closeFiscalYear(org, year);")).toBe(
      "await $blocks.closeFiscalYear({ organizationId: org, fiscalYear: year });",
    );
    expect(
      rewrite("await $blocks.organizations.closeFiscalYear(org, year);"),
    ).toBe("await $blocks.organizations.closeFiscalYear(org, year);");
  });

  it("follows optional chaining, non-null assertions and call results", () => {
    expect(rewrite("await db?.accounting!.closeFiscalYear(org, year);")).toBe(
      "await db?.accounting!.closeFiscalYear({ organizationId: org, fiscalYear: year });",
    );
    expect(
      rewrite("await client(x).accounting.closeFiscalYear(org, year);"),
    ).toBe(
      "await client(x).accounting.closeFiscalYear({ organizationId: org, fiscalYear: year });",
    );
  });

  it("needs the whole sub-client path of a nested method", () => {
    expect(rewrite("await runs.setMembers(a, b);")).toBe(
      "await runs.setMembers(a, b);",
    );
    expect(rewrite("await ai.actions.update(chat, patch);")).toContain(
      "update(chat, patch)",
    );
  });
});

describe("repository verbs", () => {
  it("lists a method named like a repository call instead of rewriting it", () => {
    const result = rewriteObjectInputCalls(
      "await chats.actions.update(chatId, patch);",
    );

    expect(result.text).toBe("await chats.actions.update(chatId, patch);");
    expect(result.review).toEqual([
      {
        line: 1,
        message: expect.stringContaining("`.update(...)` may be a block"),
      },
    ]);
  });

  it("reports the line of each candidate", () => {
    const result = rewriteObjectInputCalls(
      "const a = 1;\n\nawait chats.actions.update(chatId, patch);",
    );

    expect(result.review.map((line) => line.line)).toEqual([3]);
  });
});

describe("conflicting signatures", () => {
  it("lists a call two signatures spell differently", () => {
    const calls = findObjectInputCalls("await thing.of(a, b);");

    for (const call of calls) {
      expect(call.input).toBeUndefined();
    }
  });
});
