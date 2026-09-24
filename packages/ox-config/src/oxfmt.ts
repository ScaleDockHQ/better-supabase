import { type OxfmtConfig, defineConfig } from 'oxfmt';

const ignorePatterns: readonly string[] = [
  '**/node_modules/**',
  '**/.turbo/**',
  '**/dist/**',
  '**/.next/**',
  '**/.source/**',
  '**/coverage/**',
  '**/*.mdx',
];

export interface OxfmtOptions {
  /** Extra gitignore-style patterns, rooted at the consuming config file. */
  readonly ignorePatterns?: readonly string[];
}

/**
 * Shared Oxfmt configuration. Oxfmt has no `extends`, so this is a factory:
 * formatting options are fixed and only the ignore list may differ.
 */
export function oxfmt(options: OxfmtOptions = {}): OxfmtConfig {
  return defineConfig({
    printWidth: 80,
    semi: true,
    singleQuote: true,
    trailingComma: 'all',
    ignorePatterns: [...ignorePatterns, ...(options.ignorePatterns ?? [])],
    sortImports: {
      groups: [
        'type-import',
        ['value-builtin', 'value-external'],
        'type-internal',
        'value-internal',
        ['type-parent', 'type-sibling', 'type-index'],
        ['value-parent', 'value-sibling', 'value-index'],
        'unknown',
      ],
    },
    sortPackageJson: {
      sortScripts: true,
    },
  });
}
