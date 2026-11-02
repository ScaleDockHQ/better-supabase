import { describe, expect, it } from "vitest";

import {
  HOLIDAYS,
  HOLIDAY_YEARS,
} from "../../../src/sql/modules/calendar-holidays.ts";
import { SQL_MODULES } from "../../../src/sql/registry.ts";
import { renderBlocks } from "../../../src/sql/render.ts";
import { seedFunctionName } from "../../../src/sql/seeds.ts";

function seedBody(name: string): string {
  const files = renderBlocks([...SQL_MODULES[name]!.requires, name], {});

  const sql = files
    .filter((file) => file.module === name)
    .map((file) => file.contents)
    .join("\n");

  const start = sql.indexOf(`"${seedFunctionName(name)}"(`);

  return sql.slice(start, sql.indexOf("\n$$;", start));
}

describe("inbox seeds", () => {
  const body = seedBody("inbox");

  it("seeds the Help inbox on the in-app channel", () => {
    expect(body).toContain("'Help'");
    expect(body).toContain("'in_app'");
    expect(body).toContain("'human'");
  });

  it("applies to every locale", () => {
    expect(body).not.toContain("p_locale = any");
  });
});

describe("attachments seeds", () => {
  const body = seedBody("attachments");

  it("seeds the document types with their field schemas", () => {
    for (const key of ["contract", "invoice", "receipt", "identity", "other"]) {
      expect(body).toContain(`'${key}'`);
    }

    expect(body).toContain('"type":"expiry"');
    expect(body).toContain("::jsonb");
  });
});

describe("calendar seeds", () => {
  const body = seedBody("calendar");

  it("guards each holiday set by its locale", () => {
    for (const locale of Object.keys(HOLIDAYS)) {
      expect(body).toContain(`p_locale = any (array['${locale}'])`);
    }
  });

  it("seeds no calendar for the plain en locale", () => {
    expect(body).not.toContain("array['en']");
  });

  it("writes one event per holiday and year with a stable uid", () => {
    const nl = HOLIDAYS["nl"]!.rules.length * HOLIDAY_YEARS.length;

    expect(body.match(/'holiday-nl-\d{4}-\d{2}-\d{2}'/g)).toHaveLength(nl * 2);
    expect(body).toContain("'holiday-nl-2026-04-27'");
    expect(body).toContain("'holiday-en-gb-2027-12-27'");
  });

  it("starts each all-day event at local midnight", () => {
    expect(body).toContain(
      "timestamp '2026-04-27 00:00' at time zone 'Europe/Amsterdam'",
    );
  });
});
