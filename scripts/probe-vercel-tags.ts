// Asks a Vercel preview of apps/examples/nextjs how tag invalidation behaves,
// and prints the table for ADR 1207 and the Vercel cache docs page. Set
// BSB_TAG_PROBE_SECRET on the preview, then run:
//   BSB_TAG_PROBE_SECRET=... node scripts/probe-vercel-tags.ts https://<preview>.vercel.app [--bypass <token>]
import { argv, env, exit } from "node:process";

interface Step {
  readonly method: string;
  readonly stored: boolean;
  readonly goneAtOnce: boolean;
  readonly goneAfter: number | null;
  readonly error: string | null;
}

interface Answer {
  readonly steps: readonly Step[];
  readonly limits: readonly { count: number; error: string | null }[];
  readonly oversizedTag: { rejects: boolean; error: string | null };
}

const args = argv.slice(2);
const base = args.find((arg) => arg.startsWith("http"))?.replace(/\/$/, "");
const bypassIndex = args.indexOf("--bypass");
const bypass = bypassIndex === -1 ? undefined : args[bypassIndex + 1];
const secret = env["BSB_TAG_PROBE_SECRET"];

if (!base || !secret) {
  console.error(
    "Usage: BSB_TAG_PROBE_SECRET=... node scripts/probe-vercel-tags.ts <preview-url> [--bypass <token>]",
  );
  exit(2);
}

const headers = new Headers({ authorization: `Bearer ${secret}` });

if (bypass) {
  headers.set("x-vercel-protection-bypass", bypass);
}

const response = await fetch(`${base}/api/probe/vercel-tags`, {
  method: "POST",
  headers,
});

if (!response.ok) {
  console.error(
    `The probe answered ${String(response.status)}. A 404 means BSB_TAG_PROBE_SECRET is not set on the preview.`,
  );
  exit(1);
}

// SAFETY: the probe route answers this shape.
const answer = (await response.json()) as Answer;

const cell = (step: Step): string => {
  if (step.error !== null) {
    return `rejects: ${step.error}`;
  }

  if (step.goneAfter === null) {
    return "entry still there after 3 s";
  }

  return step.goneAtOnce
    ? "gone at once"
    : `gone after ${String(step.goneAfter)} ms`;
};

console.log("| Method | Stored | Runtime Cache entry after the call |");

console.log("| --- | --- | --- |");

for (const step of answer.steps) {
  console.log(
    `| \`${step.method}\` | ${step.stored ? "yes" : "no"} | ${cell(step)} |`,
  );
}

console.log("");

console.log("| Tags in one `expireTag` call | Result |");

console.log("| --- | --- |");

for (const { count, error } of answer.limits) {
  console.log(
    `| ${String(count)} | ${error === null ? "accepted" : `rejects: ${error}`} |`,
  );
}

console.log("");

console.log(
  `A tag over 256 bytes ${answer.oversizedTag.rejects ? `rejects the promise: ${answer.oversizedTag.error ?? ""}` : "resolves without an error"}.`,
);
