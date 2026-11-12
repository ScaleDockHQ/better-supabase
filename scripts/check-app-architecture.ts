// Enforces the feature-sliced RSC architecture (ADR 0310) over the Next.js
// example app and the `init` fixture. Pages compose and stay synchronous,
// features take plain ids, queries and actions sit in files named after
// their folder, every async component has a sibling skeleton and the page
// owns the Suspense boundary. Exceptions are listed in
// `scripts/app-architecture-allow.json`; the check fails when an entry stops
// matching, so the list only shrinks.
// Run with `node scripts/check-app-architecture.ts [--print] [root...]`.
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { basename, dirname, join, relative, resolve } from "node:path";
import { argv, exit } from "node:process";

export interface Finding {
  readonly file: string;
  readonly rule: string;
  readonly message: string;
}

interface Allow {
  /** Roots that must exist; each holds `app/`, `features/` and `components/`. */
  readonly roots: readonly string[];
  /**
   * Roots checked as soon as the directory exists (the `init` fixture, once
   * `init` writes this layout), so a new one cannot land with findings.
   */
  readonly pendingRoots: readonly string[];
  /** Composite sections that nest sibling boundaries, with the reason. */
  readonly suspenseInFeatures: Readonly<Record<string, string>>;
  /** Files where connection() is allowed without a comment, with the reason. */
  readonly connection: Readonly<Record<string, string>>;
  readonly findings: readonly string[];
}

const ALLOW_FILE = "scripts/app-architecture-allow.json";
const SKIPPED = new Set(["node_modules", ".next", "dist", ".turbo"]);

const walk = (dir: string): string[] => {
  if (!existsSync(dir)) {
    return [];
  }

  const out: string[] = [];

  for (const name of readdirSync(dir)) {
    if (SKIPPED.has(name)) {
      continue;
    }

    const path = join(dir, name);

    if (statSync(path).isDirectory()) {
      out.push(...walk(path));
    } else if (/\.tsx?$/.test(name)) {
      out.push(path);
    }
  }

  return out;
};

const stripComments = (source: string): string =>
  source
    .replaceAll(/\/\*[\s\S]*?\*\//g, "")
    .replaceAll(/(^|[^:])\/\/.*$/gm, "$1");

const firstStatement = (source: string): string => {
  const body = stripComments(source).trimStart();

  return body.slice(0, 80);
};

const hasDirective = (source: string, directive: string): boolean =>
  new RegExp(`^["']${directive}["']`).test(firstStatement(source));

const ASYNC_COMPONENT =
  /export\s+(?:default\s+)?async\s+function\s+([A-Z]\w*)/g;

const asyncComponents = (source: string): string[] =>
  [...source.matchAll(ASYNC_COMPONENT)].map((match) => match[1] ?? "");

const resolveImport = (
  root: string,
  from: string,
  specifier: string,
): string | undefined => {
  let base: string;

  if (specifier.startsWith("@/")) {
    base = join(root, specifier.slice(2));
  } else if (specifier.startsWith(".")) {
    base = resolve(dirname(from), specifier);
  } else {
    return undefined;
  }

  for (const candidate of [
    `${base}.tsx`,
    `${base}.ts`,
    join(base, "index.tsx"),
  ]) {
    if (existsSync(candidate)) {
      return candidate;
    }
  }

  return undefined;
};

const featureOf = (rel: string): string | undefined => {
  const match = /^features\/([^/]+)\//.exec(rel);

  return match?.[1];
};

export const checkRoot = (root: string, allow: Allow): Finding[] => {
  const findings: Finding[] = [];

  const add = (file: string, rule: string, message: string): void => {
    findings.push({ file: relative(process.cwd(), file), rule, message });
  };

  const files = walk(root);

  const sources = new Map(
    files.map((file) => [file, readFileSync(file, "utf-8")]),
  );

  for (const [file, source] of sources) {
    const rel = relative(root, file);
    const name = file.slice(file.lastIndexOf("/") + 1);
    const code = stripComments(source);

    const isPage =
      /(^|\/)(page|layout)\.tsx$/.test(rel) && rel.startsWith("app/");

    const feature = featureOf(rel);

    // Pages of the signed-in app navigate instantly (ADR 0314): each one
    // exports `instant = true`, or states why not in an `// instant:` comment.
    if (/(^|\/)\(app\)\/(?:.+\/)?page\.tsx$/.test(rel)) {
      if (
        !/export\s+const\s+instant\s*=/.test(code) &&
        !/^\s*\/\/\s*instant:\s*\S/m.test(source)
      ) {
        add(
          file,
          "instant-export",
          "the page exports neither `instant = true` nor an `// instant: <reason>` comment",
        );
      }

      const stage = /export\s+const\s+ensureStatic\s*=\s*["']([^"']*)["']/.exec(
        code,
      )?.[1];

      if (stage !== undefined && stage !== "shell" && stage !== "prefetch") {
        add(
          file,
          "ensure-static-value",
          `ensureStatic is "${stage}"; use "shell" or "prefetch"`,
        );
      }
    }

    if (isPage) {
      if (/from\s+["'][^"']*-queries["']/.test(code)) {
        add(
          file,
          "page-imports-queries",
          "a page or layout imports a *-queries file",
        );
      }

      if (/export\s+default\s+async\s+function/.test(code)) {
        add(
          file,
          "async-page",
          "the page is async; use params.then() and sync composition",
        );
      }

      if (/await\s+(?:props\.)?(?:params|searchParams)\b/.test(code)) {
        add(file, "await-params", "the page awaits params or searchParams");
      }
    }

    if (feature) {
      if (
        /\b(?:params|searchParams)\??\s*:\s*(?:Promise<|Awaited<|Record<|\{)/.test(
          code,
        )
      ) {
        add(
          file,
          "route-prop",
          "a feature prop is named params or searchParams",
        );
      }

      if (/\bprops\.(?:params|searchParams)\b/.test(code) && !isPage) {
        add(
          file,
          "route-prop",
          "a feature reads props.params or props.searchParams",
        );
      }

      const folder = basename(dirname(file));
      const queriesMatch = /^(.+)-queries\.ts$/.exec(name);
      const actionsMatch = /^(.+)-actions\.ts$/.exec(name);

      if (queriesMatch) {
        if (
          !hasDirective(source, "use server") &&
          !/^import\s+["']server-only["'];?\s*$/m.test(source)
        ) {
          add(
            file,
            "queries-server-only",
            "*-queries.ts must import 'server-only'",
          );
        }

        if (queriesMatch[1] !== folder) {
          add(
            file,
            "file-prefix",
            `the prefix ${queriesMatch[1]} does not match the folder ${folder}`,
          );
        }
      }

      if (actionsMatch) {
        if (!hasDirective(source, "use server")) {
          add(
            file,
            "actions-use-server",
            "*-actions.ts must start with 'use server'",
          );
        }

        if (actionsMatch[1] !== folder) {
          add(
            file,
            "file-prefix",
            `the prefix ${actionsMatch[1]} does not match the folder ${folder}`,
          );
        }
      }

      if (
        name.endsWith("-cache.ts") &&
        /server-only|from\s+["']next\/cache["']|@\/lib\/supabase\/server|["']use (?:cache|server)/.test(
          code,
        )
      ) {
        add(
          file,
          "cache-pure",
          "a *-cache.ts file holds pure tags and keys and imports no server code",
        );
      }

      if (/\/components\/[^/]+\.tsx$/.test(rel)) {
        const exported = new Set(
          [
            ...code.matchAll(
              /export\s+(?:default\s+)?(?:async\s+)?function\s+(\w+)/g,
            ),
          ].map((m) => m[1]),
        );

        for (const component of asyncComponents(code)) {
          const documented = new RegExp(
            `^[ \\t]*//\\s*skeleton:\\s*\\S.*\\n(?:[ \\t]*(?://|/\\*|\\*).*\\n)*export\\s+(?:default\\s+)?async\\s+function\\s+${component}\\b`,
            "m",
          ).test(source);

          if (!exported.has(`${component}Skeleton`) && !documented) {
            add(
              file,
              "skeleton",
              `${component} has no ${component}Skeleton in the same file and no skeleton: comment above it`,
            );
          }
        }
      }

      if (/<Suspense\b/.test(code) && !(rel in allow.suspenseInFeatures)) {
        add(
          file,
          "suspense-in-feature",
          "a feature file renders <Suspense>; the page owns the boundary",
        );
      }
    }

    const lines = source.split("\n");

    for (const [index, line] of lines.entries()) {
      if (
        !/\bconnection\(\)/.test(line) ||
        /^\s*(?:import|\*|\/\/)/.test(line)
      ) {
        continue;
      }

      const reasoned =
        /\/\/|\/\*/.test(line) ||
        /^\s*(?:\/\/|\/\*|\*)/.test(lines[index - 1] ?? "");

      if (!reasoned && !(rel in allow.connection)) {
        add(
          file,
          "connection",
          "connection() needs a comment on its line or the line before that states why rendering waits for a request",
        );
      }
    }

    if (hasDirective(source, "use client")) {
      for (const match of source.matchAll(
        /import\s+(?:[^"']*?\s+from\s+)?["']([^"']+)["']/g,
      )) {
        const target = resolveImport(root, file, match[1] ?? "");
        const targetSource = target ? sources.get(target) : undefined;

        if (
          target &&
          targetSource &&
          !hasDirective(targetSource, "use client") &&
          asyncComponents(stripComments(targetSource)).length > 0
        ) {
          add(
            file,
            "client-imports-async",
            `a client file imports the async server component in ${relative(root, target)}`,
          );
        }
      }
    }
  }

  return findings;
};

const run = (): void => {
  const args = argv.slice(2);
  const print = args.includes("--print");
  const roots = args.filter((arg) => !arg.startsWith("--"));
  // SAFETY: the allow file is this repo's own JSON, shaped by `Allow`.
  const allow = JSON.parse(readFileSync(ALLOW_FILE, "utf-8")) as Allow;
  const listed = new Set(allow.findings);

  const missing = allow.roots.filter((root) => !existsSync(root));

  const checked =
    roots.length > 0
      ? roots
      : [
          ...allow.roots,
          ...allow.pendingRoots.filter((root) => existsSync(root)),
        ];

  const all = checked.flatMap((root) => checkRoot(root, allow));

  const keyOf = (finding: Finding): string => `${finding.rule} ${finding.file}`;

  if (print) {
    const keys = [...new Set(all.map(keyOf))].toSorted();
    console.log(JSON.stringify(keys, null, 2));

    return;
  }

  for (const root of missing) {
    console.error(`${ALLOW_FILE}: the root ${root} does not exist`);
  }

  const fresh = all.filter((finding) => !listed.has(keyOf(finding)));
  const seen = new Set(all.map(keyOf));
  const stale = allow.findings.filter((key) => !seen.has(key));

  for (const finding of fresh) {
    console.error(`${finding.file}: [${finding.rule}] ${finding.message}`);
  }

  for (const key of stale) {
    console.error(`${ALLOW_FILE}: "${key}" no longer matches; remove it`);
  }

  if (fresh.length > 0 || stale.length > 0 || missing.length > 0) {
    exit(1);
  }

  console.log(
    `app architecture: ${all.length} findings, ${listed.size} allowed`,
  );
};

if (process.argv[1]?.endsWith("check-app-architecture.ts")) {
  run();
}
