import { RuleTester } from "oxlint/plugins-dev";

import { noChainedTypeAssertionsRule } from "../../../src/anti-slop/rules/no-chained-type-assertions.ts";

const tester = new RuleTester({
  languageOptions: { parserOptions: { lang: "ts" } },
});
const error = { messageId: "chained" };

tester.run(
  "anti-slop/no-chained-type-assertions",
  noChainedTypeAssertionsRule,
  {
    valid: [
      "const value = input as User;",
      "const value = <User>input;",
      "const value = ['a'] as const;",
      "const value = (input as const) as const;",
      "const value = read(input as Raw) as User;",
    ],
    invalid: [
      {
        name: "as chain",
        code: "const value = input as unknown as User;",
        errors: [error],
      },
      {
        name: "parenthesized chain",
        code: "const value = ((input as unknown)) as User;",
        errors: [error],
      },
      {
        name: "mixed spellings, reported once",
        code: "const value = <User>(input as unknown as Raw);",
        errors: [error],
      },
    ],
  },
);
