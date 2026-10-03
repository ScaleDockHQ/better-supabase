#!/usr/bin/env node
// Checked in so pnpm can link the bin on a fresh install, before dist/ is built.
// oxlint-disable-next-line import/no-unassigned-import -- the CLI module runs on import.
import "../dist/cli/bin.js";
