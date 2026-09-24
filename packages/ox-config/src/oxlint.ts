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
  plugins: ['eslint', 'unicorn', 'typescript', 'oxc', 'import', 'vitest'],
  categories: {
    correctness: 'error',
    suspicious: 'error',
    perf: 'error',
  },
  rules: {
    'no-eval': 'error',
    'no-implied-eval': 'error',
    'no-new-func': 'error',
    'typescript/no-explicit-any': 'error',
    'typescript/no-floating-promises': 'error',
    'typescript/no-misused-promises': 'error',
    'typescript/await-thenable': 'error',
    'typescript/switch-exhaustiveness-check': 'error',
    'typescript/consistent-type-imports': 'error',
    'import/no-cycle': 'error',
    'eslint/no-shadow': 'off',
    'unicorn/no-array-sort': 'off',
    'unicorn/no-array-reverse': 'off',
    'eslint/no-await-in-loop': 'off',
    'unicorn/consistent-function-scoping': 'off',
    'oxc/no-map-spread': 'off',
    'oxc/no-accumulating-spread': 'off',
    'typescript/no-unsafe-type-assertion': 'off',
    'typescript/no-unnecessary-type-parameters': 'off',
    'typescript/no-unnecessary-type-arguments': 'off',
    'typescript/no-unnecessary-type-assertion': 'off',
    'typescript/no-unnecessary-template-expression': 'off',
    'typescript/no-redundant-type-constituents': 'off',
    'typescript/no-base-to-string': 'off',
    'typescript/restrict-template-expressions': 'off',
    'unicorn/prefer-add-event-listener': 'off',
    'unicorn/no-useless-spread': 'off',
    'import/no-unassigned-import': 'off',
  },
});
