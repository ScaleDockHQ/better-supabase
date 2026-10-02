import { RuleTester } from "oxlint/plugins-dev";

import { noKnownValueWideningRule } from "../../../src/anti-slop/rules/no-known-value-widening.ts";

const tester = new RuleTester({
  languageOptions: { parserOptions: { lang: "ts" } },
});
const error = { messageId: "widening" };

tester.run("anti-slop/no-known-value-widening", noKnownValueWideningRule, {
  valid: [
    "const user = { id: 1 };",
    "const user: User = { id: 1 };",
    "const user = { id: 1 } satisfies User;",
    "const counts: Record<string, number> = {};",
    "const value: unknown = read();",
    "const value = input as unknown as User;",
    "const value = { id: 1 } as const;",
    "function read(): User { return { id: 1 }; }",
    "function outer(): unknown { const inner = () => 1; return read(); }",
  ],
  invalid: [
    {
      name: "unknown binding",
      code: "const value: unknown = { id: 1 };",
      errors: [error],
    },
    {
      name: "anonymous object type",
      code: "let point: { x: number } = { x: 1 };",
      errors: [error],
    },
    {
      name: "non-empty dictionary",
      code: "const counts: Readonly<Record<string, number>> = { a: 1 };",
      errors: [error],
    },
    {
      name: "class property",
      code: "class A { value: object = []; }",
      errors: [error],
    },
    {
      name: "assertion",
      code: "const value = [1, 2] as unknown;",
      errors: [error],
    },
    {
      name: "return in a nested block",
      code: "function read(): unknown { if (flag) { return 'a'; } return read(); }",
      errors: [error],
    },
    {
      name: "concise arrow",
      code: "const read = (): object => ({ id: 1 });",
      errors: [error],
    },
  ],
});
