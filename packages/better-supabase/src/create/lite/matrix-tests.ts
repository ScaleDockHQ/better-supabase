import type { PresetMigrationFile } from "../types.ts";
import type { MatrixCell, MatrixCommand, MatrixRole } from "./verify.ts";

import { MATRIX_COMMANDS } from "./verify.ts";

/** A caller the generated access tests act as (ADR 0105). */
export type MatrixPersona =
  | "anon"
  | "signed-in"
  | "member-a"
  | "member-b"
  | "support"
  | "service";

export const MATRIX_PERSONAS: readonly MatrixPersona[] = [
  "anon",
  "signed-in",
  "member-a",
  "member-b",
  "support",
  "service",
];

/** How one persona is set up before its assertions run. */
export interface PersonaSetup {
  /** The `sub` claim; every persona has a fixed default. */
  readonly sub?: string;
  /** Claims merged into the JWT claims the persona sends. */
  readonly claims?: Readonly<Record<string, unknown>>;
  /** SQL run as the owner before the role switch, for example a membership row. */
  readonly setup?: string;
}

export interface MatrixTestOptions {
  /** The personas to write a file for; all of them by default. */
  readonly personas?: readonly MatrixPersona[];
  /** Per-persona claims and setup SQL, because memberships are the app's own. */
  readonly setup?: Readonly<Partial<Record<MatrixPersona, PersonaSetup>>>;
  /** The folder of the files; `supabase/tests/database` by default. */
  readonly directory?: string;
}

const DEFAULT_SUBS: Readonly<Record<MatrixPersona, string>> = {
  anon: "00000000-0000-4000-8000-0000000000e0",
  "signed-in": "00000000-0000-4000-8000-0000000000e1",
  "member-a": "00000000-0000-4000-8000-0000000000e2",
  "member-b": "00000000-0000-4000-8000-0000000000e3",
  support: "00000000-0000-4000-8000-0000000000e4",
  service: "00000000-0000-4000-8000-0000000000e5",
};

/** The database role a persona runs as. */
function roleOf(persona: MatrixPersona): MatrixRole | "service_role" {
  switch (persona) {
    case "anon": {
      return "anon";
    }

    case "service": {
      return "service_role";
    }

    case "signed-in":
    case "member-a":
    case "member-b":
    case "support": {
      return "authenticated";
    }

    default: {
      const never: never = persona;

      return never;
    }
  }
}

function quoteLiteral(value: string): string {
  return `'${value.replaceAll("'", "''")}'`;
}

function quoteTable(table: string): string {
  return table
    .split(".")
    .map((part) => `"${part.replaceAll('"', '""')}"`)
    .join(".");
}

/** The statement a persona runs to try `command` on `table`. */
function statementOf(command: MatrixCommand, table: string): string {
  const target = quoteTable(table);

  switch (command) {
    case "select": {
      return `select count(*) from ${target}`;
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
      const never: never = command;

      return never;
    }
  }
}

/**
 * The helper each file defines: runs a statement in a savepoint and returns
 * `denied` for a missing privilege or a row level security violation (SQLSTATE
 * 42501), `rows:<n>` when it ran, and `error:<sqlstate>` otherwise, so a
 * constraint error on an allowed insert is not mistaken for a denial.
 */
const ATTEMPT = `create function extensions.bsb_attempt(statement text) returns text
language plpgsql as $attempt$
declare n bigint;
begin
  execute statement;
  get diagnostics n = row_count;
  return 'rows:' || n;
exception
  when insufficient_privilege then return 'denied';
  when others then return 'error:' || sqlstate;
end $attempt$;
grant execute on function extensions.bsb_attempt(text) to anon, authenticated, service_role;`;

function claimsOf(persona: MatrixPersona, setup: PersonaSetup): string {
  const sub = setup.sub ?? DEFAULT_SUBS[persona];

  return JSON.stringify({
    sub,
    role: roleOf(persona),
    ...(persona === "anon" ? {} : { aud: "authenticated" }),
    ...setup.claims,
  });
}

interface Assertion {
  readonly sql: string;
}

function assertionsOf(
  persona: MatrixPersona,
  cells: readonly MatrixCell[],
): readonly Assertion[] {
  const role = roleOf(persona);

  if (role === "service_role") {
    return [...new Set(cells.map((cell) => cell.table))].map((table) => ({
      sql: `select extensions.isnt(extensions.bsb_attempt(${quoteLiteral(statementOf("select", table))}), 'denied', ${quoteLiteral(`service_role reads ${table}`)});`,
    }));
  }

  return cells
    .filter((cell) => cell.role === role)
    .flatMap((cell): Assertion[] => {
      const statement = quoteLiteral(statementOf(cell.command, cell.table));
      const label = `${persona} ${cell.command} ${cell.table}`;

      switch (cell.reach) {
        case "denied": {
          return [
            {
              sql: `select extensions.ok(extensions.bsb_attempt(${statement}) in ('denied', 'rows:0'), ${quoteLiteral(`${label} reaches no row`)});`,
            },
          ];
        }

        case "open": {
          return [
            {
              sql: `select extensions.isnt(extensions.bsb_attempt(${statement}), 'denied', ${quoteLiteral(`${label} is not denied`)});`,
            },
          ];
        }

        case "policy": {
          return cell.command === "insert"
            ? []
            : [
                {
                  sql: `select extensions.isnt(extensions.bsb_attempt(${statement}), 'denied', ${quoteLiteral(`${label} is decided by a policy`)});`,
                },
              ];
        }

        default: {
          const never: never = cell.reach;

          return never;
        }
      }
    });
}

function fileOf(
  persona: MatrixPersona,
  cells: readonly MatrixCell[],
  options: MatrixTestOptions,
): PresetMigrationFile {
  const setup = options.setup?.[persona] ?? {};
  const assertions = assertionsOf(persona, cells);
  const role = roleOf(persona);
  const directory = options.directory ?? "supabase/tests/database";
  const name = persona.replaceAll("-", "_");

  const lines = [
    `-- Generated access matrix for the ${persona} persona (ADR 0105).`,
    `-- Each assertion holds the table's reach for ${role} against the catalog the matrix read.`,
    "begin;",
    "create extension if not exists pgtap with schema extensions;",
    `select extensions.plan(${Math.max(assertions.length, 1)});`,
    "",
    ATTEMPT,
    "",
    ...(setup.setup === undefined ? [] : [setup.setup, ""]),
    `select set_config('request.jwt.claims', ${quoteLiteral(claimsOf(persona, setup))}, true);`,
    `set local role ${role};`,
    "",
    ...(assertions.length === 0
      ? ["select extensions.pass('nothing to check');"]
      : assertions.map((each) => each.sql)),
    "",
    "select * from extensions.finish();",
    "rollback;",
    "",
  ];

  return {
    path: `${directory}/access_matrix_${name}.test.sql`,
    module: "access-matrix",
    contents: lines.join("\n"),
  };
}

/**
 * One pgTAP file per persona from the access matrix (ADR 0105): anon, a signed
 * in user without a membership, a member of tenant A and of tenant B, a
 * read-only support session and the service role. A cell that reaches no row
 * must not return one, an open cell must not be denied, and the service role is
 * never stopped by row level security. Memberships belong to the app, so a
 * persona's rows and claims come from `options.setup`.
 */
export function accessMatrixTests(
  matrix: readonly MatrixCell[],
  options: MatrixTestOptions = {},
): readonly PresetMigrationFile[] {
  const personas = options.personas ?? MATRIX_PERSONAS;

  const known = new Set<MatrixCommand>(MATRIX_COMMANDS);
  const cells = matrix.filter((cell) => known.has(cell.command));

  return personas.map((persona) => fileOf(persona, cells, options));
}
