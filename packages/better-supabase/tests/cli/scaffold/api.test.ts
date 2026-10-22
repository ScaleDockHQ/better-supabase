import { describe, expect, it } from "vitest";

import {
  GENERATED_HEADER,
  scaffoldApiFiles,
  scaffoldNextSteps,
} from "../../../src/cli/scaffold/api.ts";

const context = {
  framework: "hono",
  srcDir: ".",
  tsExtensions: true,
  name: "api",
  basePath: "/v1",
  tables: ["customers", "order-items"],
} as const;

describe("scaffoldApiFiles", () => {
  it("keeps .ts extensions, quotes table names and roots files at the project", () => {
    const files = scaffoldApiFiles(context);
    expect(files.map((file) => [file.path, file.generated])).toEqual([
      ["lib/api.generated.ts", true],
      ["lib/api.ts", false],
      ["api-routes.ts", false],
    ]);
    const [generated, api, routes] = files;
    expect(generated?.contents.startsWith(GENERATED_HEADER)).toBe(true);
    expect(generated?.contents).toContain('  "order-items": true,');
    expect(generated?.contents).toContain('export const basePath = "/v1";');
    expect(api?.contents).toContain("from './api.generated.ts'");
    expect(routes?.contents).toContain("from './server.ts'");
  });

  it("names the next steps once the entry already points at the module", () => {
    expect(scaffoldNextSteps(context, "lib/api.ts")).toEqual([
      "Mount the routes in server.ts: `.route('/', apiRoutes(bsb))`.",
      "Describe the resources in lib/api.ts; `scaffold api` only rewrites api.generated.ts.",
    ]);
    expect(
      scaffoldNextSteps(
        { ...context, framework: "next" },
        "src/lib/openapi.ts",
      ),
    ).toHaveLength(2);
  });
});
