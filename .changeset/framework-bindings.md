---
"better-supabase": minor
---

Frameworks are registrations. `defineFramework` from the new `better-supabase/plugins` entry builds a binding (`name`, `tier`, `detect`, `integrations`, `hooksSubpath` or `hooksModule`, `hooksDirective`), and `frameworks: [binding]` in `gen` registers it. `gen.hooks` takes any registered name, the built-in `react`, `svelte`, `vue` and `solid` bindings use the same contract, and `init` writes `gen.hooks` for a detected framework that no adapter selects. `ResolvedConfig` gains `frameworks`, and `gen.hooks` naming a framework nothing registers is an error.
