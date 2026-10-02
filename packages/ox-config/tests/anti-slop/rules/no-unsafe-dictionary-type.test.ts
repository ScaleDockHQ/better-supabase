import { RuleTester } from "oxlint/plugins-dev";

import { noUnsafeDictionaryTypeRule } from "../../../src/anti-slop/rules/no-unsafe-dictionary-type.ts";

const tester = new RuleTester({
  languageOptions: { parserOptions: { lang: "ts" } },
});
const error = { messageId: "unsafeDictionary" };

tester.run("anti-slop/no-unsafe-dictionary-type", noUnsafeDictionaryTypeRule, {
  valid: [
    "type Counts = Record<string, number>;",
    "type Rows = { [key: string]: Row };",
    "type Flags = { [K in Keys]: boolean };",
    "type Values = Record<string, unknown[]>;",
    "type Values = Record<string, { id: string }>;",
    "import type { Record } from './record'; type Values = Record<string, unknown>;",
  ],
  invalid: [
    {
      name: "record of unknown",
      code: "type Values = Record<string, unknown>;",
      errors: [error],
    },
    {
      name: "record of a union with any",
      code: "type Values = Record<string, string | any>;",
      errors: [error],
    },
    {
      name: "record of an empty object",
      code: "type Values = Record<string, {}>;",
      errors: [error],
    },
    {
      name: "index signature of object",
      code: "interface Values { [key: string]: object }",
      errors: [error],
    },
    {
      name: "mapped type of a wrapped unknown",
      code: "type Values = { [K in Keys]: Readonly<unknown> };",
      errors: [error],
    },
    {
      name: "class index signature",
      code: "class Bag { [key: string]: unknown }",
      errors: [error],
    },
  ],
});
