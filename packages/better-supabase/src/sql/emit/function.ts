/** `create or replace function` with a dollar-quoted body. */
export function createFunction(options: {
  readonly name: string;
  readonly args: string;
  readonly returns: string;
  readonly language: "sql" | "plpgsql";
  readonly volatility?: "immutable" | "stable" | "volatile";
  readonly security?: "definer" | "invoker";
  readonly body: string;
}): string {
  const lines = [
    `create or replace function ${options.name}(${options.args})`,
    `returns ${options.returns}`,
    `language ${options.language}`,
    ...(options.volatility === undefined ? [] : [options.volatility]),
    ...(options.security === undefined ? [] : [`security ${options.security}`]),
    "set search_path = ''",
    `as $$\n${options.body}\n$$;`,
  ];

  return lines.join("\n");
}
