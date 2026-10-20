import type { Preset } from "better-supabase/preset";

import {
  type SchemaData,
  addTable,
  type AppTable,
  appTableId,
  type Design,
  freeTableName,
  columnError,
  referenceFrom,
  renameColumn,
  setColumn,
} from "better-supabase/create";

import type { LayoutRect } from "./schema-layout";

const AUTH_USERS = "auth.users";
const MEMBER = "member_id";

export type JunctionResult =
  | { readonly ok: true; readonly design: Design; readonly name: string }
  | { readonly ok: false; readonly error: string };

/** Where a junction table goes: centred under the two tables it links. */
export function junctionPosition(
  a: LayoutRect,
  b: LayoutRect,
): readonly [number, number] {
  return [
    Math.round((a.x + b.x) / 2),
    Math.round(Math.max(a.y + a.height, b.y + b.height) + 48),
  ];
}

/** Makes a junction column required and deleted with the row it points at. */
function required(design: Design, junction: string, column: string): Design {
  const current = design.appTables?.[junction]?.columns?.[column];

  if (current?.references === undefined) {
    return design;
  }

  return setColumn(design, junction, column, {
    ...current,
    nullable: false,
    references: { ...current.references, onDelete: "cascade" },
  });
}

/**
 * Links the app table `source` to `targetId` many to many: a junction app
 * table `<source>_<target>` with a required, cascading reference to each
 * side and a composite unique on the pair. The junction keeps the source's
 * scope, so in tenant scope both links stay inside one tenant.
 */
export function manyToMany(
  design: Design,
  data: SchemaData,
  preset: Pick<Preset, "scope" | "tenantName" | "idType">,
  source: string,
  targetId: string,
  taken: ReadonlySet<string>,
  position?: readonly [number, number],
): JunctionResult {
  const table = design.appTables?.[source];

  if (table === undefined) {
    return { ok: false, error: `${source} is not in the design.` };
  }

  if (targetId === appTableId(source)) {
    return {
      ok: false,
      error: "A table can't link to itself many to many. Add a Tree instead.",
    };
  }

  const target =
    targetId === AUTH_USERS
      ? "users"
      : data.tables.find((each) => each.id === targetId)?.name;

  if (target === undefined) {
    return { ok: false, error: "That table is not in the schema." };
  }

  const name = freeTableName(design, taken, `${source}_${target}`);

  const junction: AppTable =
    table.scope === undefined ? {} : { scope: table.scope };

  const added = addTable(design, name, junction, position);
  const first = referenceFrom(added, data, preset, name, appTableId(source));

  if (!first.ok) {
    return first;
  }

  const second = referenceFrom(first.design, data, preset, name, targetId);

  if (!second.ok) {
    return second;
  }

  // Every scope reserves `user_id`, so a link to users names its member.
  const member =
    targetId === AUTH_USERS &&
    columnError(second.design.appTables?.[name] ?? {}, MEMBER, preset) ===
      undefined
      ? MEMBER
      : second.column;

  const linked = required(
    required(
      renameColumn(second.design, name, second.column, member),
      name,
      first.column,
    ),
    name,
    member,
  );

  const current = linked.appTables?.[name] ?? {};

  return {
    ok: true,
    name,
    design: addTable(
      linked,
      name,
      { ...current, unique: [[first.column, member]] },
      position,
    ),
  };
}
