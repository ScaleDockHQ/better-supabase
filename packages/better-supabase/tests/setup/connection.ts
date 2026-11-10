import { provideConnectionRuntime } from "../../src/core/define-runtime.ts";

// Unit tests call definition.connect() without importing a client or server entry.
provideConnectionRuntime();
