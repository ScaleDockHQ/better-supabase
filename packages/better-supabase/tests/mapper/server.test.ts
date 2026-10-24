import { describe, expect, it } from "vitest";

import type { LoadedProject } from "../../src/mapper/project.ts";

import { mapperHandlers } from "../../src/mapper/server.ts";

const PROJECT: LoadedProject = {
  text: "export type A = 1;\n",
  file: "/app/src/schema.bsb",
  configIdentity: "identity",
  watchedFiles: ["/app/better-supabase.config.ts"],
  diagnostics: [],
  optionDiagnostics: [],
};

const handlersFor = (project: LoadedProject = PROJECT) => {
  const opened: unknown[] = [];

  const handlers = mapperHandlers({
    env: { CI: "1" },
    load: (configFileName, options, env) => {
      opened.push({ configFileName, options, env });

      return Promise.resolve(project);
    },
  });

  return { handlers, opened };
};

const open = { configFileName: "/app/tsconfig.json", projectHandle: "h" };

describe("mapperHandlers", () => {
  it("answers initialize with the offered protocol version and utf-16", () => {
    const { handlers } = handlersFor();

    expect(
      handlers["initialize"]!({
        positionEncodings: ["utf-8", "utf-16"],
        protocolVersion: 2,
      }),
    ).toEqual({
      protocolVersion: 2,
      positionEncoding: "utf-16",
      diagnosticSource: "BS",
    });
    expect(handlers["initialize"]!({ positionEncodings: ["utf-8"] })).toEqual({
      protocolVersion: 1,
      positionEncoding: "utf-8",
      diagnosticSource: "BS",
    });
  });

  it("opens a project once and serves its module with one atom span", async () => {
    const { handlers, opened } = handlersFor();

    expect(
      await handlers["openProject"]!({ ...open, options: { config: "x" } }),
    ).toEqual({
      configIdentity: "identity",
      watchedFiles: ["/app/better-supabase.config.ts"],
      optionDiagnostics: [],
    });
    expect(opened).toEqual([
      {
        configFileName: "/app/tsconfig.json",
        options: { config: "x" },
        env: { CI: "1" },
      },
    ]);

    expect(
      await handlers["transform"]!({
        fileName: "/app/src/schema.bsb",
        content: "// é\n",
        projectHandle: "h",
      }),
    ).toEqual({
      extension: ".ts",
      text: PROJECT.text,
      mappings: [[0, PROJECT.text.length, 0, 5, 1, 56]],
      diagnostics: [],
    });
  });

  it("counts the spans in bytes when tsc asks for utf-8", async () => {
    const { handlers } = handlersFor();
    handlers["initialize"]!({ positionEncodings: ["utf-8"] });
    await handlers["openProject"]!(open);

    expect(
      await handlers["transform"]!({
        fileName: "/app/src/schema.bsb",
        content: "// é\n",
        projectHandle: "h",
      }),
    ).toMatchObject({ mappings: [[0, PROJECT.text.length, 0, 6, 1, 56]] });
  });

  it("places the project's diagnostics on the file's first character", async () => {
    const { handlers } = handlersFor({
      ...PROJECT,
      diagnostics: [{ messageText: "stale", code: 604 }],
    });

    await handlers["openProject"]!(open);

    expect(
      await handlers["transform"]!({
        fileName: "/app/src/schema.bsb",
        content: "",
        projectHandle: "h",
      }),
    ).toMatchObject({
      diagnostics: [{ messageText: "stale", code: 604, start: 0, length: 0 }],
    });
  });

  it("answers a file of another project or none with an empty module", async () => {
    const { handlers } = handlersFor();

    expect(
      await handlers["transform"]!({
        fileName: "/app/src/schema.bsb",
        content: "x",
        projectHandle: "none",
      }),
    ).toMatchObject({ text: "export {};\n", diagnostics: [{ code: 603 }] });

    await handlers["openProject"]!(open);

    expect(
      await handlers["transform"]!({
        fileName: "/app/other.bsb",
        content: "x",
        projectHandle: "h",
      }),
    ).toMatchObject({
      text: "export {};\n",
      diagnostics: [{ code: 605, start: 0, length: 1 }],
    });

    expect(handlers["closeProject"]!({ projectHandle: "h" })).toBeNull();
    expect(
      await handlers["transform"]!({
        fileName: "/app/src/schema.bsb",
        content: "x",
        projectHandle: "h",
      }),
    ).toMatchObject({ diagnostics: [{ code: 603 }] });
  });
});
