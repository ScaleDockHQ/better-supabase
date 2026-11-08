import { describe, expect, it } from "vitest";

import { splitStatements } from "../../../src/sql/pipeline/split.ts";
import { SQL_MODULES } from "../../../src/sql/registry.ts";
import { renderBlocks } from "../../../src/sql/render.ts";

const files = renderBlocks(Object.keys(SQL_MODULES), {}).filter(
  (file) => file.kind === "schema",
);

const TARGET = /^(grant|revoke)\s+(.+?)\s+on\s+(.+?)\s+(?:to|from)\s/is;

describe("grants in the block files", () => {
  it("never name every object of a kind with on all", () => {
    const found = files.flatMap((file) =>
      splitStatements(file.contents)
        .filter((statement) =>
          /^(?:grant|revoke)\b[^;]*\bon\s+all\s/i.test(statement.text),
        )
        .map((statement) => `${file.path}:${String(statement.line)}`),
    );

    expect(found).toEqual([]);
  });

  it("revokes everything on an object before it grants anything on it", () => {
    const found = files.flatMap((file) => {
      const granted = new Set<string>();
      const late: string[] = [];

      for (const statement of splitStatements(file.contents)) {
        const match = TARGET.exec(statement.text.replaceAll(/\s+/g, " "));

        if (match === null) {
          continue;
        }

        const kind = match[1]!.toLowerCase();
        const privileges = match[2]!.toLowerCase();
        const target = match[3]!.toLowerCase();

        if (kind === "grant") {
          granted.add(target);
        } else if (privileges === "all" && granted.has(target)) {
          late.push(`${file.path}:${String(statement.line)} ${target}`);
        }
      }

      return late;
    });

    expect(found).toEqual([]);
  });
});
