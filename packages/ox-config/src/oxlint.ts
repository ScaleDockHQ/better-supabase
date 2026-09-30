import { fileURLToPath } from 'node:url';
import { type OxlintConfig, defineConfig } from 'oxlint';

/**
 * Build output and caches that no workspace should lint. A consumer's own
 * `ignorePatterns` replaces the inherited list, so spread this constant first.
 */
export const ignorePatterns: readonly string[] = [
  '**/{dist,.next,.source,coverage,.turbo,node_modules}/**',
];

/**
 * Imports that the one-library-per-concern rule keeps out of the repo. A
 * `no-restricted-imports` override replaces the whole rule, so overrides
 * spread these in.
 */
export const restrictedImportPaths: { name: string; message: string }[] = [
  { name: 'vaul', message: 'Use the shadcn Drawer on Base UI.' },
  { name: 'openai', message: 'Call models through the AI SDK and AI Gateway.' },
  {
    name: '@anthropic-ai/sdk',
    message: 'Call models through the AI SDK and AI Gateway.',
  },
  {
    name: '@google/genai',
    message: 'Call models through the AI SDK and AI Gateway.',
  },
];

export const restrictedImportPatterns: { group: string[]; message: string }[] =
  [
    { group: ['@radix-ui/*'], message: 'Use Base UI primitives.' },
    {
      group: ['@ai-sdk/*', '!@ai-sdk/react', '!@ai-sdk/valibot'],
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
    'eslint',
    'typescript',
    'oxc',
    'unicorn',
    'import',
    'node',
    'promise',
  ],
  jsPlugins: [
    { name: 'turbo', specifier: plugin('eslint-plugin-turbo') },
    { name: 'anti-slop', specifier: plugin('./anti-slop/index.ts') },
  ],
  categories: {
    correctness: 'error',
    suspicious: 'error',
    perf: 'error',
  },
  options: {
    typeAware: true,
    denyWarnings: true,
    reportUnusedDisableDirectives: 'error',
  },
  rules: {
    'no-eval': 'error',
    'no-implied-eval': 'error',
    'no-new-func': 'error',
    'no-empty': 'error',
    eqeqeq: ['error', 'always', { null: 'ignore' }],
    'no-restricted-imports': [
      'error',
      {
        paths: [...restrictedImportPaths],
        patterns: [...restrictedImportPatterns],
      },
    ],
    'import/no-cycle': 'error',
    'import/no-unassigned-import': [
      'error',
      { allow: ['**/*.css', 'server-only', 'client-only'] },
    ],
    'node/no-process-env': 'error',
    'turbo/no-undeclared-env-vars': 'error',
    'unicorn/prefer-node-protocol': 'error',

    'typescript/switch-exhaustiveness-check': 'error',
    'typescript/only-throw-error': 'error',
    'typescript/return-await': ['error', 'in-try-catch'],
    'typescript/unbound-method': 'error',
    'typescript/await-thenable': 'error',
    'typescript/consistent-type-imports': 'error',
    'typescript/no-explicit-any': 'error',
    'typescript/no-misused-promises': 'error',
    'typescript/no-floating-promises': 'error',
    'typescript/no-deprecated': 'error',
    // 335 findings when measured (222 in tests). Each needs a guard or a
    // narrower type; tracked as backlog in docs/decisions/0002.
    'typescript/no-non-null-assertion': 'off',
    'typescript/prefer-optional-chain': 'error',
    'typescript/prefer-nullish-coalescing': 'error',
    'typescript/no-unsafe-argument': 'error',
    'typescript/no-unsafe-assignment': 'error',
    'typescript/no-unsafe-call': 'error',
    'typescript/no-unsafe-member-access': 'error',
    'typescript/no-unsafe-return': 'error',
    'typescript/no-unsafe-enum-comparison': 'error',
    'typescript/no-unsafe-unary-minus': 'error',
    'typescript/no-unsafe-declaration-merging': 'error',
    'typescript/no-unsafe-function-type': 'error',
    'typescript/no-unnecessary-condition': 'error',
    // 426 findings when measured, 316 of them `if (text)` checks where the
    // empty string is meant to be falsy. Rewriting them changes behavior one
    // by one; tracked as backlog in docs/decisions/0002.
    'typescript/strict-boolean-expressions': 'off',
    'typescript/no-unnecessary-type-assertion': 'error',
    'typescript/no-unnecessary-type-arguments': 'error',
    'typescript/no-unnecessary-template-expression': 'error',
    'typescript/no-redundant-type-constituents': 'error',
    'typescript/restrict-template-expressions': 'error',

    'anti-slop/no-chained-type-assertions': 'error',
    'anti-slop/no-module-mocking': 'error',
    'anti-slop/no-reflect-apply': 'error',
    'anti-slop/no-reflect-get': 'error',
    'anti-slop/no-widen-then-assert': 'error',
    // 470 unannotated assertions when measured (285 outside tests). New code
    // follows the AGENTS.md convention; turn this on once the backlog is gone.
    'anti-slop/require-safety-comment-for-type-assertion': 'off',

    // Shadowing a name in a nested scope is how the query builders read.
    'eslint/no-shadow': 'off',
    // `toSorted` and `toReversed` copies are not needed on local arrays.
    'unicorn/no-array-sort': 'off',
    'unicorn/no-array-reverse': 'off',
    // Migrations, pages and retries run in order on purpose.
    'eslint/no-await-in-loop': 'off',
    // Closures next to their single caller read better than hoisted helpers.
    'unicorn/consistent-function-scoping': 'off',
    // Row and option objects are small; spreading them is not a hot path.
    'oxc/no-map-spread': 'off',
    'oxc/no-accumulating-spread': 'off',
    // 402 findings when measured: generic trees, decoded JSON and the
    // isolatedDeclarations boundary need assertions. AGENTS.md asks for a
    // `SAFETY:` comment on each new one instead.
    'typescript/no-unsafe-type-assertion': 'off',
    // `query<R>(): Promise<{ rows: R[] }>` style return-only generics are
    // the caller-supplied row type, not an unused parameter.
    'typescript/no-unnecessary-type-parameters': 'off',
    // 27 findings when measured, all `String(unknown)` for SQL literals,
    // headers, form values and error text, where that is the intent.
    'typescript/no-base-to-string': 'off',
    // `Record<never, never>` is the deliberate "no extra fields" marker in
    // the DbError detail map and in conditional types.
    'typescript/no-generated-empty-object-type': 'off',
    // Fire-and-forget `.then()` side effects in realtime subscriptions.
    'promise/always-return': 'off',
    'promise/no-promise-in-callback': 'off',
    // Realtime and storage wrap `on*` handler properties of the SDK objects.
    'unicorn/prefer-add-event-listener': 'off',
    // Spreading an iterable into a fresh array is how readonly inputs copy.
    'unicorn/no-useless-spread': 'off',
  },
});

/**
 * Code that runs on Node: CLIs, scripts, servers and tests. Node built-ins
 * are fine here; runtime library entries restrict them separately.
 */
export const node: OxlintConfig = defineConfig({
  env: { node: true },
  rules: {
    'node/no-exports-assign': 'error',
    'node/no-new-require': 'error',
    'node/no-path-concat': 'error',
  },
});

/** Published packages: named exports only, so tree shaking and docs work. */
export const library: OxlintConfig = defineConfig({
  rules: {
    'import/no-default-export': 'error',
  },
  overrides: [
    {
      // Tool configs are loaded through their default export.
      files: ['*.config.ts', '*.config.mts'],
      rules: { 'import/no-default-export': 'off' },
    },
  ],
});

const reactRules: OxlintConfig['rules'] = {
  // The automatic JSX runtime (`jsx: react-jsx`) needs no React import.
  'react/react-in-jsx-scope': 'off',
  'react/rules-of-hooks': 'error',
  'react/exhaustive-deps': 'error',
  'react/jsx-key': 'error',
  'react/jsx-no-target-blank': 'error',
  'react/no-danger-with-children': 'error',
  'react/no-array-index-key': 'error',
  'react/self-closing-comp': 'error',
  'react/jsx-no-useless-fragment': 'error',
  'react/no-unknown-property': 'error',
  'react-doctor/no-derived-state-effect': 'error',
  'react-doctor/no-fetch-in-effect': 'error',
  'react-doctor/no-effect-chain': 'error',
  'react-doctor/no-effect-event-handler': 'error',
  'react-doctor/no-mirror-prop-effect': 'error',
  'react-doctor/no-self-updating-effect': 'error',
  'react-doctor/no-async-effect-callback': 'error',
  'react-doctor/no-set-state-after-await-in-effect': 'error',
  'react-doctor/effect-needs-cleanup': 'error',
  'react-doctor/effect-listener-cleanup-mismatch': 'error',
  'react-doctor/no-prop-callback-in-effect': 'error',
};

const a11yRules = [
  'alt-text',
  'anchor-has-content',
  'anchor-is-valid',
  'aria-activedescendant-has-tabindex',
  'aria-props',
  'aria-proptypes',
  'aria-role',
  'aria-unsupported-elements',
  'autocomplete-valid',
  'click-events-have-key-events',
  'heading-has-content',
  'html-has-lang',
  'iframe-has-title',
  'img-redundant-alt',
  'label-has-associated-control',
  'lang',
  'media-has-caption',
  'mouse-events-have-key-events',
  'no-access-key',
  'no-aria-hidden-on-focusable',
  'no-autofocus',
  'no-distracting-elements',
  'no-noninteractive-tabindex',
  'no-redundant-roles',
  'prefer-tag-over-role',
  'role-has-required-aria-props',
  'role-supports-aria-props',
  'scope',
  'tabindex-no-positive',
] as const;

/** React components: hooks, effects and every jsx-a11y rule at error. */
export const react: OxlintConfig = defineConfig({
  plugins: ['react', 'jsx-a11y'],
  jsPlugins: [
    { name: 'react-doctor', specifier: plugin('oxlint-plugin-react-doctor') },
  ],
  env: { browser: true },
  rules: {
    ...reactRules,
    ...Object.fromEntries(
      a11yRules.map((rule) => [`jsx-a11y/${rule}`, 'error']),
    ),
  },
});

/** Tailwind design system rules for apps that own shadcn components. */
export const shadcn: OxlintConfig = defineConfig({
  jsPlugins: [{ name: 'shadcn', specifier: plugin('@shadcn/lint') }],
  rules: {
    'shadcn/no-inline-styles': 'error',
    'shadcn/no-raw-colors': 'error',
    'shadcn/no-arbitrary-values': 'error',
    'shadcn/no-unknown-classes': 'error',
    'shadcn/require-static-classes': 'error',
  },
});

const testFiles = [
  '**/tests/**/*.{ts,tsx}',
  '**/*.{test,spec}.{ts,tsx}',
  '**/*.test-d.ts',
];

/** Vitest suites, unit to integration, and `expectTypeOf` type tests. */
export const test: OxlintConfig = defineConfig({
  plugins: ['vitest'],
  overrides: [
    {
      files: testFiles,
      rules: {
        'vitest/no-focused-tests': 'error',
        'vitest/no-disabled-tests': 'error',
        // Tests await in `expect(...).rejects` and fire promises on purpose.
        'typescript/no-floating-promises': 'off',
        'typescript/no-misused-promises': 'off',
        // Plain `vi.fn()` spies stand in for callbacks of any shape.
        'vitest/require-mock-type-parameters': 'off',
        // Table-driven cases branch on the case inside one `it`.
        'vitest/no-conditional-tests': 'off',
        // Type tests assert with `expectTypeOf`, which the rule cannot see.
        'vitest/expect-expect': 'off',
        // Tests hand fake clients and spans to typed APIs on purpose.
        'anti-slop/no-chained-type-assertions': 'off',
        // Fixtures read the local stack's env with defaults.
        'node/no-process-env': 'off',
        // Vitest asymmetric matchers (`expect.any`, `expect.stringContaining`)
        // and `Response.json()` are typed `any`; 60 findings when measured.
        'typescript/no-unsafe-assignment': 'off',
        'typescript/no-unsafe-member-access': 'off',
        'typescript/no-unsafe-argument': 'off',
        'typescript/no-unsafe-call': 'off',
        'typescript/no-unsafe-return': 'off',
      },
    },
  ],
});

/** Playwright suites. */
export const playwright: OxlintConfig = defineConfig({
  jsPlugins: [
    { name: 'playwright', specifier: plugin('eslint-plugin-playwright') },
  ],
  overrides: [
    {
      files: testFiles,
      rules: {
        'playwright/no-focused-test': 'error',
        'playwright/no-skipped-test': 'error',
        'playwright/no-wait-for-timeout': 'error',
        'playwright/no-page-pause': 'error',
        'playwright/missing-playwright-await': 'error',
      },
    },
  ],
});
