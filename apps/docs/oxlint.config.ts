import {
  core,
  node,
  react,
  test,
  ignorePatterns,
} from '@better-supabase/ox-config/oxlint';
import { defineConfig } from 'oxlint';

export default defineConfig({
  extends: [core, node, react, test],
  ignorePatterns: [
    ...ignorePatterns,
    '**/*.generated.ts',
    '**/generated.ts',
    '**/generated-*.ts',
    '**/database.types.ts',
  ],
});
