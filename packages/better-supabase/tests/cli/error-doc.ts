/**
 * The error document a failed `--json` run printed: the last line of stderr,
 * since stdout stays empty and earlier lines are diagnostics.
 */
export function errorDoc(result: { readonly stderr: string }): unknown {
  const line = result.stderr.trim().split("\n").at(-1) ?? "";

  return JSON.parse(line);
}

/**
 * The one document a `--json` run printed: the result on stdout, else the error
 * on stderr.
 */
export function resultDoc(result: {
  readonly stdout: string;
  readonly stderr: string;
}): { readonly status: string } {
  // SAFETY: both streams hold JSON documents with a `status` under --json.
  return (
    result.stdout.trim() === "" ? errorDoc(result) : JSON.parse(result.stdout)
  ) as { readonly status: string };
}
