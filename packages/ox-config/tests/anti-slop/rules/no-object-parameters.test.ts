import { RuleTester } from "oxlint/plugins-dev";

import { noObjectParametersRule } from "../../../src/anti-slop/rules/no-object-parameters.ts";

const tester = new RuleTester({
  languageOptions: { parserOptions: { lang: "ts" } },
});
const error = { messageId: "objectParameter" };

tester.run("anti-slop/no-object-parameters", noObjectParametersRule, {
  valid: [
    "function save(user: User) {}",
    "function save(users: object[]) {}",
    "function save(users: Array<object>) {}",
    "function save(user: { meta: object }) {}",
    "function save(user: User & object) {}",
    "function save(callback: (value: string) => object) {}",
  ],
  invalid: [
    {
      name: "plain object",
      code: "function save(user: object) {}",
      errors: [error],
    },
    {
      name: "union with object",
      code: "function save(user: object | null) {}",
      errors: [error],
    },
    {
      name: "parenthesized and destructured",
      code: "function save({ id }: (object)) {}",
      errors: [error],
    },
    {
      name: "every parameter is reported",
      code: "const save = (a: object, b: object) => {};",
      errors: [error, error],
    },
    {
      name: "interface method",
      code: "interface Store { save(user: object): void }",
      errors: [error],
    },
  ],
});
