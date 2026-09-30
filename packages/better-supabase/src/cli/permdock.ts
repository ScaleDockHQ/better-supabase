import { existsSync } from 'node:fs';
import { resolve } from 'node:path';

const PERMDOCK_CONFIGS = [
  'permdock.config.ts',
  'permdock.config.mts',
  'permdock.config.js',
  'permdock.config.mjs',
] as const;

/** The PermDock config file in `root`, if there is one. */
export function permdockConfig(root: string): string | undefined {
  return PERMDOCK_CONFIGS.find((file) => existsSync(resolve(root, file)));
}
