import { existsSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';

export type Framework =
  | 'next'
  | 'hono'
  | 'orpc'
  | 'vite'
  | 'expo'
  | 'tanstack-query';
export type PackageManager = 'pnpm' | 'npm' | 'yarn' | 'bun';

export interface Project {
  readonly root: string;
  readonly name: string | undefined;
  readonly frameworks: readonly Framework[];
  readonly packageManager: PackageManager;
  /** Installed dependencies (all kinds) to version ranges. */
  readonly dependencies: Readonly<Record<string, string>>;
  /** `src` when the project has a `src/` directory, otherwise `.`. */
  readonly srcDir: string;
  /** Whether relative imports keep their `.ts` extension. */
  readonly tsExtensions: boolean;
  readonly hasSupabase: boolean;
}

const FRAMEWORK_PACKAGES: readonly (readonly [Framework, string])[] = [
  ['next', 'next'],
  ['hono', 'hono'],
  ['orpc', '@orpc/server'],
  ['vite', 'vite'],
  ['expo', 'expo'],
  ['tanstack-query', '@tanstack/react-query'],
];

async function readJson(
  path: string,
): Promise<Record<string, unknown> | undefined> {
  if (!existsSync(path)) return undefined;
  const text = await readFile(path, 'utf8');
  try {
    return JSON.parse(
      text.replace(/^\s*\/\/.*$/gm, '').replace(/,(\s*[}\]])/g, '$1'),
    ) as Record<string, unknown>;
  } catch {
    return undefined;
  }
}

function packageManager(root: string, declared: unknown): PackageManager {
  if (typeof declared === 'string') {
    const name = declared.split('@')[0];
    if (name === 'pnpm' || name === 'npm' || name === 'yarn' || name === 'bun')
      return name;
  }
  if (existsSync(join(root, 'pnpm-lock.yaml'))) return 'pnpm';
  if (existsSync(join(root, 'bun.lock')) || existsSync(join(root, 'bun.lockb')))
    return 'bun';
  if (existsSync(join(root, 'yarn.lock'))) return 'yarn';
  return existsSync(join(root, 'package-lock.json')) ? 'npm' : 'pnpm';
}

export async function detectProject(root: string): Promise<Project> {
  const pkg = (await readJson(join(root, 'package.json'))) ?? {};
  const dependencies: Record<string, string> = {};
  for (const field of ['peerDependencies', 'devDependencies', 'dependencies']) {
    Object.assign(dependencies, pkg[field] ?? {});
  }
  const tsconfig = await readJson(join(root, 'tsconfig.json'));
  const options = (tsconfig?.['compilerOptions'] ?? {}) as Record<
    string,
    unknown
  >;
  return {
    root,
    name: typeof pkg['name'] === 'string' ? pkg['name'] : undefined,
    frameworks: FRAMEWORK_PACKAGES.filter(
      ([, name]) => name in dependencies,
    ).map(([framework]) => framework),
    packageManager: packageManager(root, pkg['packageManager']),
    dependencies,
    srcDir: existsSync(join(root, 'src')) ? 'src' : '.',
    tsExtensions:
      options['allowImportingTsExtensions'] === true ||
      options['rewriteRelativeImportExtensions'] === true,
    hasSupabase: existsSync(join(root, 'supabase', 'config.toml')),
  };
}

export function installCommand(
  manager: PackageManager,
  packages: readonly string[],
  dev = false,
): string {
  const list = packages.join(' ');
  switch (manager) {
    case 'pnpm':
      return `pnpm add ${dev ? '-D ' : ''}${list}`;
    case 'bun':
      return `bun add ${dev ? '-d ' : ''}${list}`;
    case 'yarn':
      return `yarn add ${dev ? '-D ' : ''}${list}`;
    case 'npm':
      return `npm install ${dev ? '-D ' : ''}${list}`;
    default: {
      const unreachable: never = manager;
      return unreachable;
    }
  }
}

/** Env variable prefix the framework exposes to the browser. */
export function publicPrefix(project: Project): string {
  if (project.frameworks.includes('next')) return 'NEXT_PUBLIC_';
  if (project.frameworks.includes('expo')) return 'EXPO_PUBLIC_';
  if (project.frameworks.includes('vite')) return 'VITE_';
  return '';
}
