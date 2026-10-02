import { RuleTester } from "oxlint/plugins-dev";

import { noRuntimeTypeofRule } from "../../../src/anti-slop/rules/no-runtime-typeof.ts";

const tester = new RuleTester({
  languageOptions: { parserOptions: { lang: "ts" } },
});
const error = { messageId: "runtimeTypeof" };
const typeGuard =
  "function isText(value: unknown): value is string { return typeof value === 'string'; }";

tester.run("anti-slop/no-runtime-typeof", noRuntimeTypeofRule, {
  valid: [
    "type Config = typeof config;",
    "type Keys = keyof typeof config;",
    "const copy = value as typeof other;",
    { code: typeGuard, options: [{ allowInTypeGuards: true }] },
  ],
  invalid: [
    {
      name: "comparison",
      code: "if (typeof value === 'string') {}",
      errors: [error],
    },
    {
      name: "type guards by default",
      code: typeGuard,
      errors: [error],
    },
    {
      name: "outside a type guard with the option",
      code: "function check(value: string): boolean { return typeof value === 'string'; }",
      options: [{ allowInTypeGuards: true }],
      errors: [error],
    },
  ],
});
