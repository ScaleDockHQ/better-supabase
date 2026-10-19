#!/usr/bin/env node
// Checked in so pnpm can link the bin on a fresh install, before dist/ is built.
import { enableCompileCache } from "node:module";

import manifest from "../package.json" with { type: "json" };

enableCompileCache();

const argv = process.argv.slice(2);

if (argv.length === 1 && argv[0] === "--version") {
  // A bare --version needs no CLI module; the CLI prints the same line.
  process.stdout.write(`${manifest.version}\n`);
} else {
  await import("../dist/cli/bin.js");
}
