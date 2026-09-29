import { base, ignorePatterns } from '@better-supabase/ox-config/oxlint';
import path from 'node:path';
import { defineConfig } from 'oxlint';

export default defineConfig({
  extends: [base],
  ignorePatterns: [
    ...ignorePatterns,
    '.agents/**',
    '.cursor/**',
    '.claude/**',
    '**/*.generated.ts',
    // Generated files open with a blanket disable for consumers' linters.
    '**/lib/supabase/generated.ts',
    'tests/**/generated.ts',
    'packages/better-supabase/src/fixtures/generated*.ts',
    '**/database.types.ts',
    'apps/marketing/components/ui/**',
    'apps/marketing/components/reui/**',
  ],
  options: {
    typeAware: true,
  },
  jsPlugins: [
    {
      name: 'anti-slop',
      specifier: path.resolve(
        import.meta.dirname,
        'packages/ox-config/src/anti-slop/index.ts',
      ),
    },
  ],
  rules: {
    'anti-slop/no-chained-type-assertions': 'error',
    'anti-slop/no-module-mocking': 'error',
    'anti-slop/no-reflect-apply': 'error',
    'anti-slop/no-reflect-get': 'error',
    'anti-slop/no-widen-then-assert': 'error',
    // 470 unannotated assertions when measured (285 outside tests). New code
    // follows the AGENTS.md convention; turn this on once the backlog is gone.
    'anti-slop/require-safety-comment-for-type-assertion': 'off',
  },
  overrides: [
    {
      files: ['packages/better-supabase/src/**/*.{ts,tsx}'],
      rules: {
        'import/no-default-export': 'error',
      },
    },
    {
      // Relation counts and aggregates are part of the repository API.
      files: [
        'packages/better-supabase/src/**/*.{ts,tsx}',
        'apps/examples/**/*.{ts,tsx}',
      ],
      rules: {
        'no-underscore-dangle': [
          'error',
          { allow: ['_count', '_sum', '_avg', '_min', '_max'] },
        ],
      },
    },
    {
      // Runtime entries run on every WinterTC runtime (AGENTS.md invariant 6).
      files: [
        'packages/better-supabase/src/index.ts',
        'packages/better-supabase/src/{auth,casing,client,compile,config,core,edge,env,events,generators,hono,ir,jobs,lint,list,mcp,next,openapi,orpc,otel,plugins,query,react,realtime,schema,server,sql,ssr,storage,webhooks}/**/*.{ts,tsx}',
      ],
      excludeFiles: ['**/*.test.ts', '**/*.test-d.ts'],
      rules: {
        'no-restricted-imports': [
          'error',
          {
            patterns: [
              {
                group: ['node:*'],
                message:
                  'Runtime entries import no Node built-ins; move this to cli, postgres or testing.',
              },
            ],
          },
        ],
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
        // Tests hand fake clients and spans to typed APIs on purpose.
        'anti-slop/no-chained-type-assertions': 'off',
      },
    },
  ],
});
