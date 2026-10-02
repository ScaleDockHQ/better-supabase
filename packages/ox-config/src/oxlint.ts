import { fileURLToPath } from "node:url";
import { type OxlintConfig, defineConfig } from "oxlint";

/**
 * Build output and caches that no workspace should lint. A consumer's own
 * `ignorePatterns` replaces the inherited list, so spread this constant first.
 */
export const ignorePatterns: readonly string[] = [
  "**/{dist,.next,.source,coverage,.turbo,node_modules}/**",
];

/**
 * Imports that the one-library-per-concern rule keeps out of the repo. A
 * `no-restricted-imports` override replaces the whole rule, so overrides
 * spread these in.
 */
export const restrictedImportPaths: { name: string; message: string }[] = [
  { name: "zod", message: "Use Valibot; any Standard Schema library works." },
  { name: "vaul", message: "Use the shadcn Drawer on Base UI." },
  { name: "dayjs", message: "Use Temporal." },
  { name: "luxon", message: "Use Temporal." },
  { name: "moment", message: "Use Temporal." },
  { name: "date-fns", message: "Use Temporal." },
  { name: "openai", message: "Call models through the AI SDK and AI Gateway." },
  {
    name: "@anthropic-ai/sdk",
    message: "Call models through the AI SDK and AI Gateway.",
  },
  {
    name: "@google/genai",
    message: "Call models through the AI SDK and AI Gateway.",
  },
];

export const restrictedImportPatterns: { group: string[]; message: string }[] =
  [
    { group: ["@radix-ui/*"], message: "Use Base UI primitives." },
    { group: ["date-fns/*", "@date-fns/*"], message: "Use Temporal." },
    {
      group: ["@ai-sdk/*", "!@ai-sdk/react", "!@ai-sdk/valibot"],
      message: 'Use plain "provider/model" strings through AI Gateway.',
    },
  ];

function plugin(specifier: string): string {
  return fileURLToPath(import.meta.resolve(specifier));
}

/**
 * The baseline every workspace extends: correctness, suspicious and perf at
 * error, type-aware rules pinned so a category change cannot drop them.
 */
export const core: OxlintConfig = defineConfig({
  ignorePatterns: [...ignorePatterns],
  plugins: [
    "eslint",
    "typescript",
    "oxc",
    "unicorn",
    "import",
    "node",
    "promise",
  ],
  jsPlugins: [
    { name: "turbo", specifier: plugin("eslint-plugin-turbo") },
    { name: "anti-slop", specifier: plugin("./anti-slop/index.ts") },
  ],
  categories: {
    correctness: "error",
    suspicious: "error",
    perf: "error",
    pedantic: "error",
  },
  options: {
    typeAware: true,
    denyWarnings: true,
    reportUnusedDisableDirectives: "error",
  },
  rules: {
    "no-eval": "error",
    "no-implied-eval": "error",
    "no-new-func": "error",
    "no-empty": "error",
    eqeqeq: ["error", "always", { null: "ignore" }],
    "no-restricted-imports": [
      "error",
      {
        paths: [...restrictedImportPaths],
        patterns: [...restrictedImportPatterns],
      },
    ],
    "import/no-cycle": "error",
    "import/no-unassigned-import": [
      "error",
      { allow: ["**/*.css", "server-only", "client-only"] },
    ],
    "node/no-process-env": "error",
    "turbo/no-undeclared-env-vars": "error",
    "unicorn/prefer-node-protocol": "error",

    "typescript/switch-exhaustiveness-check": "error",
    "typescript/only-throw-error": "error",
    "typescript/return-await": ["error", "in-try-catch"],
    "typescript/unbound-method": "error",
    "typescript/await-thenable": "error",
    "typescript/consistent-type-imports": "error",
    "typescript/no-explicit-any": "error",
    "typescript/no-misused-promises": "error",
    "typescript/no-floating-promises": "error",
    "typescript/no-deprecated": "error",
    // 335 findings when measured (222 in tests). Each needs a guard or a
    // narrower type; tracked as backlog in docs/decisions/0002.
    "typescript/no-non-null-assertion": "off",
    "typescript/prefer-optional-chain": "error",
    "typescript/prefer-nullish-coalescing": "error",
    "typescript/no-unsafe-argument": "error",
    "typescript/no-unsafe-assignment": "error",
    "typescript/no-unsafe-call": "error",
    "typescript/no-unsafe-member-access": "error",
    "typescript/no-unsafe-return": "error",
    "typescript/no-unsafe-enum-comparison": "error",
    "typescript/no-unsafe-unary-minus": "error",
    "typescript/no-unsafe-declaration-merging": "error",
    "typescript/no-unsafe-function-type": "error",
    "typescript/no-unnecessary-condition": "error",
    // 426 findings when measured, 316 of them `if (text)` checks where the
    // empty string is meant to be falsy. Rewriting them changes behavior one
    // by one; tracked as backlog in docs/decisions/0002.
    "typescript/strict-boolean-expressions": "off",
    "typescript/no-unnecessary-type-assertion": "error",
    "typescript/no-unnecessary-type-arguments": "error",
    "typescript/no-unnecessary-template-expression": "error",
    "typescript/no-redundant-type-constituents": "error",
    "typescript/restrict-template-expressions": "error",
    "typescript/strict-void-return": "error",
    "typescript/consistent-type-exports": "error",
    "typescript/dot-notation": "error",
    "typescript/prefer-readonly": "error",
    "typescript/prefer-find": "error",
    "typescript/prefer-string-starts-ends-with": "error",
    "typescript/prefer-regexp-exec": "error",
    "typescript/no-confusing-void-expression": "error",
    "typescript/prefer-includes": "error",
    "typescript/prefer-promise-reject-errors": "error",
    "typescript/related-getter-setter-pairs": "error",
    "typescript/require-await": "error",
    "typescript/restrict-plus-operands": "error",
    "typescript/non-nullable-type-assertion-style": "error",
    // 312 findings when measured. Misuse (an unknown table, a role other
    // than authenticated or anon) throws synchronously before any I/O, and
    // tests assert that; `async` turns those throws into rejections.
    "typescript/promise-function-async": "off",
    "typescript/use-unknown-in-catch-callback-variable": "error",
    "typescript/no-unnecessary-qualifier": "error",
    "typescript/prefer-reduce-type-parameter": "error",
    "typescript/prefer-return-this-type": "error",
    "typescript/no-mixed-enums": "error",

    "anti-slop/no-chained-type-assertions": "error",
    "anti-slop/no-conditional-empty-object-spread": "error",
    "anti-slop/no-known-value-widening": "error",
    "anti-slop/no-module-mocking": "error",
    "anti-slop/no-object-parameters": "error",
    "anti-slop/no-reflect-apply": "error",
    "anti-slop/no-reflect-get": "error",
    "anti-slop/no-runtime-typeof": "error",
    "anti-slop/no-shape-in-symbol-names": "error",
    "anti-slop/no-unknown-parameters": "error",
    "anti-slop/no-unknown-returns": "error",
    "anti-slop/no-unknown-type-aliases": "error",
    "anti-slop/no-unsafe-dictionary-type": "error",
    "anti-slop/no-widen-then-assert": "error",
    "anti-slop/require-safety-comment-for-type-assertion": "error",

    // Shadowing a name in a nested scope is how the query builders read.
    "eslint/no-shadow": "off",
    // `toSorted` and `toReversed` copies are not needed on local arrays.
    "unicorn/no-array-sort": "off",
    "unicorn/no-array-reverse": "off",
    // Migrations, pages and retries run in order on purpose.
    "eslint/no-await-in-loop": "off",
    // Closures next to their single caller read better than hoisted helpers.
    "unicorn/consistent-function-scoping": "off",
    // Row and option objects are small; spreading them is not a hot path.
    "oxc/no-map-spread": "off",
    "oxc/no-accumulating-spread": "off",
    // 402 findings when measured: generic trees, decoded JSON and the
    // isolatedDeclarations boundary need assertions. AGENTS.md asks for a
    // `SAFETY:` comment on each new one instead.
    "typescript/no-unsafe-type-assertion": "off",
    // `query<R>(): Promise<{ rows: R[] }>` style return-only generics are
    // the caller-supplied row type, not an unused parameter.
    "typescript/no-unnecessary-type-parameters": "off",
    // 27 findings when measured, all `String(unknown)` for SQL literals,
    // headers, form values and error text, where that is the intent.
    "typescript/no-base-to-string": "off",
    // `Record<never, never>` is the deliberate "no extra fields" marker in
    // the DbError detail map and in conditional types.
    "typescript/no-generated-empty-object-type": "off",
    // Fire-and-forget `.then()` side effects in realtime subscriptions.
    "promise/always-return": "off",
    "promise/no-promise-in-callback": "off",
    // Realtime and storage wrap `on*` handler properties of the SDK objects.
    "unicorn/prefer-add-event-listener": "off",
    // Spreading an iterable into a fresh array is how readonly inputs copy.
    "unicorn/no-useless-spread": "off",

    // An explicit `undefined` argument or arrow body is how a call fills a
    // required `T | undefined` parameter or an `() => undefined` contract.
    "unicorn/no-useless-undefined": [
      "error",
      { checkArguments: false, checkArrowFunctionBody: false },
    ],

    // noImplicitReturns checks this with types, and the rule rejects the
    // bare `return;` that no-useless-undefined writes for `T | undefined`;
    // 20 findings when measured.
    "typescript/consistent-return": "off",
    // noImplicitReturns needs the final `return;` of a `T | undefined`
    // function (TS7030); 8 findings when measured, all that case.
    "eslint/no-useless-return": "off",
    // Not type-aware: it flags every `.match()` call, and 2 of the 3
    // findings when measured were custom path matchers.
    "unicorn/prefer-regexp-test": "off",

    // The 1,000-line limit of the repo standard, counting code only.
    "eslint/max-lines": [
      "error",
      { max: 1000, skipBlankLines: true, skipComments: true },
    ],
    // 392 findings when measured. Builders, codegen emitters and test
    // suites are long functions by design; max-lines bounds the file.
    "eslint/max-lines-per-function": "off",
    // 34 findings when measured: entry modules and test suites import
    // many siblings, and Knip and Turbo boundaries already police imports.
    "import/max-dependencies": "off",
    // 1,764 findings when measured. Deep readonly on every parameter
    // fights the SDK types the library wraps; `readonly` arrays and
    // `Readonly<T>` are used where a function promises not to mutate.
    "typescript/prefer-readonly-parameter-types": "off",
    // 455 findings when measured. The `u` flag changes escape rules and
    // case folding per pattern, so each needs review; backlog in
    // docs/decisions/0002.
    "eslint/require-unicode-regexp": "off",
    // Duplicates typescript/require-await, which is type-aware (121 findings
    // when measured, the same sites).
    "eslint/require-await": "off",
    // Duplicates unicorn/no-negated-condition, which has the same fix.
    "eslint/no-negated-condition": "off",
    // 40 findings when measured, all `.map(parseRow)` style calls on typed
    // single-argument callbacks; the type-aware rules catch arity drift.
    "unicorn/no-array-callback-reference": "off",
    // 10 findings when measured, all deliberate: `string & {}` keeps literal
    // autocomplete, and `{}` is the empty default of generic arguments.
    "typescript/ban-types": "off",
    // 6 findings when measured, all a Valibot schema and its inferred type
    // sharing one name, which TypeScript resolves by declaration space.
    "eslint/no-redeclare": "off",
    // 4 findings when measured: an error class and its subclass, or a test
    // file's fixture classes, belong together.
    "eslint/max-classes-per-file": "off",
  },
});

/**
 * Code that runs on Node: CLIs, scripts, servers and tests. Node built-ins
 * are fine here; runtime library entries restrict them separately.
 */
export const node: OxlintConfig = defineConfig({
  env: { node: true },
  rules: {
    "node/no-exports-assign": "error",
    "node/no-new-require": "error",
    "node/no-path-concat": "error",
  },
});

/** Published packages: named exports only, so tree shaking and docs work. */
export const library: OxlintConfig = defineConfig({
  rules: {
    "import/no-default-export": "error",
    "typescript/explicit-module-boundary-types": "error",
  },
  overrides: [
    {
      // Tool configs are loaded through their default export.
      files: ["*.config.ts", "*.config.mts"],
      rules: { "import/no-default-export": "off" },
    },
  ],
});

const reactRules: OxlintConfig["rules"] = {
  // The automatic JSX runtime (`jsx: react-jsx`) needs no React import.
  "react/react-in-jsx-scope": "off",
  "react/rules-of-hooks": "error",
  "react/exhaustive-deps": "error",
  "react/jsx-key": "error",
  "react/jsx-no-target-blank": "error",
  "react/no-danger-with-children": "error",
  "react/no-array-index-key": "error",
  "react/self-closing-comp": "error",
  "react/jsx-no-useless-fragment": "error",
  "react/no-unknown-property": "error",
  // React Compiler restrictions: code the compiler cannot optimize.
  "react/invariant": "error",
  "react/todo": "error",
  "react/syntax": "error",
  "react/unsupported-syntax": "error",
  "react/rule-suppression": "error",
  "react-doctor/no-derived-state-effect": "error",
  "react-doctor/no-fetch-in-effect": "error",
  "react-doctor/no-effect-chain": "error",
  "react-doctor/no-effect-event-handler": "error",
  "react-doctor/no-mirror-prop-effect": "error",
  "react-doctor/no-self-updating-effect": "error",
  "react-doctor/no-async-effect-callback": "error",
  "react-doctor/no-set-state-after-await-in-effect": "error",
  "react-doctor/effect-needs-cleanup": "error",
  "react-doctor/effect-listener-cleanup-mismatch": "error",
  "react-doctor/no-prop-callback-in-effect": "error",
};

const a11yRules = [
  "alt-text",
  "anchor-ambiguous-text",
  "anchor-has-content",
  "anchor-is-valid",
  "aria-activedescendant-has-tabindex",
  "aria-props",
  "aria-proptypes",
  "aria-role",
  "aria-unsupported-elements",
  "autocomplete-valid",
  "click-events-have-key-events",
  "heading-has-content",
  "html-has-lang",
  "iframe-has-title",
  "img-redundant-alt",
  "label-has-associated-control",
  "lang",
  "media-has-caption",
  "mouse-events-have-key-events",
  "no-access-key",
  "no-aria-hidden-on-focusable",
  "no-autofocus",
  "no-distracting-elements",
  "no-noninteractive-tabindex",
  "no-redundant-roles",
  "prefer-tag-over-role",
  "role-has-required-aria-props",
  "role-supports-aria-props",
  "scope",
  "tabindex-no-positive",
] as const;

/** React components: hooks, effects and every jsx-a11y rule at error. */
export const react: OxlintConfig = defineConfig({
  plugins: ["react", "jsx-a11y"],
  jsPlugins: [
    { name: "react-doctor", specifier: plugin("oxlint-plugin-react-doctor") },
  ],
  env: { browser: true },
  rules: {
    ...reactRules,
    ...Object.fromEntries(
      a11yRules.map((rule) => [`jsx-a11y/${rule}`, "error"]),
    ),
  },
});

/** Tailwind design system rules for apps that own shadcn components. */
export const shadcn: OxlintConfig = defineConfig({
  jsPlugins: [{ name: "shadcn", specifier: plugin("@shadcn/lint") }],
  rules: {
    "shadcn/no-inline-styles": "error",
    "shadcn/no-raw-colors": "error",
    "shadcn/no-arbitrary-values": "error",
    "shadcn/no-unknown-classes": "error",
    "shadcn/require-static-classes": "error",
  },
});

const testFiles = [
  "**/tests/**/*.{ts,tsx}",
  "**/*.{test,spec}.{ts,tsx}",
  "**/*.test-d.ts",
];

/** Vitest suites, unit to integration, and `expectTypeOf` type tests. */
export const test: OxlintConfig = defineConfig({
  plugins: ["vitest"],
  overrides: [
    {
      files: testFiles,
      rules: {
        "vitest/no-focused-tests": "error",
        "vitest/no-disabled-tests": "error",
        // Tests await in `expect(...).rejects` and fire promises on purpose.
        "typescript/no-floating-promises": "off",
        "typescript/no-misused-promises": "off",
        // Plain `vi.fn()` spies stand in for callbacks of any shape.
        "vitest/require-mock-type-parameters": "off",
        // Table-driven cases branch on the case inside one `it`; 206
        // no-conditional-in-test findings when measured.
        "vitest/no-conditional-tests": "off",
        "vitest/no-conditional-in-test": "off",
        // Suites are one file per module (AGENTS.md); 4 exceed 1,000 lines.
        "eslint/max-lines": "off",
        // Fakes implement async SDK methods without awaiting; 89
        // require-await findings when measured.
        "typescript/require-await": "off",
        // Tests reject and throw non-Error values to cover how the code
        // under test handles them; 10 findings when measured.
        "eslint/prefer-promise-reject-errors": "off",
        "typescript/prefer-promise-reject-errors": "off",
        "eslint/no-throw-literal": "off",
        // Spies and `vi.fn()` callbacks return values the caller ignores;
        // 77 strict-void-return findings when measured.
        "typescript/strict-void-return": "off",
        // Type tests assert with `expectTypeOf`, which the rule cannot see.
        "vitest/expect-expect": "off",
        // Tests hand fake clients and spans to typed APIs on purpose.
        "anti-slop/no-chained-type-assertions": "off",
        "anti-slop/require-safety-comment-for-type-assertion": "off",
        // Fixtures read the local stack's env with defaults.
        "node/no-process-env": "off",
        // Vitest asymmetric matchers (`expect.any`, `expect.stringContaining`)
        // and `Response.json()` are typed `any`; 60 findings when measured.
        "typescript/no-unsafe-assignment": "off",
        "typescript/no-unsafe-member-access": "off",
        "typescript/no-unsafe-argument": "off",
        "typescript/no-unsafe-call": "off",
        "typescript/no-unsafe-return": "off",
      },
    },
  ],
});

/** Playwright suites. */
export const playwright: OxlintConfig = defineConfig({
  jsPlugins: [
    { name: "playwright", specifier: plugin("eslint-plugin-playwright") },
  ],
  overrides: [
    {
      files: testFiles,
      rules: {
        "playwright/no-focused-test": "error",
        "playwright/no-skipped-test": "error",
        "playwright/no-wait-for-timeout": "error",
        "playwright/no-page-pause": "error",
        "playwright/missing-playwright-await": "error",
      },
    },
  ],
});
