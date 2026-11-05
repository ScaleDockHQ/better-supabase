import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const body = (): string =>
  renderBlocks(["pgtap"], {})
    .filter((file) => file.module === "pgtap")
    .map((file) => file.contents)
    .join("\n");

describe("pgtap module", () => {
  it("looks users up in security definer helpers so an authenticated test can switch users", () => {
    const sql = body();

    expect(sql).toMatch(
      /function tests\._user_id_by_email\(user_email text\)\s+returns uuid\s+language sql\s+stable\s+security definer/u,
    );
    expect(sql).toMatch(
      /function tests\._email_of\(user_id uuid\)\s+returns text\s+language sql\s+stable\s+security definer/u,
    );
    expect(sql).toContain("found_id := tests._user_id_by_email(user_email);");
    expect(sql).not.toMatch(
      /from auth\.users u where u\.email = user_email;\n\s*if/u,
    );
  });

  it("keeps authenticate_as itself security invoker, since set role is refused in a definer", () => {
    expect(body()).toMatch(
      /function tests\.authenticate_as\(user_email text\)\s+returns void\s+language plpgsql\s+set search_path/u,
    );
  });
});
