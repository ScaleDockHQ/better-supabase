import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import { describe, expect, it } from "vitest";

const GOLDEN = join(import.meta.dirname, "__golden__");

function sqlFiles(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);

    if (entry.isDirectory()) {
      return sqlFiles(path);
    }

    return entry.name.endsWith(".sql") ? [path] : [];
  });
}

function stripGroups(text: string, opener: RegExp): string {
  let out = "";
  let index = 0;

  while (index < text.length) {
    const match = opener.exec(text.slice(index));

    if (match?.index !== 0) {
      out += text[index];
      index += 1;
      continue;
    }

    let depth = 0;
    let end = index;

    for (; end < text.length; end += 1) {
      if (text[end] === "(") {
        depth += 1;
      } else if (text[end] === ")") {
        depth -= 1;

        if (depth === 0) {
          break;
        }
      }
    }

    out += " _ ";
    index = end + 1;
  }

  return out;
}

const SUBQUERY = /^(exists\s*\(|\(\s*select\b|coalesce\s*\()/i;

function nullableCallerChecks(sql: string): string[] {
  const found: string[] = [];

  for (const match of sql.matchAll(/\b(?:if|elsif)\b([^;]*?)\bthen\b/gis)) {
    const condition = (match[1] ?? "").replaceAll(/\s+/g, " ");

    const bare = stripGroups(condition, SUBQUERY).replaceAll(
      /is (not )?distinct from auth\.uid\(\)|auth\.uid\(\) is (not )?null/gi,
      "_",
    );

    if (/\bnot\b|<>|!=/i.test(bare) && bare.includes("auth.uid()")) {
      found.push(condition.trim());
    }
  }

  return found;
}

describe("caller checks in guards", () => {
  it("never let a null comparison with auth.uid() skip a negated guard", () => {
    const offenders = sqlFiles(GOLDEN).flatMap((file) =>
      nullableCallerChecks(readFileSync(file, "utf-8")).map(
        (condition) => `${relative(GOLDEN, file)}: ${condition.slice(0, 160)}`,
      ),
    );

    expect([...new Set(offenders)]).toEqual([]);
  });

  it("flags a bare comparison and accepts a coalesced one", () => {
    expect(
      nullableCallerChecks(
        "if not (a or v.user_id = auth.uid()) then raise; end if;",
      ),
    ).toHaveLength(1);
    expect(
      nullableCallerChecks(
        "if not (a or coalesce(v.user_id = auth.uid(), false)) then raise; end if;",
      ),
    ).toEqual([]);
  });
});
