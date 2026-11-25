import {
  organizationOwner,
  signingKeys,
} from "@/features/signing-keys/signing-keys-server";

const UUID = /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i;

/**
 * The organization's public signing keys as a JWK Set, for the receivers of its
 * tokens: the active key and the retired ones that tokens still need.
 */
export async function GET(
  _request: Request,
  { params }: RouteContext<"/.well-known/jwks/[organization]">,
): Promise<Response> {
  const { organization } = await params;

  if (!UUID.test(organization)) {
    return new Response(null, { status: 404 });
  }

  return signingKeys().jwksResponse({ owner: organizationOwner(organization) });
}
