import { describe, expect, it } from "vitest";

import { BLOCK_MANIFESTS } from "../../../src/blocks/registry.ts";
import { SQL_MODULES } from "../../../src/sql/registry.ts";
import { renderBlocks } from "../../../src/sql/render.ts";

const sql = (names: readonly string[]): string =>
  renderBlocks(names)
    .map((file) => file.contents)
    .join("\n");

const erase = (all: string): string => {
  const unquoted = all.replaceAll('"', "");

  const start = unquoted.indexOf(
    "function better_supabase.erase_data_subject(",
  );

  return unquoted.slice(start, unquoted.indexOf("\n$$;", start));
};

describe("erase_data_subject", () => {
  const all = sql(["data-lifecycle", "consents", "field-history"]);
  const body = erase(all);

  it("is generated from the lifecycle.erase of the installed tables", () => {
    expect(body).toContain("update better_supabase.field_changes x set");
    expect(body).toContain("update better_supabase.consents x set");
    expect(body).toContain("from better_supabase.data_subject_requests x");
    expect(body.match(/delete from [^ ]+/g)).toStrictEqual([
      "delete from better_supabase.consent_signals",
    ]);
  });

  it("blanks only the declared personal columns", () => {
    expect(body).toContain(
      "field_changes x set old_value = null, new_value = null, changed_by = null",
    );
  });

  it("checks the legal hold of the retention kind before it touches a table", () => {
    expect(body).toContain("better_supabase.is_held('audit'");
    expect(body).toContain("better_supabase.is_held('personal_data'");
  });

  it("limits every table to the request's tenant and person", () => {
    expect(body).toContain("x.tenant_id::text = v_row.tenant_id::text");
    expect(body).toContain("x.subject_id = v_row.subject_id");
  });

  it("is only granted to signed-in callers and the service role", () => {
    const unquoted = all.replaceAll('"', "");

    expect(unquoted).toContain(
      "revoke execute on function better_supabase.erase_data_subject(uuid) from public, anon;",
    );
    expect(unquoted).toContain(
      "grant execute on function better_supabase.erase_data_subject(uuid) to authenticated, service_role;",
    );
  });

  it("leaves out a module that is not installed", () => {
    const only = erase(sql(["data-lifecycle"]));

    expect(only).not.toContain("field_changes");
    expect(only).not.toContain("better_supabase.consents x");
  });
});

describe("the erase declarations of the manifests and the SQL tables", () => {
  it("agree on the erase mode of every entity that declares personal data", () => {
    const wrong: string[] = [];

    for (const block of BLOCK_MANIFESTS) {
      const tables = SQL_MODULES[block.name]?.names?.tables ?? {};

      const modes = new Set(
        Object.values(tables).flatMap((table) =>
          table.lifecycle?.erase === undefined
            ? []
            : [table.lifecycle.erase.mode],
        ),
      );

      for (const [key, surface] of Object.entries(block.entities ?? {})) {
        if (surface.personalData === undefined) {
          continue;
        }

        if (!modes.has(surface.erase ?? "delete")) {
          wrong.push(`${block.name}.${key}`);
        }
      }
    }

    expect(wrong).toStrictEqual([]);
  });

  it("never declares delete on a table of an append-only entity", () => {
    const wrong: string[] = [];

    for (const block of BLOCK_MANIFESTS) {
      const append = Object.values(block.entities ?? {}).some(
        (surface) => surface.mutability === "append-only",
      );

      const tables = SQL_MODULES[block.name]?.names?.tables ?? {};

      for (const [logical, table] of Object.entries(tables)) {
        if (append && table.lifecycle?.erase?.mode === "delete") {
          wrong.push(`${block.name}.${logical}`);
        }
      }
    }

    expect(wrong).toStrictEqual([]);
  });
});
