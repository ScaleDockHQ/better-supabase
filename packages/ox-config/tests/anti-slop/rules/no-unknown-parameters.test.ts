import { RuleTester } from "oxlint/plugins-dev";

import { noUnknownParametersRule } from "../../../src/anti-slop/rules/no-unknown-parameters.ts";

const tester = new RuleTester({
  languageOptions: { parserOptions: { lang: "ts" } },
});
const error = { messageId: "unknownParameter" };

tester.run("anti-slop/no-unknown-parameters", noUnknownParametersRule, {
  valid: [
    "function parse(input: string) {}",
    "function wrap(cause: unknown) {}",
    "function list(values: unknown[]) {}",
    "function map(values: Record<string, unknown>) {}",
    "function maybe(value: unknown | string) {}",
    "function later(value: Promise<unknown>) {}",
    "function untyped(value) {}",
  ],
  invalid: [
    {
      name: "function declaration",
      code: "function parse(input: unknown) {}",
      errors: [error],
    },
    {
      name: "arrow with default",
      code: "const parse = (input: unknown = 1) => input;",
      errors: [error],
    },
    {
      name: "parenthesized",
      code: "function parse(input: (unknown)) {}",
      errors: [error],
    },
    {
      name: "rest parameter",
      code: "function log(...values: unknown) {}",
      errors: [error],
    },
    {
      name: "method and interface signatures",
      code: "class A { run(input: unknown) {} } interface B { run(input: unknown): void }",
      errors: [error, error],
    },
    {
      name: "function type",
      code: "type Handler = (event: unknown) => void;",
      errors: [error],
    },
    {
      name: "parameter property",
      code: "class A { constructor(private readonly input: unknown) {} }",
      errors: [error],
    },
  ],
});
