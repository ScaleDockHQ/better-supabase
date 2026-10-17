import playwright from "eslint-plugin-playwright";
import { fileURLToPath } from "node:url";
import { type OxlintConfig, defineConfig } from "oxlint";
import antiSlop from "ultracite/oxlint/anti-slop";
import core from "ultracite/oxlint/core";
import { jsPluginSettings, selectJsPlugins } from "ultracite/oxlint/js-plugins";
import ultraciteNext from "ultracite/oxlint/next";
import ultraciteNextJsPlugins from "ultracite/oxlint/next/js-plugins";
import ultraciteReact from "ultracite/oxlint/react";
import ultraciteShadcn from "ultracite/oxlint/shadcn";
import vitest from "ultracite/oxlint/vitest";

function plugin(specifier: string): string {
  return fileURLToPath(import.meta.resolve(specifier));
}

/**
 * Every config spreads these: a workspace's `ignorePatterns` replaces the
 * inherited list. `apps/docs/content/docs/build` is a docs section, not output.
 */
export const ignorePatterns: string[] = [
  ...(core.ignorePatterns ?? []).filter((pattern) => pattern !== "**/build"),
  "**/.source",
  "**/.agents/**",
  "**/.claude/**",
  "**/.cursor/**",
  "**/generated.ts",
  "**/generated.meta.*",
  "**/generated-*.ts",
  "**/database.types.ts",
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
      // @ai-sdk/mcp is the MCP client, not a model provider.
      // @ai-sdk/workflow runs agents inside Workflow SDK runs; it calls no provider.
      group: [
        "@ai-sdk/*",
        "!@ai-sdk/react",
        "!@ai-sdk/valibot",
        "!@ai-sdk/mcp",
        "!@ai-sdk/workflow",
        "!@ai-sdk/workflow/*",
      ],
      message: 'Use plain "provider/model" strings through AI Gateway.',
    },
  ];

const testFiles = [
  "**/tests/**/*.{ts,tsx}",
  "**/*.{test,spec,test-d,spec-d}.{ts,tsx,js,jsx,mts,cts,mjs,cjs}",
  "**/__tests__/**/*.{ts,tsx,js,jsx,mts,cts,mjs,cjs}",
];

const reactDoctor = selectJsPlugins(["react-doctor"]);

/** The recommended Playwright rules, all at error like every other rule. */
const playwrightRules: NonNullable<OxlintConfig["rules"]> = Object.fromEntries(
  Object.keys(playwright.configs["flat/recommended"].rules ?? {})
    .filter((name) => name.startsWith("playwright/"))
    .map((name) => [name, "error"]),
);

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

/** React components: Ultracite's react preset, react-doctor and the effect rules. */
export const react: OxlintConfig = defineConfig({
  extends: [ultraciteReact, reactDoctor],
  jsPlugins: [
    { name: "react-doctor", specifier: plugin("oxlint-plugin-react-doctor") },
  ],
  env: { browser: true },
  rules: {
    "react/rules-of-hooks": "error",
    "react/exhaustive-deps": "error",
    "react/no-array-index-key": "error",
    "react/no-unknown-property": "error",
    "jsx-a11y/no-autofocus": "error",
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

    // Components are function declarations, and the react-doctor findings are
    // perf hints on code outside render paths; each needs reading. Backlog in
    // docs/decisions/0002.
    // Findings when measured: function-component-definition 295,
    // js-combine-iterations 150, js-set-map-lookups 96, async-await-in-loop 75,
    // no-barrel-import 36, no-json-parse-stringify-clone 22,
    // server-sequential-independent-await 5, jsx-handler-names 4, js-index-maps
    // 4, no-react-children 3, hook-use-state 3,
    // prefer-module-scope-pure-function 3, js-cache-property-access 3,
    // async-defer-await 3, jsx-curly-brace-presence 2, no-array-index-as-key 1,
    // jsx-pascal-case 1, rerender-defer-reads-hook 1,
    // rendering-hydration-mismatch-time 1, no-danger 1, no-giant-component 1,
    // js-flatmap-filter 1, js-length-check-first 1, button-has-type 1.
    "react/function-component-definition": "off",
    "react-doctor/js-combine-iterations": "off",
    "react-doctor/js-set-map-lookups": "off",
    "react-doctor/async-await-in-loop": "off",
    "react-doctor/no-barrel-import": "off",
    "react-doctor/no-json-parse-stringify-clone": "off",
    "react-doctor/server-sequential-independent-await": "off",
    "react/jsx-handler-names": "off",
    "react-doctor/js-index-maps": "off",
    "react/no-react-children": "off",
    "react/hook-use-state": "off",
    "react-doctor/prefer-module-scope-pure-function": "off",
    "react-doctor/js-cache-property-access": "off",
    "react-doctor/async-defer-await": "off",
    "react/jsx-curly-brace-presence": "off",
    "react-doctor/no-array-index-as-key": "off",
    "react/jsx-pascal-case": "off",
    "react-doctor/rerender-defer-reads-hook": "off",
    "react-doctor/rendering-hydration-mismatch-time": "off",
    "react/no-danger": "off",
    "react-doctor/no-giant-component": "off",
    "react-doctor/js-flatmap-filter": "off",
    "react-doctor/js-length-check-first": "off",
    "react/button-has-type": "off",
  },
});

/**
 * Next.js apps, on top of `react`, which loads the react-doctor plugin these
 * Next.js rules belong to.
 */
export const next: OxlintConfig = defineConfig({
  extends: [ultraciteNext],
  rules: { ...ultraciteNextJsPlugins.rules },
});

/** Tailwind design system rules for apps that own shadcn components. */
export const shadcn: OxlintConfig = defineConfig({
  extends: [ultraciteShadcn],
  jsPlugins: [{ name: "shadcn", specifier: plugin("@shadcn/lint") }],
  rules: {
    // Pages pass layout and appearance classes to shadcn components; moving
    // appearance into variants is per component. Backlog in docs/decisions/0002.
    // Findings when measured: no-restyle 140.
    "shadcn/no-restyle": "off",
  },
});

/** Oxlint does not merge `settings` from `extends`; every workspace sets it. */
export const settings: NonNullable<OxlintConfig["settings"]> = jsPluginSettings;

const config: OxlintConfig = defineConfig({
  extends: [core, vitest, antiSlop],
  jsPlugins: [{ name: "turbo", specifier: plugin("eslint-plugin-turbo") }],
  env: { node: true },
  options: {
    typeAware: true,
    denyWarnings: true,
    reportUnusedDisableDirectives: "error",
  },
  ignorePatterns,
  settings,
  rules: {
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
      {
        allow: [
          "**/*.css",
          "server-only",
          "client-only",
          "temporal-polyfill/global",
        ],
      },
    ],
    "node/no-process-env": "error",
    "node/no-exports-assign": "error",
    "node/no-new-require": "error",
    "node/no-path-concat": "error",
    "turbo/no-undeclared-env-vars": "error",
    // Type-aware rules the house config kept at error that Ultracite's core
    // leaves out or sets differently.
    "typescript/prefer-optional-chain": "error",
    "typescript/no-unnecessary-condition": "error",
    "typescript/require-await": "error",
    "typescript/return-await": ["error", "in-try-catch"],

    // 335 findings when measured (222 in tests). Each needs a guard or a
    // narrower type; tracked as backlog in docs/decisions/0002.
    "typescript/no-non-null-assertion": "off",
    // 426 findings when measured, 316 of them `if (text)` checks where the
    // empty string is meant to be falsy. Rewriting them changes behavior one
    // by one; tracked as backlog in docs/decisions/0002.
    "typescript/strict-boolean-expressions": "off",
    // 312 findings when measured. Misuse (an unknown table, a role other
    // than authenticated or anon) throws synchronously before any I/O, and
    // tests assert that; `async` turns those throws into rejections.
    "typescript/promise-function-async": "off",
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

    // Ultracite rules that fire on code written before it was adopted. Each
    // is its own follow-up change; backlog in docs/decisions/0002.
    //
    // Whitespace only (its autofix adds blank lines), but the diff touches
    // most files, so it lands in its own commit.
    // Findings when measured: require-readable-spacing 36,556.
    "anti-slop/require-readable-spacing": "off",

    // These prefer a different form than the one the repo writes (function
    // declarations, keys in reading order, interfaces); adopting one is a
    // repo-wide codemod.
    // Findings when measured: sort-keys 21,748, func-style 5,465,
    // method-signature-style 1,896, consistent-type-specifier-style 1,826,
    // no-await-expression-member 1,472, switch-case-braces 593,
    // prefer-named-capture-group 488, no-use-before-define 476,
    // prefer-destructuring 436, catch-error-name 249,
    // consistent-type-definitions 202, no-nested-ternary 200, no-plusplus 123,
    // import-style 120, no-bitwise 54, no-array-for-each 28, no-eq-null 7.
    // no-array-reduce (8) flags folds that compose middleware or chain
    // results, which read clearer as a fold than as a loop.
    // prefer-ternary (4) flags branches that each await a call with effects.
    // no-duplicate-imports (35) also flags the `import type` line the repo
    // keeps apart from the value import; import/no-duplicates covers the rest.
    // prefer-export-from (27) has no autofix, and Next.js route exports such
    // as `export const size = ogSize` must stay declarations.
    // no-inferrable-types (25) flags exported template constants, which
    // isolatedDeclarations requires to carry their type.
    "eslint/sort-keys": "off",
    "eslint/func-style": "off",
    "typescript/method-signature-style": "off",
    "import/consistent-type-specifier-style": "off",
    "unicorn/no-await-expression-member": "off",
    "unicorn/switch-case-braces": "off",
    "eslint/prefer-named-capture-group": "off",
    "eslint/no-use-before-define": "off",
    "eslint/prefer-destructuring": "off",
    "unicorn/catch-error-name": "off",
    "typescript/consistent-type-definitions": "off",
    "eslint/no-nested-ternary": "off",
    "eslint/no-plusplus": "off",
    "unicorn/import-style": "off",
    "eslint/no-bitwise": "off",
    "eslint/no-duplicate-imports": "off",
    "unicorn/no-array-for-each": "off",
    "unicorn/prefer-export-from": "off",
    "typescript/no-inferrable-types": "off",
    "eslint/no-eq-null": "off",
    "unicorn/no-array-reduce": "off",
    "unicorn/prefer-ternary": "off",

    // Each finding needs reading first: some are deliberate (Promise
    // constructors around callback APIs, bitwise hashing, empty fakes), others
    // are worth fixing.
    // Findings when measured: prefer-await-to-then 140, avoid-new 114,
    // complexity 110, no-void 98, no-array-filter-map 71, no-module-mocking 59,
    // prefer-await-to-callbacks 50, callback-return 44, prefer-structured-clone
    // 22, no-invalid-void-type 21, param-names 18, no-dynamic-delete 17,
    // class-methods-use-this 17, no-empty-object-type 16,
    // custom-error-definition 16, no-empty-function 15,
    // no-unreadable-array-destructuring 14.
    // These stay off because every finding is deliberate: throw-new-error (7)
    // flags `extends TaggedError("X")` class factories, default-param-last
    // (6) flags callbacks whose positions an interface fixes, prefer-catch (5)
    // flags `.then(onOk, onError)`, where onError must not see onOk throw,
    // no-return-wrap (3) flags `Promise.resolve` around a result that may be
    // synchronous, and no-barrel-file (1) flags the CLI entry.
    "promise/prefer-await-to-then": "off",
    "promise/avoid-new": "off",
    "eslint/complexity": "off",
    "eslint/no-void": "off",
    "anti-slop/no-array-filter-map": "off",
    "anti-slop/no-module-mocking": "off",
    "promise/prefer-await-to-callbacks": "off",
    "node/callback-return": "off",
    "unicorn/prefer-structured-clone": "off",
    "typescript/no-invalid-void-type": "off",
    "promise/param-names": "off",
    "typescript/no-dynamic-delete": "off",
    "eslint/class-methods-use-this": "off",
    "typescript/no-empty-object-type": "off",
    "unicorn/custom-error-definition": "off",
    "eslint/no-empty-function": "off",
    "unicorn/no-unreadable-array-destructuring": "off",
    "unicorn/throw-new-error": "off",
    "eslint/default-param-last": "off",
    "promise/prefer-catch": "off",
    "promise/no-return-wrap": "off",
    "oxc/no-barrel-file": "off",
  },
  overrides: [
    {
      files: testFiles,
      plugins: ["vitest"],
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

        // Ultracite's matcher and layout preferences differ from how the suites
        // assert (`toEqual`, `.rejects`, several expects per case); each is a
        // codemod across the tests. Backlog in docs/decisions/0002.
        // Findings when measured: prefer-strict-equal 5,619,
        // prefer-expect-resolves 4,118, max-expects 3,996, prefer-to-be-truthy
        // 925, prefer-describe-function-title 752, prefer-to-be-falsy 708,
        // prefer-called-once 153, padding-around-after-all-blocks 119,
        // require-top-level-describe 71, prefer-import-in-mock 56,
        // consistent-test-it 25, prefer-to-be 25, prefer-called-with 24,
        // prefer-to-have-length 23, prefer-expect-type-of 20,
        // prefer-mock-return-shorthand 12, padding-around-test-blocks 11,
        // consistent-test-filename 7, prefer-importing-vitest-globals 7,
        // prefer-mock-promise-shorthand 5, prefer-hooks-in-order 4, prefer-each
        // 3, prefer-comparison-matcher 2, prefer-to-contain 2.
        "vitest/prefer-strict-equal": "off",
        "vitest/prefer-expect-resolves": "off",
        "vitest/max-expects": "off",
        "vitest/prefer-to-be-truthy": "off",
        "vitest/prefer-describe-function-title": "off",
        "vitest/prefer-to-be-falsy": "off",
        "vitest/prefer-called-once": "off",
        "vitest/padding-around-after-all-blocks": "off",
        "vitest/require-top-level-describe": "off",
        "vitest/prefer-import-in-mock": "off",
        "vitest/consistent-test-it": "off",
        "vitest/prefer-to-be": "off",
        "vitest/prefer-called-with": "off",
        "vitest/prefer-to-have-length": "off",
        "vitest/prefer-expect-type-of": "off",
        "vitest/prefer-mock-return-shorthand": "off",
        "vitest/padding-around-test-blocks": "off",
        "vitest/consistent-test-filename": "off",
        "vitest/prefer-importing-vitest-globals": "off",
        "vitest/prefer-mock-promise-shorthand": "off",
        "vitest/prefer-hooks-in-order": "off",
        "vitest/prefer-each": "off",
        "vitest/prefer-comparison-matcher": "off",
        "vitest/prefer-to-contain": "off",
      },
    },
    {
      files: ["**/e2e/**/*.spec.ts"],
      jsPlugins: [
        { name: "playwright", specifier: plugin("eslint-plugin-playwright") },
      ],
      rules: {
        ...playwrightRules,
        "playwright/expect-expect": [
          "error",
          { assertFunctionNames: ["expectInstant"] },
        ],
        // Role-driven cases skip a page the role can't see inside one test,
        // like the Vitest suites; 2 findings each when measured.
        "playwright/no-conditional-in-test": "off",
        "playwright/no-conditional-expect": "off",
      },
    },
    {
      // Config files are loaded through their default export.
      files: ["*.config.ts", "*.config.mts", "knip.mts"],
      rules: { "import/no-default-export": "off" },
    },
    {
      // Repo scripts and app env modules are the env boundary.
      files: ["scripts/**", "**/env.ts"],
      rules: { "node/no-process-env": "off" },
    },
  ],
});

export default config;
