import { provideConnectionRuntime } from "../../src/core/define-runtime-full.ts";

// Unit tests call definition.connect() without importing a client or server entry.
provideConnectionRuntime();
