import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { select } from "./select-tests.ts";

const PKG = "packages/better-supabase";
let root = "";

function write(path: string, text: string): void {
  mkdirSync(dirname(join(root, path)), { recursive: true });
  writeFileSync(join(root, path), text);
}

beforeAll(() => {
  root = mkdtempSync(join(tmpdir(), "select-tests-"));
  write(`${PKG}/src/a.ts`, "export const a = 1;\n");
  write(
    `${PKG}/src/b.ts`,
    'import { a } from "./a.ts";\nexport const b = a;\n',
  );
  write(`${PKG}/src/c.ts`, "export const c = 1;\n");
  write(`${PKG}/src/lazy.ts`, 'export const load = () => import("./c.ts");\n');
  write(
    `${PKG}/tests/b.test.ts`,
    'import { b } from "../src/b.ts";\nvoid b;\n',
  );
  write(
    `${PKG}/tests/lazy.test.ts`,
    'import { load } from "../src/lazy.ts";\nvoid load;\n',
  );
  write(
    `${PKG}/tests/docs.test.ts`,
    'readFileSync("apps/docs/content/docs/index.mdx");\n',
  );
  write(
    `${PKG}/tests/entries.test.ts`,
    'import { globSync } from "node:fs";\nglobSync("src/**/*.ts");\n',
  );
});

afterAll(() => {
  rmSync(root, { recursive: true, force: true });
});

describe("select", () => {
  it("follows static and dynamic imports to the tests that reach a file", () => {
    const direct = select([`${PKG}/src/a.ts`], root);

    expect(direct.mode).toBe("files");
    expect(direct.tests).toContain("tests/b.test.ts");
    expect(direct.tests).not.toContain("tests/docs.test.ts");

    expect(select([`${PKG}/src/c.ts`], root).tests).toContain(
      "tests/lazy.test.ts",
    );
  });

  it("always adds the tests that list src", () => {
    expect(select([`${PKG}/src/c.ts`], root).tests).toContain(
      "tests/entries.test.ts",
    );
  });

  it("selects only the changed test for a changed test file", () => {
    expect(select([`${PKG}/tests/docs.test.ts`], root).tests).toEqual([
      "tests/docs.test.ts",
    ]);
  });

  it("maps a docs page to the tests that read the docs", () => {
    expect(select(["apps/docs/content/docs/index.mdx"], root).tests).toEqual([
      "tests/docs.test.ts",
    ]);
  });

  it("selects nothing for paths no test reads", () => {
    expect(
      select(["apps/marketing/app/page.tsx", "README.md"], root),
    ).toMatchObject({ mode: "files", tests: [] });
  });

  it("widens to the full suite for the lockfile, config and unexplained library paths", () => {
    expect(select(["pnpm-lock.yaml"], root).mode).toBe("full");
    expect(select([`${PKG}/vitest.config.ts`], root).mode).toBe("full");
    expect(select([`${PKG}/src/data/new.json`], root).mode).toBe("full");
    expect(select([`${PKG}/src/gone.ts`], root).mode).toBe("full");
  });
});
