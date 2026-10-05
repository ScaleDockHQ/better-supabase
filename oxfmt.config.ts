import { oxfmt } from "@better-supabase/ox-config/oxfmt";

export default oxfmt({
  ignorePatterns: [
    "**/.agents/**",
    "**/.cursor/**",
    "**/.claude/**",
    "**/*.generated.ts",
    "**/database.types.ts",
    "packages/better-supabase/tests/fixtures/generated*",
    "apps/examples/**/lib/supabase/generated.*",
    "apps/examples/monorepo/runtime/src/generated.*",
    "tests/validation-*/src/**/generated.*",
    "packages/better-supabase/api/**",
    "packages/better-supabase/tests/standards/schemas/**",
    "apps/marketing/components/ui/**",
    "apps/marketing/components/reui/**",
    "CHANGELOG.md",
    "pnpm-lock.yaml",
  ],
});
