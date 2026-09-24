import { base, ignorePatterns } from '@better-supabase/ox-config/oxlint';
import { defineConfig } from 'oxlint';

export default defineConfig({
  extends: [base],
  ignorePatterns: [
    ...ignorePatterns,
    '.agents/**',
    '.cursor/**',
    '.claude/**',
    '**/*.generated.ts',
    '**/database.types.ts',
  ],
  options: {
    typeAware: true,
  },
  overrides: [
    {
      files: ['packages/better-supabase/src/**/*.{ts,tsx}'],
      rules: {
        'import/no-default-export': 'error',
        'no-underscore-dangle': ['error', { allow: ['_count'] }],
      },
    },
    {
      // ESLint and oxlint load plugins from the module's default export.
      files: ['packages/better-supabase/src/lint/index.ts'],
      rules: {
        'import/no-default-export': 'off',
      },
    },
    {
      files: ['**/*.{test,spec}.{ts,tsx}', '**/*.test-d.ts', 'tests/**/*.ts'],
      rules: {
        'typescript/no-floating-promises': 'off',
        'typescript/no-misused-promises': 'off',
        'vitest/require-mock-type-parameters': 'off',
        'vitest/no-conditional-tests': 'off',
        'vitest/expect-expect': 'off',
      },
    },
  ],
});
