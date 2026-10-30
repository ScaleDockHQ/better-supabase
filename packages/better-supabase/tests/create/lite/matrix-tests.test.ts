import { describe, expect, it } from "vitest";

import type {
  MatrixCell,
  SandboxSession,
} from "../../../src/create/lite/index.ts";
import type { CreateDesign } from "../../../src/preset/index.ts";

import { previewFiles } from "../../../src/create/index.ts";
import {
  accessMatrix,
  accessMatrixTests,
  MATRIX_PERSONAS,
  openSandbox,
  readSecurityCatalog,
  verifyQuery,
} from "../../../src/create/lite/index.ts";
import { namedPreset, presetSpec } from "../../../src/preset/index.ts";

const cell = (overrides: Partial<MatrixCell> = {}): MatrixCell => ({
  table: "public.notes",
  role: "authenticated",
  command: "select",
  reach: "policy",
  ...overrides,
});

describe("accessMatrixTests", () => {
  it("writes one pgTAP file per persona", () => {
    const files = accessMatrixTests([cell()]);

    expect(files.map((file) => file.path)).toEqual(
      MATRIX_PERSONAS.map(
        (persona) =>
          `supabase/tests/database/access_matrix_${persona.replaceAll("-", "_")}.test.sql`,
      ),
    );
  });

  it("asserts denied, open and policy cells for the persona's role", () => {
    const [anon, signedIn] = accessMatrixTests(
      [
        cell({ role: "anon", command: "select", reach: "denied" }),
        cell({ role: "authenticated", command: "select", reach: "open" }),
        cell({ role: "authenticated", command: "update", reach: "policy" }),
        cell({ role: "authenticated", command: "insert", reach: "policy" }),
      ],
      { personas: ["anon", "signed-in"] },
    );

    expect(anon?.contents).toContain("set local role anon;");
    expect(anon?.contents).toContain("plan(1)");
    expect(anon?.contents).toContain("anon select public.notes reaches no row");
    expect(anon?.contents).toContain('select 1 from "public"."notes"');
    expect(anon?.contents).not.toContain("count(*)");
    expect(signedIn?.contents).toContain("set local role authenticated;");
    expect(signedIn?.contents).toContain("plan(2)");
    expect(signedIn?.contents).toContain(
      "signed-in select public.notes is not denied",
    );
    expect(signedIn?.contents).toContain(
      'select 1 from "public"."notes" where false for update',
    );
    expect(signedIn?.contents).not.toContain("insert into");
  });

  it("applies a persona's claims and setup SQL", () => {
    const [file] = accessMatrixTests([cell()], {
      personas: ["member-a"],
      setup: {
        "member-a": {
          sub: "u-1",
          claims: { app_metadata: { tenant_id: "t-1" } },
          setup: "insert into memberships values ('u-1', 't-1');",
        },
      },
    });

    expect(file?.contents).toContain(
      "insert into memberships values ('u-1', 't-1');",
    );
    expect(file?.contents).toContain('"sub":"u-1"');
    expect(file?.contents).toContain('"app_metadata":{"tenant_id":"t-1"}');
  });

  it("checks the service role reads every table", () => {
    const [file] = accessMatrixTests(
      [cell({ table: "public.a" }), cell({ table: "public.b" })],
      { personas: ["service"] },
    );

    expect(file?.contents).toContain("set local role service_role;");
    expect(file?.contents).toContain("plan(2)");
  });
});

/** A small seeded generator, so a failing project replays. */
function random(seed: number): () => number {
  let state = seed;

  return () => {
    state = (state * 1_664_525 + 1_013_904_223) % 4_294_967_296;

    return state / 4_294_967_296;
  };
}

const NAMES = ["notes", "tasks", "invoices", "docs", "tickets", "pages"];
const SCOPES = ["inherit", "user", "none"] as const;
const TYPES = ["text", "integer", "boolean"] as const;

function randomDesign(next: () => number): CreateDesign {
  const pick = <T>(items: readonly T[]): T =>
    items[Math.floor(next() * items.length)] as T;

  const count = 1 + Math.floor(next() * 4);
  const names = NAMES.toSorted(() => next() - 0.5).slice(0, count);

  return {
    appTables: Object.fromEntries(
      names.map((name) => [
        name,
        {
          scope: pick(SCOPES),
          columns: Object.fromEntries(
            ["title", "amount", "done"]
              .slice(0, 1 + Math.floor(next() * 3))
              .map((column) => [column, { type: pick(TYPES) }]),
          ),
        },
      ]),
    ),
  };
}

const STRANGER = "00000000-0000-4000-8000-0000000000a2";

function statementOf(cell: MatrixCell): string {
  const target = cell.table;

  switch (cell.command) {
    case "select": {
      return `select 1 from ${target} limit 1`;
    }

    case "insert": {
      return `insert into ${target} default values`;
    }

    case "update": {
      return `select 1 from ${target} where false for update`;
    }

    case "delete": {
      return `delete from ${target} where false`;
    }

    default: {
      const never: never = cell.command;

      return never;
    }
  }
}

async function attempt(
  session: SandboxSession,
  cell: MatrixCell,
): Promise<"denied" | "ran"> {
  const result = await session.query(statementOf(cell));

  return !result.ok && result.error.code === "42501" ? "denied" : "ran";
}

describe("access matrix over random projects", () => {
  const seeds = [1, 2, 3, 4, 5, 6];

  it.each(seeds)(
    "agrees with the engine for project %i",
    async (seed) => {
      const design = randomDesign(random(seed));
      const files = previewFiles(presetSpec(namedPreset("saas")), design);
      const sandbox = await openSandbox({ files });

      try {
        const query = await sandbox.query(verifyQuery(["public"]));

        if (!query.ok) {
          throw new Error(query.error.message);
        }

        const matrix = accessMatrix(readSecurityCatalog(query.rows));
        expect(matrix.length).toBeGreaterThan(0);

        const sessions = {
          anon: sandbox.as({}),
          authenticated: sandbox.as({ sub: STRANGER }),
        };

        const violations: string[] = [];

        for (const each of matrix) {
          const label = `${each.role} ${each.command} ${each.table}`;
          const session = sessions[each.role];
          const outcome = await attempt(session, each);

          if (each.reach === "open" && outcome === "denied") {
            violations.push(`${label} is open but denied`);
          }

          if (each.reach === "denied" && each.command !== "insert") {
            const result = await session.query(statementOf(each));

            if (result.ok && result.rows.length > 0) {
              violations.push(`${label} is denied but returned rows`);
            }
          }

          if (
            each.role === "anon" &&
            each.command !== "select" &&
            each.reach === "open"
          ) {
            violations.push(`${label} is open to anon`);
          }
        }

        expect(violations).toEqual([]);

        const generated = accessMatrixTests(matrix);

        for (const file of generated) {
          const planned = /plan\((\d+)\)/u.exec(file.contents)?.[1];

          const asserted = file.contents
            .split("\n")
            .filter((line) => line.startsWith("select extensions.")).length;

          expect(Number(planned)).toBe(Math.max(asserted - 1, 1));
        }
      } finally {
        await sandbox.close();
      }
    },
    120_000,
  );
});
