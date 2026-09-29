import { type OxlintConfig, defineConfig } from 'oxlint';

/**
 * Build output and caches that no workspace should lint. A consumer's own
 * `ignorePatterns` replaces the inherited list, so spread this constant first.
 */
export const ignorePatterns: readonly string[] = [
  '**/{dist,.next,.source,coverage,.turbo,node_modules}/**',
];

/**
 * Shared Oxlint baseline. Type-aware linting is switched on once, from the
 * root config, over the whole repository.
 */
export const base: OxlintConfig = defineConfig({
  ignorePatterns: [...ignorePatterns],
  plugins: [
    'eslint',
    'unicorn',
    'typescript',
    'oxc',
    'import',
    'vitest',
    'node',
    'promise',
  ],
  categories: {
    correctness: 'error',
    suspicious: 'error',
    perf: 'error',
  },
  options: {
    reportUnusedDisableDirectives: 'error',
  },
  rules: {
    'no-eval': 'error',
    'no-implied-eval': 'error',
    'no-new-func': 'error',
    eqeqeq: ['error', 'always', { null: 'ignore' }],
    'typescript/no-explicit-any': 'error',
    'typescript/no-floating-promises': 'error',
    'typescript/no-misused-promises': 'error',
    'typescript/await-thenable': 'error',
    'typescript/switch-exhaustiveness-check': 'error',
    'typescript/consistent-type-imports': 'error',
    'typescript/only-throw-error': 'error',
    'typescript/return-await': ['error', 'in-try-catch'],
    'typescript/no-deprecated': 'error',
    'typescript/no-unnecessary-type-assertion': 'error',
    'typescript/no-unnecessary-type-arguments': 'error',
    'typescript/no-unnecessary-template-expression': 'error',
    'typescript/no-redundant-type-constituents': 'error',
    'typescript/restrict-template-expressions': 'error',
    'unicorn/prefer-node-protocol': 'error',
    'import/no-cycle': 'error',
    'eslint/no-shadow': 'off',
    'unicorn/no-array-sort': 'off',
    'unicorn/no-array-reverse': 'off',
    'eslint/no-await-in-loop': 'off',
    'unicorn/consistent-function-scoping': 'off',
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
    'unicorn/prefer-add-event-listener': 'off',
    'unicorn/no-useless-spread': 'off',
    'import/no-unassigned-import': 'off',
  },
});
