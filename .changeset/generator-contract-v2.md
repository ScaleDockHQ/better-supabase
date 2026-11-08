---
"better-supabase": minor
---

Generators are plugins at `apiVersion: 2`. A generator declares `name`, `version`, `options`, `pure`, `workerSafe` and `provides`, and `generate` receives plain data: `config` is a view (`output`, `databaseTypesOutput`, `casing`, `json`) and `imports.runtime` replaces `runtimeImport`. `provides: ["validators"]` replaces the `validators` flag on a file, and two generators that provide it are an error (the zod, valibot and standard-schema generators take `validators: false`). `gen` caches a `pure` generator's files on its name, version, options and input. The new `better-supabase/generators` entry exports `defineGenerator`, `relativeImport` and the helpers the built-in generators use. `testGenerator` is now `testGeneratorPlugin`, and it also checks `structuredClone` safety and the cache round trip. A generator at `apiVersion: 1` fails with a message that names the change.
