/** `alter table <table> add constraint <name> <definition>`. */
function addConstraint(options: {
  readonly table: string;
  readonly name: string;
  readonly definition: string;
  readonly notValid?: boolean;
}): string {
  return `alter table ${options.table} add constraint ${options.name}\n  ${options.definition}${options.notValid === true ? " not valid" : ""};`;
}

/** A check constraint added once, over `expression`. */
export const addCheckConstraint = (options: {
  readonly table: string;
  readonly name: string;
  readonly expression: string;
  readonly notValid?: boolean;
}): string =>
  addConstraint({
    table: options.table,
    name: options.name,
    definition: `check (${options.expression})`,
    ...(options.notValid === undefined ? {} : { notValid: options.notValid }),
  });

/** A foreign key from `column` to `references`. */
export const addForeignKeyConstraint = (options: {
  readonly table: string;
  readonly name: string;
  readonly column: string;
  readonly references: string;
  readonly onDelete: "cascade" | "restrict" | "set null";
}): string =>
  addConstraint({
    table: options.table,
    name: options.name,
    definition: `foreign key (${options.column}) references ${options.references} on delete ${options.onDelete}`,
  });
