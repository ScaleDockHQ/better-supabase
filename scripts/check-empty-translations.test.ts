import { describe, expect, it } from "vitest";

import {
  belongsTo,
  checkTranslations,
  parsePo,
  readMessageFiles,
} from "./check-empty-translations.ts";
import { readEntityRoutes } from "./entity-routes.ts";

const page = {
  entity: "risks.risk",
  name: "risks",
  route: "/risks",
  messageKeys: ["risks.title", "risks.columns.status"],
};

const PO = `msgid ""
msgstr ""
"Language: nl\\n"

#: src/features/risks/risk-list.tsx
msgctxt "risks.ep8Oy7"
msgid "Next review"
msgstr "Volgende review"

msgctxt "risks.abc123"
msgid "A long text"
msgstr ""
"split over "
"two lines"

msgctxt "risks.zzz999"
msgid "Search risks"
msgstr ""

msgctxt "risks.title"
msgid "Risks"
msgstr ""

msgctxt "people.q1"
msgid "Unrelated"
msgstr ""
`;

describe("check-empty-translations", () => {
  it("reads entries, joins continuation lines and skips the header", () => {
    const entries = parsePo(PO);

    expect(entries.map((entry) => entry.context)).toEqual([
      "risks.ep8Oy7",
      "risks.abc123",
      "risks.zzz999",
      "risks.title",
      "people.q1",
    ]);

    expect(entries[1]?.text).toBe("split over two lines");
  });

  it("matches a page by its namespace or by a literal key", () => {
    const [, , search, title, other] = parsePo(PO);

    expect(belongsTo(search!, page)).toBe(true);
    expect(belongsTo(title!, page)).toBe(true);
    expect(belongsTo(other!, page)).toBe(false);
  });

  it("reports an empty msgstr of the page and ignores other pages", () => {
    const report = checkTranslations([page], { "nl.po": PO });

    expect(report.checked).toBe(4);

    expect(report.problems).toHaveLength(2);
    expect(report.problems[0]).toContain("risks.zzz999");
    expect(report.problems[1]).toContain("risks.title");
  });

  it("reads the generated manifest of the example", () => {
    const routes = readEntityRoutes();

    expect(routes.map((route) => route.name)).toContain("periods");
    expect(routes.every((route) => route.messageKeys.length > 0)).toBe(true);
  });

  it("passes for the example's message files", () => {
    const report = checkTranslations(readEntityRoutes(), readMessageFiles());

    expect(report.problems).toEqual([]);
    expect(report.checked).toBeGreaterThan(0);
  });
});
