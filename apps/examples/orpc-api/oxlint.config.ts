import {
  core,
  node,
  test,
  ignorePatterns,
} from '@better-supabase/ox-config/oxlint';
import { defineConfig } from 'oxlint';

export default defineConfig({
  extends: [core, node, test],
  ignorePatterns: [
    ...ignorePatterns,
    '**/*.generated.ts',
    '**/generated.ts',
    '**/generated-*.ts',
    '**/database.types.ts',
  ],
  overrides: [
    {
      // Examples read env where they create the client, the way the
      // generated templates do, so they stay copyable.
      files: ['**/*.{ts,tsx}'],
      rules: { 'node/no-process-env': 'off' },
    },
  ],
});
