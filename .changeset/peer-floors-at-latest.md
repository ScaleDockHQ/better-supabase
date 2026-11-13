---
"better-supabase": minor
---

Every peer range now starts at the release the conformance tests run on, and each range covers one major release. The previous majors are no longer supported: SvelteKit 2, Nuxt 3, React Router 7, NestJS 11, Stripe 17 to 22, `expo-server` 55 to 57, undici 7, redis 5 and PowerSync 1. `h3` keeps H3 1 (`>=1.15.11 <3`) because Nuxt 4 runs on it, and `oxfmt` keeps its 0.66.0 floor. Expo SDK 58 needs no `unstable_` options, and the `bsb.loader()` error names `web.output`. `VercelSandboxCreateOptions` types Sandbox 4's `credentials: { npm: true }`, which lets a sandbox install the team's private npm packages. Eight Vercel SDKs join the optional peers: `@vercel/schedules`, `botid`, `@vercel/firewall`, `@vercel/passport`, `@vercel/sdk`, `@vercel/functions`, `@vercel/kms` and `@vercel/blob`. [From 0.66 to 0.67](https://bettersupabase.com/docs/migration/0.66-to-0.67) lists every new floor; the Supabase packages are in their own changeset.

| Package             | Before        | After            |
| ------------------- | ------------- | ---------------- |
| `@sveltejs/kit`     | `>=2 <4`      | `>=3.2.0 <4`     |
| `nuxt`              | `>=3 <5`      | `>=4.6.4 <5`     |
| `react-router`      | `>=7.9 <9`    | `>=8.5.1 <9`     |
| `@nestjs/common`    | `>=11 <13`    | `>=12.5.0 <13`   |
| `stripe`            | `>=17 <24`    | `>=23.1.0 <24`   |
| `expo-server`       | `>=55 <59`    | `>=58.1.0 <59`   |
| `undici`            | `>=7.30.1 <9` | `>=8.12.4 <9`    |
| `redis`             | `>=5 <7`      | `>=6.3.1 <7`     |
| `@powersync/common` | `>=1 <3`      | `>=2.5.0 <3`     |
| `@vercel/queue`     | `>=0.8 <0.9`  | `>=0.11.0 <0.12` |
| `@vercel/sandbox`   | `>=3 <4`      | `>=4.0.0 <5`     |
| `eve`               | `>=0.71 <1`   | `>=0.83.3 <1`    |
| `workflow`          | `>=5.1 <6`    | `>=5.4.0 <6`     |
