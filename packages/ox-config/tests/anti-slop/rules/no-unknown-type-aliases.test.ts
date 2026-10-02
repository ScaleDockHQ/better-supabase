import { RuleTester } from "oxlint/plugins-dev";

import { noUnknownTypeAliasesRule } from "../../../src/anti-slop/rules/no-unknown-type-aliases.ts";

const tester = new RuleTester({
  languageOptions: { parserOptions: { lang: "ts" } },
});
const error = { messageId: "unknownAlias" };

tester.run("anti-slop/no-unknown-type-aliases", noUnknownTypeAliasesRule, {
  valid: [
    "type Payload = { id: string };",
    "type Payloads = unknown[];",
    "type Maybe = unknown | string;",
    "type A = B; type B = A;",
    "function f() { type Local = unknown; }",
  ],
  invalid: [
    {
      name: "direct",
      code: "type Payload = unknown;",
      errors: [error],
    },
    {
      name: "exported and parenthesized",
      code: "export type Payload = (unknown);",
      errors: [error],
    },
    {
      name: "a generic alias is not resolved through",
      code: "type G<T> = unknown; type U = G;",
      errors: [{ ...error, line: 1, column: 0, endColumn: 20 }],
    },
    {
      name: "through a chain",
      code: "type Raw = unknown; type Payload = Raw;",
      errors: [error, error],
    },
  ],
});
