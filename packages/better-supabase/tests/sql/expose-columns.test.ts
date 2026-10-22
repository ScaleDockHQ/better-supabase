import { describe, expect, it } from "vitest";

import { resolveConfig } from "../../src/config/index.ts";
import {
  excludedColumns,
  moduleLayout,
  renderBlocks,
  resolveExposeColumns,
} from "../../src/sql/index.ts";

const files = [
  {
    text: "create table app.keys (id int, label text, token text, check (id > 0));",
  },
];

describe("resolveExposeColumns", () => {
  it("reads the excluded columns of the star form only", () => {
    expect(excludedColumns("select(*, -token, - label)")).toEqual([
      "token",
      "label",
    ]);
    expect(excludedColumns("select(id, token)")).toEqual([]);
    expect(excludedColumns("select")).toEqual([]);
  });

  it("keeps the declared columns in order and leaves other grants alone", () => {
    const plain = {
      table: "app.keys",
      role: "anon" as const,
      privileges: ["select"],
    };

    expect(
      resolveExposeColumns(
        [
          plain,
          {
            table: "app.keys",
            role: "authenticated",
            privileges: ["select(*, -token)", "update(label)"],
          },
        ],
        files,
        ["app"],
      ),
    ).toEqual([
      plain,
      {
        table: "app.keys",
        role: "authenticated",
        privileges: ["select(id, label)", "update(label)"],
      },
    ]);
  });

  it("refuses exclusions that leave no column", () => {
    expect(() =>
      resolveExposeColumns(
        [
          {
            table: "app.keys",
            role: "authenticated",
            privileges: ["select(*, -id, -label, -token)"],
          },
        ],
        files,
        ["app"],
      ),
    ).toThrow("excludes every column of app.keys");
  });

  it("refuses to render an exclusion sql sync did not resolve", () => {
    const config = resolveConfig(
      { expose: { notes: ["select(*, -body)"] }, blocks: ["grants"] },
      "/project",
    );

    expect(() => renderBlocks(["grants"], moduleLayout(config))).toThrow(
      "resolves against the declared columns",
    );
  });
});
