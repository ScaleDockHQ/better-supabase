import { RuleTester } from "oxlint/plugins-dev";

import { noConditionalEmptyObjectSpreadRule } from "../../../src/anti-slop/rules/no-conditional-empty-object-spread.ts";

const tester = new RuleTester({
  languageOptions: { parserOptions: { lang: "ts" } },
});
const error = { messageId: "conditionalSpread" };

tester.run(
  "anti-slop/no-conditional-empty-object-spread",
  noConditionalEmptyObjectSpreadRule,
  {
    valid: [
      "const value = { ...base };",
      "const value = { ...(flag ? a : b) };",
      "const value = { ...build(flag ? {} : { a }) };",
      "const list = [...(flag ? [] : [a])];",
      "call(...(flag ? {} : { a }));",
    ],
    invalid: [
      {
        name: "empty alternate",
        code: "const value = { ...(flag ? { a } : {}) };",
        errors: [error],
      },
      {
        name: "empty consequent",
        code: "const value = { b, ...(flag ? {} : { a }) };",
        errors: [error],
      },
      {
        name: "parenthesized empty branch",
        code: "const value = { ...(flag ? ({}) : { a }) };",
        errors: [error],
      },
      {
        name: "nested parentheses",
        code: "const value = { ...((flag ? { a } : {})) };",
        errors: [error],
      },
    ],
  },
);
