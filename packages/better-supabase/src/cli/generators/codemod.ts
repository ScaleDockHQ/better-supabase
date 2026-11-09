import type { Codemod, ReviewLine } from "../codemod.ts";

/** Where each generator export moved to, by `better-supabase/config` name. */
const MOVED: Readonly<Record<string, string>> = {
  zod: "zod",
  ZodFlavor: "zod",
  ZodGeneratorOptions: "zod",
  valibot: "valibot",
  ValibotGeneratorOptions: "valibot",
  jsonSchema: "json-schema",
  toJsonSchema: "json-schema",
  JsonSchemaGeneratorOptions: "json-schema",
  JsonSchemaTarget: "json-schema",
  standardSchema: "standard-schema",
  StandardSchemaGeneratorOptions: "standard-schema",
  factories: "factories",
  FactoriesGeneratorOptions: "factories",
  nuqs: "nuqs",
  NuqsGeneratorOptions: "nuqs",
};

/** `import [type] { ... } from "better-supabase/config"`, over any lines. */
const IMPORT =
  /import\s+(type\s+)?\{([^}]*)\}\s*from\s*(["'])better-supabase\/config\3;?/g;

interface Specifier {
  readonly text: string;
  readonly name: string;
}

function specifiers(body: string): Specifier[] {
  return body
    .split(",")
    .map((part) => part.trim())
    .filter((part) => part !== "")
    .map((text) => ({
      text,
      name: text
        .replace(/^type\s+/, "")
        .split(/\s+as\s+/)[0]!
        .trim(),
    }));
}

/**
 * Moves the generator imports from `better-supabase/config` to the subpath of
 * each generator. A name that stays in the config import keeps its place.
 */
export function moveGeneratorImports(text: string): string {
  return text.replaceAll(
    IMPORT,
    (whole, typeOnly: string | undefined, body: string, quote: string) => {
      const kept: string[] = [];
      const moved = new Map<string, string[]>();

      for (const specifier of specifiers(body)) {
        const subpath = Object.hasOwn(MOVED, specifier.name)
          ? MOVED[specifier.name]
          : undefined;

        if (subpath === undefined) {
          kept.push(specifier.text);
        } else {
          moved.set(subpath, [...(moved.get(subpath) ?? []), specifier.text]);
        }
      }

      if (moved.size === 0) {
        return whole;
      }

      const prefix = typeOnly === undefined ? "import" : "import type";

      const lines = [
        ...(kept.length === 0
          ? []
          : [
              `${prefix} { ${kept.join(", ")} } from ${quote}better-supabase/config${quote};`,
            ]),
        ...[...moved].map(
          ([subpath, names]) =>
            `${prefix} { ${names.join(", ")} } from ${quote}better-supabase/generators/${subpath}${quote};`,
        ),
      ];

      return lines.join("\n");
    },
  );
}

/** Lines that still use the v1 generator shape, for the author to port. */
const V1 = [
  [
    /\bruntimeImport\b/,
    "`runtimeImport` is `input.imports.runtime` at apiVersion 2",
  ],
  [
    /\binput\.importPath\b/,
    "`importPath` is `relativeImport` from `better-supabase/generators`",
  ],
  [
    /\bapiVersion:\s*1\b/,
    "set `apiVersion: 2` and a `version`, or build it with `defineGenerator`",
  ],
  [
    /\bvalidators:\s*true\b/,
    'declare `provides: ["validators"]` on the generator',
  ],
] as const;

/**
 * Whether the object literal around `index` is a generator: it has a `generate`
 * key. Other contracts (`defineAuthorizationHooks`, a block provider) also
 * write `apiVersion: 1`, and they are not generators.
 */
function insideGenerator(text: string, index: number): boolean {
  let depth = 0;
  let start = -1;

  for (let at = index; at >= 0; at -= 1) {
    const char = text.charAt(at);

    if (char === "}") {
      depth += 1;
    } else if (char === "{") {
      if (depth === 0) {
        start = at;
        break;
      }

      depth -= 1;
    }
  }

  if (start === -1) {
    return false;
  }

  depth = 0;

  for (let at = start; at < text.length; at += 1) {
    const char = text.charAt(at);

    if (char === "{") {
      depth += 1;
    } else if (char === "}") {
      depth -= 1;

      if (depth === 0) {
        return /\bgenerate\s*[:(]/.test(text.slice(start, at));
      }
    }
  }

  return false;
}

const VERSION_ONE = /\bapiVersion:\s*1\b/;

function reviewLines(text: string): ReviewLine[] {
  let offset = 0;

  return text.split("\n").flatMap((line, index): ReviewLine[] => {
    const lineStart = offset;
    offset += line.length + 1;

    return V1.flatMap(([pattern, message]): ReviewLine[] => {
      if (!pattern.test(line)) {
        return [];
      }

      if (
        pattern.source === VERSION_ONE.source &&
        !insideGenerator(text, lineStart + line.search(VERSION_ONE))
      ) {
        return [];
      }

      return [{ line: index + 1, message }];
    });
  });
}

/** Moves generator imports to their subpaths and flags v1 generators. */
export function generatorsCodemod(): Codemod {
  return {
    name: "generators",
    description:
      "Import the generators from better-supabase/generators/<name>, and flag generators written for apiVersion 1",
    source: (text) => {
      const moved = moveGeneratorImports(text);

      return { text: moved, review: reviewLines(moved) };
    },
  };
}
