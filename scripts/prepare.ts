import { execFileSync } from "node:child_process";
import process from "node:process";

// Vercel and CI builds have no git hooks to install.
if (process.env["CI"] === undefined && process.env["VERCEL"] === undefined) {
  execFileSync("lefthook", ["install"], { stdio: "inherit" });
}
