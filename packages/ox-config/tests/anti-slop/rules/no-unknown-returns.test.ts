import { RuleTester } from "oxlint/plugins-dev";

import { noUnknownReturnsRule } from "../../../src/anti-slop/rules/no-unknown-returns.ts";

const tester = new RuleTester({
  languageOptions: { parserOptions: { lang: "ts" } },
});
const error = { messageId: "unknownReturn" };

tester.run("anti-slop/no-unknown-returns", noUnknownReturnsRule, {
  valid: [
    "function read(): string { return ''; }",
    "function read(): unknown[] { return []; }",
    "function read(): Record<string, unknown> { return {}; }",
    "function read(): Box<unknown> { return box; }",
    "function read() { return value; }",
  ],
  invalid: [
    {
      name: "function declaration",
      code: "function read(): unknown { return value; }",
      errors: [error],
    },
    {
      name: "promise of unknown",
      code: "async function read(): Promise<unknown> { return value; }",
      errors: [error],
    },
    {
      name: "promise-like of parenthesized unknown",
      code: "function read(): PromiseLike<(unknown)> { return value; }",
      errors: [error],
    },
    {
      name: "union with unknown",
      code: "const read = (): string | unknown => value;",
      errors: [error],
    },
    {
      name: "interface method and function type",
      code: "interface Store { read(): unknown } type Read = () => unknown;",
      errors: [error, error],
    },
    {
      name: "getter",
      code: "class Store { get value(): unknown { return 1; } }",
      errors: [error],
    },
  ],
});
