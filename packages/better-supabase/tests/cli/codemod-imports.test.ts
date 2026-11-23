import { describe, expect, it } from "vitest";

import { applyCodemod } from "../../src/cli/codemod.ts";

const codemod = {
  name: "t",
  description: "t",
  imports: { oldName: "newName" },
};

const run = (source: string): string => applyCodemod(codemod, source).text;

describe("codemod import renames", () => {
  it("renames the import and its uses", () => {
    expect(
      run('import { oldName } from "better-supabase";\noldName();\n'),
    ).toBe('import { newName } from "better-supabase";\nnewName();\n');
  });

  it("keeps an object key, a member and a type member", () => {
    const text = run(
      'import { oldName } from "better-supabase";\nconst a = { oldName: 1 };\nb.oldName;\ninterface I { oldName: string }\noldName();\n',
    );

    expect(text).toContain("{ oldName: 1 }");
    expect(text).toContain("b.oldName;");
    expect(text).toContain("interface I { oldName: string }");
    expect(text).toContain("\nnewName();");
  });

  it("leaves a shadowing local alone", () => {
    const text = run(
      'import { oldName } from "better-supabase";\nfunction f(oldName: number) { return oldName; }\noldName();\n',
    );

    expect(text).toContain("function f(oldName: number) { return oldName; }");
    expect(text).toContain("\nnewName();");
  });

  it("keeps the property name of a shorthand", () => {
    expect(
      run(
        'import { oldName } from "better-supabase";\nconst a = { oldName };\n',
      ),
    ).toContain("{ oldName: newName }");
  });

  it("leaves a comment and a string alone", () => {
    const text = run(
      'import { oldName } from "better-supabase";\n// oldName\nconst s = "oldName";\nconst t = `oldName`;\n',
    );

    expect(text).toContain("// oldName");
    expect(text).toContain('"oldName"');
    expect(text).toContain("`oldName`");
  });

  it("keeps an import alias and renames only the imported name", () => {
    expect(
      run('import { oldName as mine } from "better-supabase";\nmine();\n'),
    ).toBe('import { newName as mine } from "better-supabase";\nmine();\n');
  });

  it("leaves another package alone", () => {
    const source = 'import { oldName } from "other";\noldName();\n';

    expect(run(source)).toBe(source);
  });

  it("uses CRLF and tab files as they are", () => {
    expect(
      run('import { oldName } from "better-supabase";\r\n\toldName();\r\n'),
    ).toBe('import { newName } from "better-supabase";\r\n\tnewName();\r\n');
  });
});

describe("codemod subpath renames", () => {
  const subpaths = { old: "new", gone: "" };

  const rename = (source: string): string =>
    applyCodemod({ name: "t", description: "t", subpaths }, source).text;

  it("renames import, export, dynamic import and mock specifiers", () => {
    const text = rename(
      'import a from "better-supabase/old";\nexport * from \'better-supabase/old\';\nawait import("better-supabase/gone");\nvi.mock("better-supabase/old");\n',
    );

    expect(text).toBe(
      'import a from "better-supabase/new";\nexport * from \'better-supabase/new\';\nawait import("better-supabase");\nvi.mock("better-supabase/new");\n',
    );
  });

  it("leaves a comment and a longer string alone", () => {
    const source =
      '// "better-supabase/old"\nconst s = "see better-supabase/old for more";\n';

    expect(rename(source)).toBe(source);
  });
});
