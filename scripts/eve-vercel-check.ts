// Probes a deployed eve service on Vercel and prints the numbers the gap report in
// docs/agents/eve.md leaves unproven. Run it against a deployment of
// apps/examples/eve:
//   node scripts/eve-vercel-check.ts https://<deployment>.vercel.app [--bypass <token>]
// The build check is separate: build the example twice with `vercel build`, once with
// and once without `build.externalDependencies: ["better-supabase"]`, and note whether
// the World bundles `pg`.
import { argv, exit } from "node:process";

const args = argv.slice(2);
const base = args.find((arg) => arg.startsWith("http"))?.replace(/\/$/, "");
const bypassIndex = args.indexOf("--bypass");
const bypass = bypassIndex === -1 ? undefined : args[bypassIndex + 1];

if (!base) {
  console.error(
    "Usage: node scripts/eve-vercel-check.ts <deployment-url> [--bypass <token>]",
  );
  exit(2);
}

const headers: Record<string, string> = bypass
  ? { "x-vercel-protection-bypass": bypass }
  : {};

const timed = async <T>(
  run: () => Promise<T>,
): Promise<{ ms: number; value: T }> => {
  const start = performance.now();
  const value = await run();

  return { ms: Math.round(performance.now() - start), value };
};

/**
 * The flow route has a Vercel Queues trigger, so a plain request must not run a
 * flow.
 */
const probeFlowRoute = async (): Promise<string> => {
  const { ms, value } = await timed(() =>
    fetch(`${base}/.well-known/workflow/v1/flow`, { headers, method: "POST" }),
  );

  return `flow route answers ${value.status} in ${ms} ms`;
};

const probeSessionStart = async (): Promise<string[]> => {
  const lines: string[] = [];
  const start = performance.now();

  const response = await fetch(`${base}/eve/v1/sessions`, {
    body: JSON.stringify({ message: "Reply with the word ready." }),
    headers: { ...headers, "content-type": "application/json" },
    method: "POST",
  });

  lines.push(`session start answers ${response.status}`);

  if (!response.body) {
    return lines;
  }

  const reader = response.body.getReader();
  const first = await reader.read();
  lines.push(
    `time to first byte ${Math.round(performance.now() - start)} ms (${first.done ? 0 : String(first.value).length} chars)`,
  );
  await reader.cancel();

  return lines;
};

const main = async (): Promise<void> => {
  console.log(`Checking ${base}`);
  console.log(await probeFlowRoute());

  for (const line of await probeSessionStart()) {
    console.log(line);
  }

  console.log(
    "Reconnect time: reload the example chat during a long answer and note the gap.",
  );
};

try {
  await main();
} catch (error) {
  console.error(String(error));
  exit(1);
}
