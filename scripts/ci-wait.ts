// Waits for the checks of the current branch's pull request and prints one line per failed job.
import { spawnSync } from "node:child_process";
import { exit } from "node:process";

const watch = spawnSync("gh", ["pr", "checks", "--watch", "--interval", "20"], {
  stdio: ["ignore", "ignore", "inherit"],
});

if (watch.error !== undefined) {
  console.error("gh is not available or not logged in.");
  exit(2);
}

const list = spawnSync("gh", ["pr", "checks", "--json", "name,state,link"], {
  encoding: "utf-8",
});

// SAFETY: `gh pr checks --json name,state,link` prints exactly these fields.
const checks = JSON.parse(list.stdout || "[]") as {
  name: string;
  state: string;
  link: string;
}[];

const failed = checks.filter(
  (check) => check.state === "FAILURE" || check.state === "ERROR",
);

for (const check of failed) {
  console.log(`FAIL ${check.name} ${check.link}`);
}

console.log(
  failed.length === 0
    ? `All ${checks.length} checks passed.`
    : `${failed.length} failed.`,
);

exit(failed.length === 0 ? 0 : 1);
