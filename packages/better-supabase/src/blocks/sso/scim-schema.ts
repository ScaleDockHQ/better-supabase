/** SCIM 2.0 schema URIs and the attributes this service provider supports (RFC 7643). */

export const SCIM_USER = "urn:ietf:params:scim:schemas:core:2.0:User";
export const SCIM_GROUP = "urn:ietf:params:scim:schemas:core:2.0:Group";
export const SCIM_LIST = "urn:ietf:params:scim:api:messages:2.0:ListResponse";
export const SCIM_ERROR = "urn:ietf:params:scim:api:messages:2.0:Error";
export const SCIM_PATCH = "urn:ietf:params:scim:api:messages:2.0:PatchOp";
export const SCIM_SEARCH =
  "urn:ietf:params:scim:api:messages:2.0:SearchRequest";
export const SCIM_SERVICE_PROVIDER_CONFIG =
  "urn:ietf:params:scim:schemas:core:2.0:ServiceProviderConfig";
export const SCIM_RESOURCE_TYPE =
  "urn:ietf:params:scim:schemas:core:2.0:ResourceType";
export const SCIM_SCHEMA = "urn:ietf:params:scim:schemas:core:2.0:Schema";

export interface ScimAttribute {
  readonly name: string;
  readonly type: "string" | "boolean" | "complex" | "reference";
  readonly multiValued: boolean;
  readonly description: string;
  readonly required: boolean;
  readonly caseExact?: boolean;
  readonly canonicalValues?: readonly string[];
  readonly referenceTypes?: readonly string[];
  readonly mutability: "readOnly" | "readWrite" | "immutable" | "writeOnly";
  readonly returned: "always" | "never" | "default" | "request";
  readonly uniqueness?: "none" | "server" | "global";
  readonly subAttributes?: readonly ScimAttribute[];
}

const text = (
  name: string,
  description: string,
  extra: Partial<ScimAttribute> = {},
): ScimAttribute => ({
  name,
  type: "string",
  multiValued: false,
  description,
  required: false,
  caseExact: false,
  mutability: "readWrite",
  returned: "default",
  uniqueness: "none",
  ...extra,
});

const reference = (mutability: ScimAttribute["mutability"]): ScimAttribute => ({
  name: "$ref",
  type: "reference",
  referenceTypes: ["User", "Group"],
  multiValued: false,
  description: "The URI of the resource.",
  required: false,
  caseExact: false,
  mutability,
  returned: "default",
  uniqueness: "none",
});

export const USER_ATTRIBUTES: readonly ScimAttribute[] = [
  text("userName", "Unique identifier for the User within the organization.", {
    required: true,
    uniqueness: "server",
  }),
  {
    name: "name",
    type: "complex",
    multiValued: false,
    description: "The components of the user's name.",
    required: false,
    mutability: "readWrite",
    returned: "default",
    uniqueness: "none",
    subAttributes: [
      text("formatted", "The full name."),
      text("familyName", "The family name."),
      text("givenName", "The given name."),
    ],
  },
  text("displayName", "The name of the User, suitable for display."),
  {
    name: "emails",
    type: "complex",
    multiValued: true,
    description:
      "Email addresses for the user. The primary address links the User to an account at a verified domain.",
    required: false,
    mutability: "readWrite",
    returned: "default",
    uniqueness: "none",
    subAttributes: [
      text("value", "The email address."),
      text("display", "A label for display."),
      text("type", "The kind of address.", {
        canonicalValues: ["work", "home", "other"],
      }),
      {
        name: "primary",
        type: "boolean",
        multiValued: false,
        description: "Whether this is the primary address.",
        required: false,
        mutability: "readWrite",
        returned: "default",
      },
    ],
  },
  {
    name: "active",
    type: "boolean",
    multiValued: false,
    description:
      "Whether the user may use the organization. False removes the membership.",
    required: false,
    mutability: "readWrite",
    returned: "default",
  },
  {
    name: "groups",
    type: "complex",
    multiValued: true,
    description: "The groups the user belongs to, through Group membership.",
    required: false,
    mutability: "readOnly",
    returned: "default",
    subAttributes: [
      text("value", "The id of the Group.", { mutability: "readOnly" }),
      reference("readOnly"),
      text("display", "The displayName of the Group.", {
        mutability: "readOnly",
      }),
    ],
  },
];

export const GROUP_ATTRIBUTES: readonly ScimAttribute[] = [
  text(
    "displayName",
    "A name for the Group. Groups named like a role, or mapped in groupRoles, grant that role.",
    { required: true },
  ),
  {
    name: "members",
    type: "complex",
    multiValued: true,
    description: "The Users in the Group.",
    required: false,
    mutability: "readWrite",
    returned: "default",
    subAttributes: [
      text("value", "The id of the User.", { mutability: "immutable" }),
      reference("immutable"),
      text("type", "The kind of member.", {
        canonicalValues: ["User"],
        mutability: "immutable",
      }),
    ],
  },
];

/** The writable attribute names of each resource, for PATCH paths. */
export const ATTRIBUTES: Readonly<
  Record<"User" | "Group", readonly ScimAttribute[]>
> = {
  User: [
    ...USER_ATTRIBUTES,
    text("externalId", "The client's identifier for the resource.", {
      caseExact: true,
    }),
  ],
  Group: [
    ...GROUP_ATTRIBUTES,
    text("externalId", "The client's identifier for the resource.", {
      caseExact: true,
    }),
  ],
};

export interface ScimDiscoveryOptions {
  readonly maxResults: number;
  readonly documentationUri?: string;
}

/** `/ServiceProviderConfig` (RFC 7643 §5). */
export function serviceProviderConfig(
  base: string,
  options: ScimDiscoveryOptions,
): Record<string, unknown> {
  return {
    schemas: [SCIM_SERVICE_PROVIDER_CONFIG],
    ...(options.documentationUri === undefined
      ? {}
      : { documentationUri: options.documentationUri }),
    patch: { supported: true },
    bulk: { supported: false, maxOperations: 0, maxPayloadSize: 0 },
    filter: { supported: true, maxResults: options.maxResults },
    changePassword: { supported: false },
    sort: { supported: false },
    etag: { supported: true },
    authenticationSchemes: [
      {
        type: "oauthbearertoken",
        name: "OAuth Bearer Token",
        description:
          "An organization API key with the scim scope, sent as a bearer token.",
        primary: true,
      },
    ],
    meta: {
      resourceType: "ServiceProviderConfig",
      location: `${base}/ServiceProviderConfig`,
    },
  };
}

/** `/ResourceTypes` entries (RFC 7643 §6). */
export function resourceTypes(
  base: string,
): readonly Record<string, unknown>[] {
  return [
    {
      schemas: [SCIM_RESOURCE_TYPE],
      id: "User",
      name: "User",
      endpoint: "/Users",
      description: "A member of the organization",
      schema: SCIM_USER,
      schemaExtensions: [],
      meta: {
        resourceType: "ResourceType",
        location: `${base}/ResourceTypes/User`,
      },
    },
    {
      schemas: [SCIM_RESOURCE_TYPE],
      id: "Group",
      name: "Group",
      endpoint: "/Groups",
      description: "A group of members, mapped to a role",
      schema: SCIM_GROUP,
      schemaExtensions: [],
      meta: {
        resourceType: "ResourceType",
        location: `${base}/ResourceTypes/Group`,
      },
    },
  ];
}

/** `/Schemas` entries (RFC 7643 §7). */
export function schemas(base: string): readonly Record<string, unknown>[] {
  return [
    {
      schemas: [SCIM_SCHEMA],
      id: SCIM_USER,
      name: "User",
      description: "User Account",
      attributes: USER_ATTRIBUTES,
      meta: {
        resourceType: "Schema",
        location: `${base}/Schemas/${SCIM_USER}`,
      },
    },
    {
      schemas: [SCIM_SCHEMA],
      id: SCIM_GROUP,
      name: "Group",
      description: "Group",
      attributes: GROUP_ATTRIBUTES,
      meta: {
        resourceType: "Schema",
        location: `${base}/Schemas/${SCIM_GROUP}`,
      },
    },
  ];
}
