import { describe, expect, it } from "vitest";

import type { DoctorContext, TextFile } from "../../../src/cli/doctor/rules.ts";

import { ENFORCEMENT_RULES } from "../../../src/cli/doctor/enforcement.ts";

function check(
  sources: readonly TextFile[],
): readonly {
  message: string;
  target?: string;
  location?: { line: number };
}[] {
  const [rule] = ENFORCEMENT_RULES;
  // SAFETY: BS429 reads only `sources`.
  const findings = rule?.check({ sources } as unknown as DoctorContext);

  if (!Array.isArray(findings)) {
    throw new TypeError("BS429 runs synchronously");
  }

  return findings;
}

const file = (path: string, lines: readonly string[]): TextFile => ({
  path,
  text: lines.join("\n"),
});

describe("BS429", () => {
  it("names an action with a permission and no enforcement", () => {
    const findings = check([
      file("src/app/projects/actions.ts", [
        'import { bsb } from "@/lib/supabase/server";',
        "",
        "export const archiveProject = bsb.action(",
        '  { input: schema, permission: "projects.archive" },',
        "  async (input, { db }) => db.projects.archive(input.id),",
        ");",
        "export const renameProject = bsb.action(",
        '  { input: schema, permission: "projects.update", enforcement: "rls" },',
        "  async (input, { db }) => db.projects.update(input),",
        ");",
        "export const listProjects = bsb.action({ input: schema }, fn);",
      ]),
    ]);

    expect(findings).toEqual([
      expect.objectContaining({
        target: "src/app/projects/actions.ts:archiveProject",
        location: { file: "src/app/projects/actions.ts", line: 3 },
        message: expect.stringContaining(
          "The action archiveProject in src/app/projects/actions.ts writes and sets no enforcement",
        ),
      }),
    ]);
    expect(findings[0]?.message).toContain(
      'Set enforcement: "rls" only when every write in it runs through the caller\'s db',
    );
  });

  it("names write routes only", () => {
    const findings = check([
      file("src/app/api/projects/route.ts", [
        'export const GET = bsb.route(handler, { permission: "projects.read" });',
        'export const POST = bsb.route(handler, { permission: "projects.create" });',
        'export const DELETE = bsb.route(handler, { permission: "projects.delete", enforcement: "definer" });',
      ]),
    ]);

    expect(findings.map((finding) => finding.target)).toEqual([
      "src/app/api/projects/route.ts:POST",
    ]);
  });

  it("names resource actions that write", () => {
    const findings = check([
      file("src/server/projects.ts", [
        "export const projects = defineResource({",
        "  actions: {",
        '    archive: { method: "POST", path: "/:id/archive", permission: "projects.archive" },',
        '    preview: { method: "GET", path: "/:id/preview", permission: "projects.read" },',
        '    recount: { method: "POST", path: "/recount", permission: "projects.read", intent: "read" },',
        '    touch: { method: "PATCH", path: "/:id/touch", permission: "projects.update", enforcement: "rls" },',
        "  },",
        "});",
      ]),
    ]);

    expect(findings.map((finding) => finding.target)).toEqual([
      "src/server/projects.ts:archive",
    ]);
  });

  it("names MCP tools that are not read-only", () => {
    const findings = check([
      file("src/mcp/tools.ts", [
        "export const voidInvoice = defineTool({",
        '  name: "void_invoice",',
        '  permission: "invoices.void",',
        "  run: async () => {},",
        "});",
        "export const listInvoices = defineTool({",
        '  name: "list_invoices",',
        '  permission: "invoices.read",',
        "  annotations: { readOnlyHint: true },",
        "  run: async () => {},",
        "});",
      ]),
    ]);

    expect(findings).toEqual([
      expect.objectContaining({
        target: "src/mcp/tools.ts:void_invoice",
        message: expect.stringContaining("The MCP tool void_invoice"),
      }),
    ]);
  });
});
