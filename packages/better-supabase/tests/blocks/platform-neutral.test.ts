import { existsSync } from "node:fs";
import { readdir, readFile } from "node:fs/promises";
import { dirname, relative, resolve } from "node:path";
import { describe, expect, it } from "vitest";

// Block controllers and their React bindings run in React DOM and React
// Native alike: platform needs go through the ports in `client/ports.ts`.
// This walks each one's relative imports, as the WinterTC check does, and
// rejects DOM globals and React Native imports anywhere in the closure.
const SRC = resolve(import.meta.dirname, "../../src");

/** Value imports only: `import type` and `export type` vanish at build time. */
const SPECIFIER =
  /^\s*(?:import|export)(?!\s+type\b)\b[^;]*?\bfrom\s+["']([^"']+)["']|^\s*import\s+["']([^"']+)["']|\bimport\(\s*["']([^"']+)["']\s*\)/gm;

/** Comments and string literals, which may name `window` without using it. */
const NOISE =
  /\/\*[\s\S]*?\*\/|\/\/[^\n]*|"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`(?:\\.|[^`\\])*`/g;

/** `window` or `document` as a value, not as a property or an object key. */
const DOM_GLOBAL = /(?<![\w$.])(?:window|document)(?![\w$]|\s*\??:)/;

async function closure(entry: string) {
  const files = new Set<string>();
  const externals = new Map<string, string>();

  const visit = async (file: string): Promise<void> => {
    if (files.has(file)) {
      return;
    }

    files.add(file);
    const source = await readFile(file, "utf-8");

    for (const match of source.matchAll(SPECIFIER)) {
      const specifier = (match[1] ?? match[2] ?? match[3])!;

      if (specifier.startsWith(".")) {
        const target = resolve(dirname(file), specifier);

        if (existsSync(target)) {
          await visit(target);
        }
      } else if (!externals.has(specifier)) {
        externals.set(specifier, relative(SRC, file));
      }
    }
  };

  await visit(resolve(SRC, entry));

  return { files, externals };
}

async function domOffenders(files: ReadonlySet<string>): Promise<string[]> {
  const offenders: string[] = [];

  for (const file of files) {
    const code = (await readFile(file, "utf-8")).replaceAll(NOISE, "");

    for (const [index, line] of code.split("\n").entries()) {
      if (DOM_GLOBAL.test(line)) {
        offenders.push(`${relative(SRC, file)}:${index + 1}: ${line.trim()}`);
      }
    }
  }

  return offenders;
}

const isNative = (name: string): boolean =>
  name === "react-native" || name.startsWith("react-native/");

const blocks = await readdir(resolve(SRC, "blocks"), { withFileTypes: true });

const controllers = blocks
  .filter((entry) => entry.isDirectory())
  .map((entry) => `blocks/${entry.name}/client.ts`)
  .filter((file) => existsSync(resolve(SRC, file)));

const bindings = blocks
  .filter((entry) => entry.isDirectory())
  .map((entry) => `blocks/${entry.name}/react/index.ts`)
  .filter((file) => existsSync(resolve(SRC, file)));

describe("platform-neutral block clients", () => {
  it("gives every React binding a controller", () => {
    expect(bindings.length).toBeGreaterThan(0);

    for (const binding of bindings) {
      expect(controllers).toContain(
        binding.replace("/react/index.ts", "/client.ts"),
      );
    }
  });

  it.each(controllers)(
    "%s imports no React, DOM or React Native",
    async (file) => {
      const { files, externals } = await closure(file);

      const imports = [...externals]
        .filter(
          ([name]) =>
            name === "react" || name === "react-dom" || isNative(name),
        )
        .map(([name, from]) => `${from} imports ${name}`);

      expect([...imports, ...(await domOffenders(files))]).toEqual([]);
    },
  );

  it.each(bindings)("%s uses no DOM global or React Native", async (file) => {
    const { files, externals } = await closure(file);

    const imports = [...externals]
      .filter(([name]) => name === "react-dom" || isNative(name))
      .map(([name, from]) => `${from} imports ${name}`);

    expect([...imports, ...(await domOffenders(files))]).toEqual([]);
  });

  it("catches the globals it is meant to catch", async () => {
    const lines = [
      "window.addEventListener('keydown', onKey);",
      "const el = document.createElement('input');",
      "if (typeof window === 'undefined') return;",
    ];

    for (const line of lines) {
      expect(DOM_GLOBAL.test(line.replaceAll(NOISE, ""))).toBe(true);
    }

    const fine = [
      "// a window focus refetches",
      '"document.created"',
      "event.document",
      "{ document: value }",
      "readonly window?: Span;",
      "const windowSize = 3;",
    ];

    for (const line of fine) {
      expect(DOM_GLOBAL.test(line.replaceAll(NOISE, ""))).toBe(false);
    }
  });
});
