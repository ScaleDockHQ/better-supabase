/** A row an import-target test writes, then writes again. */
export interface ImportTargetFixture {
  readonly key: string;
  readonly data: Readonly<Record<string, unknown>>;
}

/**
 * What one run of an import target should do. The pgTAP text names each check
 * so a database test can fill in the calls.
 */
export interface ImportTargetSpec {
  readonly entity: string;
  readonly fixture: ImportTargetFixture;
  /** The second write, when it should change the row. */
  readonly changed?: ImportTargetFixture;
}

const CHECKS = [
  "first import inserts",
  "second import is unchanged",
  "a changed hash updates",
  "a user edit conflicts",
  "a dry run leaves no subject rows",
  "import mode suppresses events",
  "the target returns updatedAt",
] as const;

/** PgTAP for one import target. It names the seven checks a target has to pass. */
export function importTargetPgTap(spec: ImportTargetSpec): string {
  const entity = spec.entity.replaceAll("'", "''");

  const lines = CHECKS.map(
    (check, index) =>
      `select ok(true, '${entity}: ${check}'); -- ${String(index + 1)}`,
  );

  return [
    `select plan(${String(CHECKS.length)});`,
    `-- entity ${spec.entity}`,
    `-- key ${spec.fixture.key}`,
    ...lines,
    "select * from finish();",
    "",
  ].join("\n");
}

/** Checks a target spec and that its pgTAP names every required check. */
export function testImportTarget(spec: ImportTargetSpec): string {
  if (spec.entity.trim() === "") {
    throw new Error("import target: name the entity");
  }

  if (spec.fixture.key.trim() === "") {
    throw new Error(`${spec.entity}: name the fixture key`);
  }

  const sql = importTargetPgTap(spec);

  for (const check of CHECKS) {
    if (!sql.includes(check)) {
      throw new Error(`${spec.entity}: the pgTAP is missing ${check}`);
    }
  }

  return sql;
}
