import { RuleTester } from "oxlint/plugins-dev";

import { noShapeInSymbolNamesRule } from "../../../src/anti-slop/rules/no-shape-in-symbol-names.ts";

const tester = new RuleTester({
  languageOptions: {
    parserOptions: { lang: "ts", ecmaFeatures: { jsx: true } },
  },
});
const error = { messageId: "shapeName" };

tester.run("anti-slop/no-shape-in-symbol-names", noShapeInSymbolNamesRule, {
  valid: [
    "const user = { id: 1 };",
    "const label = 'shape';",
    "// shape of the row",
    "const value = { 'shape': 1 };",
  ],
  invalid: [
    {
      name: "binding",
      code: "const userShape = {};",
      errors: [error],
    },
    {
      name: "type alias, case-insensitive",
      code: "type SHAPE = string;",
      errors: [error],
    },
    {
      name: "private field",
      code: "class A { #shaped = 1; }",
      errors: [error],
    },
    {
      name: "property key and reference",
      code: "const a = { shape: 1 }; a.shape;",
      errors: [error, error],
    },
  ],
});
