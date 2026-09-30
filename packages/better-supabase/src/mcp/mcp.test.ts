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

  it('initializes legacy clients and lists tools with JSON Schema inputs and annotations', async () => {
    expect(
      await result('initialize', {
        protocolVersion: '2025-06-18',
        capabilities: {},
        clientInfo: { name: 'test', version: '1' },
      }),
    ).toMatchObject({
      protocolVersion: '2025-06-18',
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

  const modern = (
    id: number,
    method: string,
    params: Record<string, unknown> = {},
    headers: Record<string, string> = {},
  ) =>
    rpc(
      {
        jsonrpc: '2.0',
        id,
        method,
        params: {
          ...params,
          _meta: {
            'io.modelcontextprotocol/protocolVersion': MCP_PROTOCOL_VERSION,
            'io.modelcontextprotocol/clientCapabilities': {},
          },
        },
      },
      {
        headers: {
          'mcp-protocol-version': MCP_PROTOCOL_VERSION,
          'mcp-method': method,
          ...headers,
        },
      },
    );

  it('serves 2026-07-28 requests without a handshake', async () => {
    expect(MCP_PROTOCOL_VERSION).toBe('2026-07-28');
    const discover = await (await modern(1, 'server/discover')).json();
    expect(discover.result).toMatchObject({
      supportedVersions: [
        '2026-07-28',
        '2025-11-25',
        '2025-06-18',
        '2025-03-26',
      ],
      capabilities: { tools: { listChanged: false } },
      instructions: expect.stringContaining('Customer'),
      cacheScope: 'private',
      resultType: 'complete',
      _meta: {
        'io.modelcontextprotocol/serverInfo': { name: 'crm', version: '1.0.0' },
      },
    });
    const list = await (await modern(2, 'tools/list')).json();
    expect(list.result).toMatchObject({
      ttlMs: expect.any(Number),
      cacheScope: 'private',
      resultType: 'complete',
    });
    const call = await (
      await modern(
        3,
        'tools/call',
        { name: 'whoami', arguments: {} },
        { 'mcp-name': `=?base64?${btoa('whoami')}?=` },
      )
    ).json();
    expect(call.result).toMatchObject({
      structuredContent: { id: USER },
      resultType: 'complete',
    });
    const removed = await modern(4, 'initialize');
    expect(removed.status).toBe(404);
    expect((await modern(5, 'ping')).status).toBe(404);
  });

  it('rejects 2026-07-28 requests whose headers or _meta disagree', async () => {
    const mismatch = await modern(
      1,
      'tools/call',
      { name: 'whoami' },
      { 'mcp-name': 'echo' },
    );
    expect(mismatch.status).toBe(400);
    expect(await mismatch.json()).toMatchObject({ error: { code: -32020 } });
    expect(
      await (
        await modern(2, 'tools/list', {}, { 'mcp-method': 'tools/call' })
      ).json(),
    ).toMatchObject({ error: { code: -32020 } });
    const unsupported = await rpc(
      { jsonrpc: '2.0', id: 3, method: 'tools/list' },
      { headers: { 'mcp-protocol-version': '1999-01-01' } },
    );
    expect(unsupported.status).toBe(400);
    expect(await unsupported.json()).toMatchObject({
      error: {
        code: -32022,
        data: { requested: '1999-01-01', supported: expect.any(Array) },
      },
    });
    const noMeta = await rpc(
      { jsonrpc: '2.0', id: 4, method: 'tools/list' },
      {
        headers: {
          'mcp-protocol-version': MCP_PROTOCOL_VERSION,
          'mcp-method': 'tools/list',
        },
      },
    );
    expect(noMeta.status).toBe(400);
    expect(await noMeta.json()).toMatchObject({ error: { code: -32602 } });
  });

  it('challenges with insufficient_scope and publishes scopes without offline_access', async () => {
    const scoped = createMcp(sb, {
      env,
      auth: { jwks: signer.jwks as never },
      name: 'admin',
      version: '1.0.0',
      allow: ['service'],
      scopes: ['openid', 'crm.read', 'offline_access'],
    });
    const response = await scoped.fetch(
      new Request(ENDPOINT, {
        method: 'POST',
        headers: {
          authorization: `Bearer ${await signer.sign({ sub: USER })}`,
          'content-type': 'application/json',
        },
        body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/list' }),
      }),
    );
    expect(response.status).toBe(403);
    const challenge = response.headers.get('www-authenticate') ?? '';
    expect(challenge).toMatch(/^Bearer error="insufficient_scope", /);
    expect(challenge).toContain('scope="openid crm.read"');
    expect(challenge).toContain(
      'resource_metadata="https://tools.test/.well-known/oauth-protected-resource/mcp"',
    );
    const anonymous = await scoped.fetch(
      new Request(ENDPOINT, { method: 'POST', body: '{}' }),
    );
    expect(anonymous.headers.get('www-authenticate')).toContain(
      'scope="openid crm.read"',
    );
    const metadata = await scoped.fetch(
      new Request(
        'https://tools.test/.well-known/oauth-protected-resource/mcp',
      ),
    );
    expect(await metadata.json()).toMatchObject({
      scopes_supported: ['openid', 'crm.read'],
    });
  });

  it('authorizes calls and filters lists with per-tool hooks', async () => {
    const seen: { tool: string; meta: unknown; args: unknown }[] = [];
    const guarded = createMcp(sb, {
      env,
      auth: { jwks: signer.jwks as never },
      name: 'guarded',
      version: '1.0.0',
      scopes: ['openid'],
      resources: { tags: { operations: ['list'] } },
      tools: [
        defineTool({
          name: 'read_notes',
          description: 'Reads notes.',
          input: z.object({ limit: z.coerce.number() }),
          meta: { permission: 'notes.read' },
          run: (args: { limit: number }) => ({ limit: args.limit }),
        }),
        defineTool({
          name: 'export_notes',
          description: 'Exports notes.',
          meta: { permission: 'notes.export', scope: 'notes.export' },
          run: () => ({ exported: true }),
        }),
        defineTool({
          name: 'purge_notes',
          description: 'Deletes every note.',
          meta: { permission: 'notes.purge' },
          run: () => ({ purged: true }),
        }),
        defineTool({
          name: 'secret',
          description: 'Hidden from everyone.',
          meta: { hidden: true },
          run: () => 'never',
        }),
      ],
      authorize: (_ctx, tool, args) => {
        const meta = tool.meta as
          | { permission?: string; scope?: string }
          | undefined;
        seen.push({ tool: tool.info.name, meta: tool.meta, args });
        if (tool.info.name === 'tags_list') {
          return { allowed: false, reason: 'No tags for you' };
        }
        if (meta?.permission === 'notes.purge') {
          return { allowed: false, reason: 'Only owners may purge notes' };
        }
        if (meta?.scope) {
          return { allowed: false, scopes: ['notes.read', meta.scope] };
        }
        return { allowed: true };
      },
      visible: (ctx, tool) =>
        ctx.auth.kind === 'user' &&
        (tool.meta as { hidden?: boolean } | undefined)?.hidden !== true,
    });
    const send = async (method: string, params?: unknown) =>
      guarded.fetch(
        new Request(ENDPOINT, {
          method: 'POST',
          headers: {
            authorization: `Bearer ${await signer.sign({ sub: USER })}`,
            'content-type': 'application/json',
          },
          body: JSON.stringify({ jsonrpc: '2.0', id: 7, method, params }),
        }),
      );

    const listed = (await (await send('tools/list')).json()) as {
      result: { tools: { name: string; meta?: unknown }[] };
    };
    expect(listed.result.tools.map((tool) => tool.name)).toEqual([
      'tags_list',
      'read_notes',
      'export_notes',
      'purge_notes',
    ]);
    expect(listed.result.tools[1]).not.toHaveProperty('meta');

    const allowed = (await (
      await send('tools/call', {
        name: 'read_notes',
        arguments: { limit: '5' },
      })
    ).json()) as { result: unknown };
    expect(allowed.result).toMatchObject({ structuredContent: { limit: 5 } });
    expect(seen.at(-1)).toEqual({
      tool: 'read_notes',
      meta: { permission: 'notes.read' },
      args: { limit: 5 },
    });

    const invalid = (await (
      await send('tools/call', { name: 'read_notes', arguments: {} })
    ).json()) as { result: unknown };
    expect(invalid.result).toMatchObject({ isError: true });
    expect(seen).toHaveLength(1);

    const refused = (await (
      await send('tools/call', { name: 'purge_notes', arguments: {} })
    ).json()) as { result: unknown };
    expect(refused.result).toMatchObject({
      isError: true,
      structuredContent: {
        kind: 'forbidden',
        detail: 'Only owners may purge notes',
      },
    });

    const challenged = await send('tools/call', {
      name: 'export_notes',
      arguments: {},
    });
    expect(challenged.status).toBe(403);
    expect(challenged.headers.get('www-authenticate')).toContain(
      'Bearer error="insufficient_scope", error_description="Not allowed to call export_notes", scope="openid notes.read notes.export"',
    );
    expect(await challenged.json()).toMatchObject({ id: 7 });

    const hidden = (await (
      await send('tools/call', { name: 'secret', arguments: {} })
    ).json()) as { error: { code: number; message: string } };
    expect(hidden.error).toMatchObject({
      code: -32602,
      message: 'Unknown tool "secret"',
    });

    const table = (await (
      await send('tools/call', { name: 'tags_list', arguments: { page: 2 } })
    ).json()) as { result: unknown };
    expect(seen.at(-1)).toEqual({
      tool: 'tags_list',
      meta: undefined,
      args: { page: 2 },
    });
    expect(table.result).toMatchObject({
      isError: true,
      structuredContent: { kind: 'forbidden', detail: 'No tags for you' },
    });

    // Direct calls have no HTTP challenge, so a scope refusal is a tool error.
    const direct = await guarded.call('export_notes', {}, {
      auth: { kind: 'user' },
    } as never);
    expect(direct).toMatchObject({
      isError: true,
      structuredContent: { kind: 'forbidden' },
    });
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
