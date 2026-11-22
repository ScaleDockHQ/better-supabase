/**
 * The shortest dollar-quote delimiter the body does not contain: `$$`, then
 * `$body$`, then `$body1$` and so on.
 */
function dollarTag(body: string): string {
  for (let index = 0; ; index += 1) {
    const tag = index === 0 ? "$$" : `$body${index === 1 ? "" : index - 1}$`;

    if (!body.includes(tag)) {
      return tag;
    }
  }
}

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
  const tag = dollarTag(options.body);

  const lines = [
    `create or replace function ${options.name}(${options.args})`,
    `returns ${options.returns}`,
    `language ${options.language}`,
    ...(options.volatility === undefined ? [] : [options.volatility]),
    ...(options.security === undefined ? [] : [`security ${options.security}`]),
    "set search_path = ''",
    `as ${tag}\n${options.body}\n${tag};`,
  ];

  return lines.join("\n");
}
