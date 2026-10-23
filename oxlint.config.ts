import type { OxlintConfig } from "oxlint";

import playwright from "eslint-plugin-playwright";
import { fileURLToPath } from "node:url";
import { defineConfig } from "oxlint";
import antiSlop from "ultracite/oxlint/anti-slop";
import core from "ultracite/oxlint/core";
import { jsPluginSettings, selectJsPlugins } from "ultracite/oxlint/js-plugins";
import ultraciteNext from "ultracite/oxlint/next";
import ultraciteNextJsPlugins from "ultracite/oxlint/next/js-plugins";
import ultraciteReact from "ultracite/oxlint/react";
import ultraciteShadcn from "ultracite/oxlint/shadcn";
import vitest from "ultracite/oxlint/vitest";
import * as v from "valibot";

function plugin(specifier: string): string {
  return fileURLToPath(import.meta.resolve(specifier));
}

/**
 * Every config spreads these: a workspace's `ignorePatterns` replaces the
 * inherited list. `apps/docs/content/docs/build` is a docs section, not
 * output.
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
  "**/lib/supabase/records/**",
];

/**
 * Imports that the one-library-per-concern rule keeps out of the repo. A
 * `no-restricted-imports` override replaces the whole rule, so overrides spread
 * these in.
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

// The plugin types its configs with ESLint's types, and ESLint isn't
// installed (Oxlint runs the rules), so the config is parsed.
const FlatConfig = v.object({
  rules: v.optional(v.record(v.string(), v.unknown()), {}),
});

/** The recommended Playwright rules, all at error like every other rule. */
const playwrightRules: NonNullable<OxlintConfig["rules"]> = Object.fromEntries(
  Object.keys(v.parse(FlatConfig, playwright.configs["flat/recommended"]).rules)
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

/**
 * React components: Ultracite's react preset, react-doctor and the effect
 * rules.
 */
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
    // Findings when measured: function-component-definition 296,
    // js-combine-iterations 151, js-set-map-lookups 98, async-await-in-loop 75,
    // no-barrel-import 36, no-json-parse-stringify-clone 22,
    // server-sequential-independent-await 10,
    // prefer-module-scope-pure-function 6.
    "react/function-component-definition": "off",
    "react-doctor/js-combine-iterations": "off",
    "react-doctor/js-set-map-lookups": "off",
    "react-doctor/async-await-in-loop": "off",
    "react-doctor/no-barrel-import": "off",
    "react-doctor/no-json-parse-stringify-clone": "off",
    "react-doctor/server-sequential-independent-await": "off",
    "react-doctor/prefer-module-scope-pure-function": "off",
    // Read and kept, every finding deliberate. js-index-maps (4) and
    // js-cache-property-access (3) flag lookups over lists of a few entries.
    // async-defer-await (3) flags awaits that write a row or authenticate
    // before the early return. jsx-handler-names (4) flags state setters
    // passed straight to a handler prop. rerender-defer-reads-hook (3) flags
    // `usePathname()` read in a handler, where the path must come from the
    // Next.js router. no-giant-component (3) asks to split the CSV import,
    // work grid and order detail screens, a change per screen.
    "react-doctor/js-index-maps": "off",
    "react-doctor/js-cache-property-access": "off",
    "react-doctor/async-defer-await": "off",
    "react/jsx-handler-names": "off",
    "react-doctor/rerender-defer-reads-hook": "off",
    "react-doctor/no-giant-component": "off",
    // jsx-curly-brace-presence (2) flags `{"'a'"}` strings whose quotes
    // no-unescaped-entities rejects as bare JSX text.
    "react/jsx-curly-brace-presence": "off",
    // hook-use-state (3) flags `const [client] = useState(() => new
    // QueryClient())`, the lazy initial value that keeps one per mount.
    "react/hook-use-state": "off",
    // Fumadocs compiles each page to an `MDX` component.
    "react/jsx-pascal-case": ["error", { allowAllCaps: true }],
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
    // Findings when measured: no-restyle 399.
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

    // 2,231 findings when measured (1,862 in tests). Each needs a guard or a
    // narrower type; tracked as backlog in docs/decisions/0002.
    "typescript/no-non-null-assertion": "off",
    // 1,503 findings when measured (179 in tests), most of them `if (text)`
    // checks where the empty string is meant to be falsy. Rewriting them
    // changes behavior one by one; tracked as backlog in docs/decisions/0002.
    "typescript/strict-boolean-expressions": "off",
    // 1,836 findings when measured (1,120 in tests). Misuse (an unknown table, a role other
    // than authenticated or anon) throws synchronously before any I/O, and
    // tests assert that; `async` turns those throws into rejections.
    "typescript/promise-function-async": "off",
    // Shadowing a name in a nested scope is how the query builders read;
    // 147 findings when measured (69 in tests), each a rename by hand.
    "eslint/no-shadow": "off",
    // Migrations, pages and retries run in order on purpose; 663 findings
    // when measured.
    "eslint/no-await-in-loop": "off",
    // Closures next to their single caller read better than hoisted helpers;
    // 596 findings when measured.
    "unicorn/consistent-function-scoping": "off",
    // 1,671 findings when measured: generic trees, decoded JSON and the
    // isolatedDeclarations boundary need assertions. AGENTS.md asks for a
    // `SAFETY:` comment on each new one instead.
    "typescript/no-unsafe-type-assertion": "off",
    // `query<R>(): Promise<{ rows: R[] }>` style return-only generics are
    // the caller-supplied row type, not an unused parameter; 36 findings
    // when measured, most on published signatures.
    "typescript/no-unnecessary-type-parameters": "off",
    // 141 findings when measured, all `String(unknown)` for SQL literals,
    // headers, form values and error text, where that is the intent.
    "typescript/no-base-to-string": "off",
    // `Record<never, never>` is the deliberate "no extra fields" marker in
    // the DbError detail map and in conditional types; 232 findings when
    // measured.
    "typescript/no-generated-empty-object-type": "off",
    // The rule is written for Node-style callbacks; its 11 findings when
    // measured were all arrow functions that return a promise, such as
    // `execute: () => Promise.resolve(refuse())`.
    "promise/no-promise-in-callback": "off",
    // 9 findings when measured, all `for (const listener of [...listeners])`
    // style copies taken before a loop that may unsubscribe or delete.
    "unicorn/no-useless-spread": "off",
    // An explicit `undefined` argument or arrow body is how a call fills a
    // required `T | undefined` parameter or an `() => undefined` contract.
    "unicorn/no-useless-undefined": [
      "error",
      { checkArguments: false, checkArrowFunctionBody: false },
    ],
    // noImplicitReturns checks this with types, and the rule rejects the
    // bare `return;` that no-useless-undefined writes for `T | undefined`;
    // 81 findings when measured.
    "typescript/consistent-return": "off",
    // noImplicitReturns needs the final `return;` of a `T | undefined`
    // function (TS7030); 41 findings when measured, all that case.
    "eslint/no-useless-return": "off",
    // Not type-aware: it flags every `.match()` call, and 2 of the 3
    // findings when measured were custom path matchers.
    "unicorn/prefer-regexp-test": "off",
    // The 1,000-line limit of the repo standard, counting code only.
    "eslint/max-lines": [
      "error",
      { max: 1000, skipBlankLines: true, skipComments: true },
    ],
    // 10,176 findings when measured. Deep readonly on every parameter
    // fights the SDK types the library wraps; `readonly` arrays and
    // `Readonly<T>` are used where a function promises not to mutate.
    "typescript/prefer-readonly-parameter-types": "off",
    // 2,621 findings when measured. The `u` flag changes escape rules and
    // case folding per pattern, so each needs review; backlog in
    // docs/decisions/0002.
    "eslint/require-unicode-regexp": "off",
    // Duplicates typescript/require-await, which is type-aware (851 findings
    // when measured, the same sites).
    "eslint/require-await": "off",
    // 336 findings when measured, all `.map(parseRow)` style calls on typed
    // single-argument callbacks; the type-aware rules catch arity drift.
    "unicorn/no-array-callback-reference": "off",
    // 27 findings when measured, all deliberate: `string & {}` keeps literal
    // autocomplete, and `{}` is the empty default of generic arguments.
    "typescript/ban-types": "off",
    // 15 findings when measured, all a Valibot schema and its inferred type
    // sharing one name, which TypeScript resolves by declaration space.
    "eslint/no-redeclare": "off",
    // 12 findings when measured: an error class and its subclass, or a test
    // file's fixture classes, belong together.
    "eslint/max-classes-per-file": "off",
    // `cause` names a caught value when the handler also builds or returns
    // an `error` of its own, as in `{ error: toDbError(cause) }`.
    "unicorn/catch-error-name": ["error", { ignore: ["^cause$"] }],

    // Ultracite rules that fire on code written before it was adopted. Each
    // is its own follow-up change; backlog in docs/decisions/0002.
    //
    // These prefer a different form than the one the repo writes (function
    // declarations, keys in reading order, interfaces); adopting one is a
    // repo-wide codemod.
    // Findings when measured: sort-keys 22,476, func-style 5,625,
    // method-signature-style 2,106, no-await-expression-member 1,504,
    // no-use-before-define 603, prefer-named-capture-group 598,
    // prefer-destructuring 519, no-nested-ternary 314,
    // consistent-type-definitions 221, import-style 148.
    // consistent-type-definitions would turn types into interfaces, which
    // are not assignable to `Record<string, unknown>`.
    // no-array-reduce (8) flags folds that compose middleware or chain
    // results, which read clearer as a fold than as a loop.
    // prefer-ternary (4) flags branches that each await a call with effects.
    // prefer-export-from (27) has no autofix, and Next.js route exports such
    // as `export const size = ogSize` must stay declarations.
    // no-inferrable-types (25) flags exported template constants, which
    // isolatedDeclarations requires to carry their type.
    "eslint/sort-keys": "off",
    "eslint/func-style": "off",
    "typescript/method-signature-style": "off",
    "unicorn/no-await-expression-member": "off",
    "eslint/prefer-named-capture-group": "off",
    "eslint/no-use-before-define": "off",
    "eslint/prefer-destructuring": "off",
    "typescript/consistent-type-definitions": "off",
    "eslint/no-nested-ternary": "off",
    "unicorn/import-style": "off",
    "unicorn/prefer-export-from": "off",
    "typescript/no-inferrable-types": "off",
    "unicorn/no-array-reduce": "off",
    "unicorn/prefer-ternary": "off",

    // Each finding needs reading first: some are deliberate (Promise
    // constructors around callback APIs, empty fakes), others are worth
    // fixing.
    // Findings when measured: prefer-await-to-then 185, complexity 150,
    // avoid-new 123, no-void 105, no-array-filter-map 98, no-module-mocking
    // 59, prefer-await-to-callbacks 50, callback-return 45, param-names 18.
    // Read and kept, every finding deliberate:
    // prefer-structured-clone (23) flags JSON round trips that model the
    // wire, which `structuredClone` does not (it keeps `undefined` and Dates).
    // custom-error-definition (23) would rename exported classes such as
    // `DbException`. no-invalid-void-type (22) flags `| void` callback
    // returns that let a hook return nothing. no-empty-function (20) flags
    // no-op defaults. no-dynamic-delete (19) flags patch and record code that
    // removes a key. class-methods-use-this (17) flags methods that implement
    // an interface. no-empty-object-type (16) flags `= {}` generic defaults.
    // no-unreadable-array-destructuring (16) flags positional `ps` columns
    // and mock call arguments.
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
        // Plain `vi.fn()` spies stand in for callbacks of any shape; 753
        // findings when measured.
        "vitest/require-mock-type-parameters": "off",
        // Table-driven cases branch on the case inside one `it`; 1,495
        // no-conditional-in-test findings when measured.
        "vitest/no-conditional-tests": "off",
        "vitest/no-conditional-in-test": "off",
        // Suites are one file per module (AGENTS.md); 242 exceed 1,000 lines.
        "eslint/max-lines": "off",
        // Fakes implement async SDK methods without awaiting; 712
        // require-await findings when measured.
        "typescript/require-await": "off",
        // Tests reject and throw non-Error values to cover how the code
        // under test handles them; 27 findings when measured.
        "eslint/prefer-promise-reject-errors": "off",
        "typescript/prefer-promise-reject-errors": "off",
        "eslint/no-throw-literal": "off",
        // Spies and `vi.fn()` callbacks return values the caller ignores;
        // 233 strict-void-return findings when measured.
        "typescript/strict-void-return": "off",
        // Type tests assert with `expectTypeOf`, which the rule cannot see;
        // 67 findings when measured.
        "vitest/expect-expect": "off",
        // Tests hand fake clients and spans to typed APIs on purpose (213 and
        // 1,258 findings when measured).
        "anti-slop/no-chained-type-assertions": "off",
        "anti-slop/require-safety-comment-for-type-assertion": "off",
        // Fixtures read the local stack's env with defaults; 47 findings when
        // measured.
        "node/no-process-env": "off",
        // Vitest asymmetric matchers (`expect.any`, `expect.stringContaining`)
        // and `Response.json()` are typed `any`; 371 findings when measured.
        "typescript/no-unsafe-assignment": "off",
        "typescript/no-unsafe-member-access": "off",
        "typescript/no-unsafe-argument": "off",
        "typescript/no-unsafe-call": "off",
        "typescript/no-unsafe-return": "off",

        // Ultracite's matcher and layout preferences differ from how the suites
        // assert (`toEqual`, `.rejects`, several expects per case); each is a
        // codemod across the tests. Backlog in docs/decisions/0002.
        // Findings when measured: prefer-strict-equal 6,576,
        // prefer-expect-resolves 4,241, max-expects 4,068, prefer-to-be-truthy
        // 946, prefer-describe-function-title 892, prefer-to-be-falsy 734,
        // require-top-level-describe 88, prefer-expect-type-of 25,
        // consistent-test-filename 16. The autofixes of
        // prefer-describe-function-title and prefer-expect-type-of move a
        // method reference into `describe()` or `expect()`, which
        // typescript/unbound-method then rejects.
        "vitest/prefer-strict-equal": "off",
        "vitest/prefer-expect-resolves": "off",
        "vitest/max-expects": "off",
        "vitest/prefer-to-be-truthy": "off",
        "vitest/prefer-describe-function-title": "off",
        "vitest/prefer-to-be-falsy": "off",
        "vitest/require-top-level-describe": "off",
        "vitest/prefer-expect-type-of": "off",
        "vitest/consistent-test-filename": "off",
        // Its 3 findings compare base-62 rank keys, which are strings, and
        // `toBeLessThan` takes only numbers.
        "vitest/prefer-comparison-matcher": "off",
      },
    },
    {
      files: ["**/e2e/**/*.spec.ts"],
      // An override only sets rules of the plugins it lists.
      plugins: ["vitest"],
      jsPlugins: [
        { name: "playwright", specifier: plugin("eslint-plugin-playwright") },
      ],
      rules: {
        ...playwrightRules,
        // `test` and `expect` come from @playwright/test here, not Vitest.
        "vitest/prefer-importing-vitest-globals": "off",
        // `test` and `expect` come from @playwright/test here, not Vitest.
        "playwright/expect-expect": [
          "error",
          { assertFunctionNames: ["expectInstant"] },
        ],
        // Role-driven cases skip a page the role can't see inside one test,
        // like the Vitest suites; 2 findings each when measured.
        "playwright/no-conditional-in-test": "off",
        "playwright/no-conditional-expect": "off",
        // Playwright has no `test.each`; a loop is how it parametrises.
        "vitest/prefer-each": "off",
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
