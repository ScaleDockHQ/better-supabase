import { describe, expect, it } from 'vitest';
import { z } from 'zod';

import { defineSupabase } from '../core/define.ts';
import { dbError } from '../core/errors.ts';
import { err } from '../core/result.ts';
import { schema } from '../fixtures/generated-camel.ts';
import { defineListQuery } from '../list/index.ts';
import { createTestSigner } from '../testing/jwt.ts';
import { createMcp, defineTool, MCP_PROTOCOL_VERSION } from './index.ts';

const PROJECT_URL = 'https://abcdefghijklmnopqrst.supabase.co';
const env = {
  url: PROJECT_URL,
  publishableKey: 'sb_publishable_test',
  jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
};
const USER = '11111111-1111-4111-8111-111111111111';
const ENDPOINT = 'https://tools.test/mcp';
const signer = await createTestSigner();

describe('createMcp', () => {
  const sb = defineSupabase(schema);
  const list = defineListQuery(sb, 'customers', {
    search: ['name'],
    sorts: { name: { name: 'asc' } },
    defaultSort: 'name',
  });
  const mcp = createMcp(sb, {
    env,
    auth: { jwks: signer.jwks as never },
    name: 'crm',
    version: '1.0.0',
    instructions: 'Customer records of the caller’s organization.',
    resources: {
      customers: { list },
      tags: { operations: ['list', 'get'] },
    },
    tools: [
      defineTool({
        name: 'echo',
        description: 'Echoes a message.',
        input: z.object({ message: z.string().min(1) }),
        annotations: { readOnlyHint: true },
        run: (args: { message: string }) => ({ echoed: args.message }),
      }),
    ],
    allowedOrigins: ['https://claude.test'],
  }).tool({
    name: 'whoami',
    description: 'The signed-in user.',
    run: (_args, ctx) =>
      ctx.auth.kind === 'user'
        ? { id: ctx.auth.user.id }
        : err(dbError('unauthorized', 'No user')),
  });

  const rpc = async (
    body: unknown,
    init: { token?: string | null; headers?: Record<string, string> } = {},
  ) => {
    const token =
      init.token === undefined ? await signer.sign({ sub: USER }) : init.token;
    return mcp.fetch(
      new Request(ENDPOINT, {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          accept: 'application/json, text/event-stream',
          ...(token ? { authorization: `Bearer ${token}` } : {}),
          ...init.headers,
        },
        body: typeof body === 'string' ? body : JSON.stringify(body),
      }),
    );
  };
  const result = async (method: string, params?: unknown) =>
    (
      (await (await rpc({ jsonrpc: '2.0', id: 1, method, params })).json()) as {
        result: Record<string, unknown>;
      }
    ).result;

  it('answers 401 with RFC 9728 metadata for anonymous clients', async () => {
    const response = await rpc(
      { jsonrpc: '2.0', id: 1, method: 'initialize' },
      { token: null },
    );
    expect(response.status).toBe(401);
    expect(response.headers.get('www-authenticate')).toBe(
      'Bearer resource_metadata="https://tools.test/.well-known/oauth-protected-resource/mcp"',
    );
    const metadata = await mcp.fetch(
      new Request(
        'https://tools.test/.well-known/oauth-protected-resource/mcp',
      ),
    );
    expect(await metadata.json()).toEqual({
      resource: 'https://tools.test/mcp',
      authorization_servers: [`${PROJECT_URL}/auth/v1`],
      bearer_methods_supported: ['header'],
    });
  });

  it('initializes and lists tools with JSON Schema inputs and annotations', async () => {
    expect(
      await result('initialize', {
        protocolVersion: MCP_PROTOCOL_VERSION,
        capabilities: {},
        clientInfo: { name: 'test', version: '1' },
      }),
    ).toMatchObject({
      protocolVersion: MCP_PROTOCOL_VERSION,
      capabilities: { tools: {} },
      serverInfo: { name: 'crm', version: '1.0.0' },
      instructions: expect.stringContaining('Customer'),
    });
    const { tools } = (await result('tools/list')) as {
      tools: {
        name: string;
        inputSchema: Record<string, unknown>;
        annotations?: unknown;
      }[];
    };
    expect(tools.map((tool) => tool.name)).toEqual([
      'customers_list',
      'customers_get',
      'customers_create',
      'customers_update',
      'customers_delete',
      'tags_list',
      'tags_get',
      'echo',
      'whoami',
    ]);
    const byName = new Map(tools.map((tool) => [tool.name, tool]));
    expect(byName.get('customers_list')?.annotations).toMatchObject({
      readOnlyHint: true,
    });
    expect(byName.get('customers_delete')?.annotations).toMatchObject({
      destructiveHint: true,
      idempotentHint: true,
    });
    expect(byName.get('customers_list')?.inputSchema).toMatchObject({
      type: 'object',
      properties: { q: expect.any(Object), sort: expect.any(Object) },
    });
    expect(byName.get('customers_create')?.inputSchema).toMatchObject({
      required: expect.arrayContaining(['name', 'organizationId']),
    });
    expect(byName.get('customers_update')?.inputSchema).toMatchObject({
      required: ['id', 'patch'],
    });
    expect(byName.get('echo')?.inputSchema).toMatchObject({
      type: 'object',
      properties: { message: { type: 'string', minLength: 1 } },
      required: ['message'],
    });
    expect(byName.get('echo')?.inputSchema).not.toHaveProperty('$schema');
  });

  it('calls tools as the caller and reports failures as tool errors', async () => {
    expect(
      await result('tools/call', { name: 'whoami', arguments: {} }),
    ).toEqual({
      content: [{ type: 'text', text: JSON.stringify({ id: USER }) }],
      structuredContent: { id: USER },
    });
    const invalid = await result('tools/call', {
      name: 'echo',
      arguments: { message: '' },
    });
    expect(invalid).toMatchObject({
      isError: true,
      structuredContent: {
        kind: 'validation',
        issues: [{ path: ['message'] }],
      },
    });
    const badKey = await result('tools/call', {
      name: 'customers_get',
      arguments: {},
    });
    expect(badKey).toMatchObject({
      isError: true,
      structuredContent: { kind: 'invalid_request' },
    });
  });

  it('follows the Streamable HTTP rules', async () => {
    expect(
      (await rpc({ jsonrpc: '2.0', method: 'notifications/initialized' }))
        .status,
    ).toBe(202);
    expect((await rpc('{nope')).status).toBe(400);
    expect(
      await (
        await rpc({ jsonrpc: '2.0', id: 2, method: 'resources/list' })
      ).json(),
    ).toMatchObject({ id: 2, error: { code: -32601 } });
    expect(
      await (
        await rpc({
          jsonrpc: '2.0',
          id: 3,
          method: 'tools/call',
          params: { name: 'nope' },
        })
      ).json(),
    ).toMatchObject({ id: 3, error: { code: -32602 } });
    expect(
      (
        await rpc(
          { jsonrpc: '2.0', id: 4, method: 'ping' },
          { headers: { 'mcp-protocol-version': '1999-01-01' } },
        )
      ).status,
    ).toBe(400);
    expect(
      (
        await rpc(
          { jsonrpc: '2.0', id: 5, method: 'ping' },
          { headers: { origin: 'https://evil.test' } },
        )
      ).status,
    ).toBe(403);
    expect((await mcp.fetch(new Request(ENDPOINT))).status).toBe(405);
  });

  it('rejects invalid tool definitions', () => {
    expect(() =>
      defineTool({ name: 'has space', description: 'x', run: () => null }),
    ).toThrow('Invalid tool name');
    expect(() =>
      mcp.tool({ name: 'echo', description: 'again', run: () => null }),
    ).toThrow('Duplicate MCP tool "echo"');
  });
});
