# Deep links

Every incoming URL (custom scheme, universal link, push or in-app notification link) goes through
`DeepLinks.route(for:env:)` in `AppShell`, which maps it to a `Route` or to nothing. Unknown hosts, unknown paths and
malformed ids are ignored: nothing is ever opened raw.

## Accepted forms

| URL | Route |
|---|---|
| `voyager://share/<token>` | the share viewer |
| `https://<trusted host>/share/<token>` | the share viewer |
| `/alerts`, `/alerts?kind=<k>&watch=<id>` | Alerts (optionally a watch) |
| `/trips/{id}`, `/trips/{id}/today` | trip detail, Trips Today |
| `/feed`, `/feed/{id}`, `/u/{handle}`, `/play`, `/play/h2h/{id}` | social and play |
| `voyager://import?url=<url>` | Plan from a link (custom scheme only) |

A trusted host is one of `VOYAGER_TRUSTED_HOSTS` (Info.plist `VoyagerTrustedHosts`); `http`, other schemes and other
hosts are ignored.

## Share links

A share token is 8 to 64 URL-safe characters (`A-Z a-z 0-9 - _`); anything else is not a share link. The viewer
(`FeatureShare`) calls the public `GET /api/share/{token}` (no sign-in) and picks a view from `kind`:

| `kind` | View |
|---|---|
| none (legacy token) or `plan` | the read-only plan with "Inspired by" and Remix |
| `recap`, `savings` (with a `card`) | the card: headline, destination and month, counts-only stats, "Plan your own trip" |
| anything else (`quiz`, `status`, later kinds) | the headline and "Open in browser" (`SFSafariViewController` on the share's own https page) |
| 404 (unknown, revoked, sharing off) | "This shared trip isn't available" |

`owner_name` is shown only when the server sent it (the sharer chose to show their name). The app never sends
`share_view` (SPA only). Universal links work once the owner adds the associated-domains entitlement and the
`apple-app-site-association` file; until then the pasted-link path (My shares > Open a link) and the custom scheme
open the same viewer.

## Notification links

A notification `link` is mapped through `DeepLinks.route(forNotificationLink:)`: only a bare path (`/trips/7/today`)
is accepted, never a scheme, host or `//host`.
