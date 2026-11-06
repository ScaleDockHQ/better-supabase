/** `create trigger` calling `fn` once per row or per statement. */
export function createTrigger(options: {
  readonly name: string;
  readonly timing: "before" | "after" | "instead of";
  readonly events: readonly string[];
  readonly table: string;
  readonly fn: string;
  readonly args?: readonly string[];
  readonly forEach?: "row" | "statement";
  readonly when?: string;
}): string {
  const args = (options.args ?? []).join(", ");
  const when = options.when === undefined ? "" : `\n  when (${options.when})`;

  return `create trigger ${options.name} ${options.timing} ${options.events.join(" or ")} on ${options.table}\n  for each ${options.forEach ?? "row"}${when}\n  execute function ${options.fn}(${args});`;
}
