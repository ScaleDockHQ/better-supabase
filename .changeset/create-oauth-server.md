---
"better-supabase": minor
---

The `oauth-server` block's creator is now `createOauthServer`, so it follows the `create<Name>` rule every other block uses, and its types write `Oauth` the same way. The old names keep working as deprecated aliases until the next minor release.

| Old                     | New                     |
| ----------------------- | ----------------------- |
| `createOAuthServer`     | `createOauthServer`     |
| `OAuthServer`           | `OauthServer`           |
| `OAuthServerOptions`    | `OauthServerOptions`    |
| `OAuthServerEvents`     | `OauthServerEvents`     |
| `OAuthClient`           | `OauthClient`           |
| `OAuthClientAuthMethod` | `OauthClientAuthMethod` |
| `OAuthClientMetadata`   | `OauthClientMetadata`   |
| `OAuthClientEventData`  | `OauthClientEventData`  |
| `RegisteredOAuthClient` | `RegisteredOauthClient` |
| `OAuthAuthorization`    | `OauthAuthorization`    |
| `OAuthGrant`            | `OauthGrant`            |
| `OAuthGrantType`        | `OauthGrantType`        |
| `OAuthGrantEventData`   | `OauthGrantEventData`   |

These names come from `better-supabase/blocks/oauth-server`. The `OAuthClient` type in `better-supabase/client/native` and `OAuthGrant` in `better-supabase/blocks/sessions` keep their names.
