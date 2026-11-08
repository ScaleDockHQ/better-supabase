import { argv, stdin } from "node:process";
// Prints the client JavaScript a route loads first, grouped by package, from
// the JSON Lines `next analyze export` writes (Next.js 16.4). Pipe it in:
//   pnpm --filter @better-supabase/example-nextjs exec next analyze --output --snapshot a
//   pnpm --filter @better-supabase/example-nextjs exec next analyze export --snapshot a \
//     | node scripts/next-analyze-report.ts "/[locale]/customers" [top]
// A chunk counts as first load unless it only belongs to a dynamic import
// (group kind `async`). Sizes are the analyzer's minified and compressed bytes.
import { createInterface } from "node:readline";

interface Line {
  readonly type: string;
  readonly route?: string;
  readonly kind?: string;
  readonly outputs?: readonly string[];
  readonly filename?: string;
  readonly source_path?: string;
  readonly size?: number;
  readonly compressed_size?: number;
}

const route = argv[2];
const top = Number(argv[3] ?? "25");

if (!route) {
  throw new Error('usage: node scripts/next-analyze-report.ts "<route>" [top]');
}

const PNPM = /node_modules\/\.pnpm\/[^/]+\/node_modules\/((?:@[^/]+\/)?[^/]+)/;
const LIBRARY = /packages\/better-supabase\/(?:src|dist)\/([^/]+)/;
const APP = /apps\/examples\/nextjs\/src\/([^/]+(?:\/[^/]+)?)/;

function packageOf(path: string): string {
  return (
    PNPM.exec(path)?.[1] ??
    (LIBRARY.exec(path)?.[1]
      ? `better-supabase/${LIBRARY.exec(path)?.[1]}`
      : undefined) ??
    (APP.exec(path)?.[1] ? `app:${APP.exec(path)?.[1]}` : undefined) ??
    path.slice(0, 60)
  );
}

const isClientScript = (file: string): boolean =>
  file.includes("/static/chunks/") && file.endsWith(".js");

const outputs = new Set<string>();
const asyncOnly = new Set<string>();
const joined = new Set<string>();
const parts: Line[] = [];

for await (const text of createInterface({ input: stdin })) {
  // The export is large; only the route's lines are parsed.
  if (!text.includes(`"route":${JSON.stringify(route)}`)) {
    continue;
  }

  // SAFETY: each line of the export is one JSON object.
  const line = JSON.parse(text) as Line;

  if (line.type === "group") {
    for (const file of line.outputs ?? []) {
      (line.kind === "async" ? asyncOnly : joined).add(file);
    }
  } else if (line.type === "output" && isClientScript(line.filename ?? "")) {
    outputs.add(line.filename ?? "");
  } else if (line.type === "part" && isClientScript(line.filename ?? "")) {
    parts.push(line);
  }
}

const first = new Set(
  [...outputs].filter((file) => !asyncOnly.has(file) || joined.has(file)),
);

const raw = new Map<string, number>();
const compressed = new Map<string, number>();

for (const part of parts) {
  if (first.has(part.filename ?? "")) {
    const name = packageOf(part.source_path ?? "");

    raw.set(name, (raw.get(name) ?? 0) + (part.size ?? 0));
    compressed.set(
      name,
      (compressed.get(name) ?? 0) + (part.compressed_size ?? 0),
    );
  }
}

const total = [...raw.values()].reduce((sum, size) => sum + size, 0);

console.log(`${route}: ${total} bytes first load, ${first.size} chunks`);

for (const [name, size] of [...raw]
  .toSorted((a, b) => b[1] - a[1])
  .slice(0, top)) {
  console.log(
    `${String(size).padStart(9)} ${String(compressed.get(name)).padStart(9)}  ${name}`,
  );
}
