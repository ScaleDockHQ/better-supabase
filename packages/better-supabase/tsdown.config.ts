import { defineConfig } from 'tsdown';

const entries = [
  'index',
  'config/index',
  'client/index',
  'react/index',
  'react/server',
  'query/index',
  'server/index',
  'postgres/index',
  'ssr/index',
  'next/index',
  'hono/index',
  'orpc/index',
  'edge/index',
  'mcp/index',
  'jobs/index',
  'env/index',
  'list/index',
  'storage/index',
  'realtime/index',
  'events/index',
  'webhooks/index',
  'openapi/index',
  'otel/index',
  'plugins/timestamps/index',
  'lint/index',
  'plugins/rules/index',
  'plugins/soft-delete/index',
  'plugins/tenant/index',
  'plugins/actor/index',
  'plugins/validation/index',
  'testing/index',
  'cli/index',
  'cli/bin',
];

export default defineConfig({
  entry: Object.fromEntries(entries.map((name) => [name, `src/${name}.ts`])),
  platform: 'neutral',
  format: 'esm',
  dts: true,
  clean: true,
  exports: false,
  inputOptions: {
    onLog(level, log, handler) {
      // Rolldown keeps "use client" on the react entry chunk; tests/bundle asserts it.
      if (
        log.code === 'MODULE_LEVEL_DIRECTIVE' &&
        log.id?.endsWith('src/react/index.ts')
      )
        return;
      handler(level, log);
    },
  },
  deps: {
    neverBundle: [
      /^@supabase\//,
      /^@opentelemetry\//,
      /^@orpc\//,
      /^@tanstack\//,
      /^node:/,
      'hono',
      'next',
      /^next\//,
      'pg',
      'react',
      'react-dom',
    ],
  },
});
