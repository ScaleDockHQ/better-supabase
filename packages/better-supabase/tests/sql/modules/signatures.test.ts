import { describe, expect, it } from "vitest";

import { customContracts, renderModules } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderModules>[1];

const sqlOf = (modules: readonly string[], layout: Layout = {}): string =>
  renderModules(modules, layout)
    .filter((file) => file.module === "signatures")
    .map((file) => file.contents)
    .join("\n");

const BASE = ["versions", "signatures"];

describe("signatures module", () => {
  it("keeps requests and signatures bound to a frozen version", () => {
    const sql = sqlOf(BASE);
    for (const table of ["signature_requests", "signatures"]) {
      expect(sql).toContain(
        `create table if not exists "better_supabase"."${table}"`,
      );
    }
    expect(sql).toContain(
      `references "better_supabase"."versions" ("id") on delete restrict`,
    );
    expect(sql).toContain(`set "frozen" = true`);
    expect(sql).toContain("extensions.digest(");
    expect(sql).toContain("SIGNATURE_CONTENT_CHANGED");
    expect(sql).toContain(
      `revoke execute on function "better_supabase"."signature_verification"(uuid) from public, anon, authenticated;`,
    );
  });

  it("decides an approval step only with the approvals module", () => {
    expect(sqlOf(BASE)).not.toContain("decide_approval");
    expect(sqlOf(BASE)).toContain("SIGNATURE_APPROVAL_UNSUPPORTED");
    const linked = sqlOf(["approvals", ...BASE]);
    expect(linked).toContain(`"better_supabase"."approval_eligible"(`);
    expect(linked).toContain(`"better_supabase"."decide_approval"(`);
    expect(linked).toContain("SIGNATURE_APPROVAL_NOT_FOUND");
  });

  it("checks drawn images against attachments when that module is installed", () => {
    expect(sqlOf(BASE)).toContain(
      "a drawn signature needs the attachments module for its image",
    );
    const images = sqlOf(["attachments", ...BASE]);
    expect(images).toContain(`from "better_supabase"."attachments" a`);
    expect(images).toContain("SIGNATURE_IMAGE_NOT_FOUND");
  });

  it("needs a versions table", () => {
    expect(() =>
      sqlOf(BASE, { modules: { versions: { mode: "custom" } } }),
    ).toThrow(/versions can't be in custom mode/);
  });

  it("references adopted versions without a foreign key", () => {
    const sql = sqlOf(BASE, {
      modules: {
        versions: { mode: "adopt", tables: { versions: "app.revisions" } },
      },
    });
    expect(sql).toContain(`from "app"."revisions" x`);
    expect(sql).not.toContain("on delete restrict");
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { signatures: { mode: "custom" } } };
    expect(sqlOf(BASE, custom).trim()).toBe("");
    const [contract] = customContracts(["signatures"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual([
      "create_signature_request",
      "sign_signature",
      "get_signature_request",
    ]);
  });

  it("works on adopted tables without creating them", () => {
    const sql = sqlOf(BASE, {
      modules: {
        signatures: {
          mode: "adopt",
          tables: {
            requests: "app.sign_requests",
            signatures: "app.sign_marks",
          },
        },
      },
    });
    expect(sql).not.toMatch(/create table if not exists "app"/);
    expect(sql).toContain(`"app"."sign_requests"`);
    expect(sql).toContain(`"app"."sign_marks"`);
  });
});
