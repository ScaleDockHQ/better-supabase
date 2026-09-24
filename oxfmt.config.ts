import { oxfmt } from '@better-supabase/ox-config/oxfmt';

export default oxfmt({
  ignorePatterns: [
    '**/.agents/**',
    '**/.cursor/**',
    '**/.claude/**',
    '**/*.generated.ts',
    '**/database.types.ts',
    'packages/better-supabase/src/fixtures/generated*',
    'apps/examples/**/lib/supabase/generated.ts',
    'packages/better-supabase/api/**',
    '**/*.md',
    'CHANGELOG.md',
    'pnpm-lock.yaml',
  ],
});
