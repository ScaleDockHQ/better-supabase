import { afterEach, describe, expect, it, vi } from 'vitest';

import { defineSupabase } from '../core/define.ts';
import { createEdge } from '../edge/index.ts';
import { ENV_VARIABLES, EnvValidationError } from '../env/index.ts';
import { schema } from '../fixtures/generated-camel.ts';
import { createHono } from '../hono/index.ts';
import { createMcp } from '../mcp/index.ts';
import { createOrpc } from '../orpc/index.ts';
import { createServer } from './server.ts';

afterEach(() => {
  vi.unstubAllEnvs();
});

describe('env loading', () => {
  it('waits for the first use, so builds without runtime env can import server modules', () => {
    for (const name of Object.values(ENV_VARIABLES).flat())
      vi.stubEnv(name, '');
    const sb = defineSupabase(schema);
    const servers = [
      createServer(sb),
      createEdge(sb),
      createHono(sb),
      createOrpc(sb),
      createMcp(sb, { name: 'test', version: '1.0.0' }),
    ];
    for (const server of servers) {
      expect(typeof server.context).toBe('function');
      expect(() => server.env).toThrow(EnvValidationError);
    }
  });
});
