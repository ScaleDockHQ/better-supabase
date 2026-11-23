import { MagicString } from "magic-string";
import { describe, expect, it } from "vitest";

import { parseSource } from "../../src/cli/config-document/parse.ts";
import { addNamedImports } from "../../src/cli/import-edits.ts";

const MODULE = "better-supabase/server/account";

function add(text: string, names: readonly string[]): string {
  const out = new MagicString(text);

  addNamedImports(out, parseSource(text).program, MODULE, names);

  return out.toString();
}

describe("addNamedImports", () => {
  it("adds a statement after the last import", () => {
    expect(add('import a from "a";\nconst x = 1;\n', ["endSessions"])).toBe(
      `import a from "a";\nimport { endSessions } from "${MODULE}";\nconst x = 1;\n`,
    );
  });

  it("adds a statement at the top of a file without imports", () => {
    expect(add("const x = 1;\n", ["a", "b"])).toBe(
      `import { a, b } from "${MODULE}";\nconst x = 1;\n`,
    );
  });

  it("joins an existing import and skips a name it already has", () => {
    expect(add(`import { a } from "${MODULE}";\n`, ["a", "b"])).toBe(
      `import { a, b } from "${MODULE}";\n`,
    );
    expect(add(`import { a as c } from "${MODULE}";\n`, ["a"])).toBe(
      `import { a as c } from "${MODULE}";\n`,
    );
  });

  it("gives a default import a named clause", () => {
    expect(add(`import d from "${MODULE}";\n`, ["a"])).toBe(
      `import d, { a } from "${MODULE}";\n`,
    );
  });

  it("leaves a type import and a namespace import alone", () => {
    expect(add(`import type { T } from "${MODULE}";\n`, ["a"])).toBe(
      `import type { T } from "${MODULE}";\nimport { a } from "${MODULE}";\n`,
    );
    expect(add(`import * as ns from "${MODULE}";\n`, ["a"])).toBe(
      `import * as ns from "${MODULE}";\nimport { a } from "${MODULE}";\n`,
    );
  });

  it("fills an empty import", () => {
    expect(add(`import {} from "${MODULE}";\n`, ["a"])).toBe(
      `import { a } from "${MODULE}";\n`,
    );
  });
});
