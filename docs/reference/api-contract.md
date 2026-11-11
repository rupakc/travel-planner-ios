# Travel Planner backend API contract (for a mobile client)

> Copied from `rupakc/travel-planner-android` (`docs/reference/`). On any conflict, `docs/API-Reference.md` in `rupakc/travel-planner` wins; the backend code is the source of truth.

Source of truth: `/Users/rupak/travel-planner/backend/app` (FastAPI), cross-checked with `frontend/src/services/api.js`, `workers/sseWorker.js`, `workers/chatWorker.js`, `pages/ResultsPage.jsx`, `pages/ChatPage.jsx`. Read-only analysis; nothing was run. Anything marked **UNVERIFIED** was not confirmed from code. Default dev base URL: `http://localhost:8001` (emulator: `http://10.0.2.2:8001`). All endpoints live under `/api` except `/health`, `/health/agents`.

---------------------------------------------------------------------------
## 0. Cross-cutting facts

### 0.1 Auth / JWT (`core/auth.py`, `api/routes/auth.py`)
- No registration. Admin creates users (`POST /api/admin/users`). First login of a created user has `requires_password_change=true` (temp password).
- Login: `POST /api/auth/login` JSON `{username, password}` -> `{access_token, token_type:"bearer", user:{...}}`.
- Send `Authorization: Bearer <access_token>` on every authenticated call. Scheme parsed by FastAPI `HTTPBearer(auto_error=False)`.
- JWT: HS256 (PyJWT), expiry **24 h** (`ACCESS_TOKEN_EXPIRE_HOURS = 24`), claims: `sub` (username), `is_admin` (bool), `is_first_login` (bool), `exp`. **No refresh endpoint and no refresh token**: after 24 h (or `401`) the client must re-login (store credentials or prompt). The server re-reads the user from DB on every request (is_active/is_admin come from DB, not the token claims).
- `change-password` returns a fresh token (replace the stored one).
- Min password length 8 (`MIN_PASSWORD_LENGTH`).
- Dependency flavours:
  - `required` = `get_current_user`: missing header -> `401 {"detail":"Not authenticated"}`; bad/expired token -> `401 {"detail":"Invalid or expired token"}`; unknown/inactive user -> `401 {"detail":"User not found or inactive"}`.
  - `optional` = `get_optional_user`: no/invalid token or inactive user = anonymous (no error).
  - `admin` = `require_admin`: non-admin -> `403 {"detail":"Admin access required"}`.
  - `none` = no auth dependency.
- JWT secret default is `""` (settings.jwt_secret_key) - server-side config, irrelevant to client.

### 0.2 `/api/auth/me` and login `user` shape
```json
{"username":"alice","is_admin":false,"requires_password_change":false,"email":null}
```
(`email` is `string|null`.) Login's `user` object has the same four keys.

### 0.3 Error shapes
- Normal errors: `{"detail":"<human string>"}`; the web client only displays `detail` if it is a non-blank string (`utils/httpError.js`), else falls back to `HTTP <status>`.
- Pydantic/FastAPI validation errors: `422` with `{"detail":[{"loc":[...],"msg":"...","type":"..."}]}` (detail is a **list** here - handle both).
- Structured-detail errors exist: `/api/import/*` use `detail: {"code": "...", "message": "..."}` (object). Price-watch 422s `no_live_price` / `target_currency_mismatch` are top-level JSON with `detail` (string) **plus** extra top-level keys (see 8.3).
- `429` rate limit: `{"detail":"Too many requests — please wait N seconds and try again."}` + header `Retry-After: N` (seconds). The check runs before the SSE stream starts, so it is a normal HTTP 429 (not an SSE event).
- `413` for `/api/import/*` bodies > 30 MB (`BodySizeLimit`); message "That upload is too big — use up to 4 screenshots of 5 MB or less." (exact JSON shape of the 413 body: **UNVERIFIED**, in `core/body_limit.py`).
- Every response carries `X-Request-ID` (echoes inbound `X-Request-ID` header if sent).

### 0.4 Rate limits (`core/rate_limit.py`, `main.py`)
In-process sliding window, **key = signed-in username, else client IP**, window `RATE_LIMIT_WINDOW_SECONDS` = 600 s. Buckets (defaults per window): `search` 10, `chat` 30, `compare` 30, `discover` 10, `light_ai` 60, `import` 20. Disabled when `RATE_LIMIT_ENABLED=false`. Router-level assignments:

| Bucket | Routes |
|---|---|
| search | `/search`, `/search/sync` |
| chat | `/chat` (plus one `search` token consumed in-stream per full trip plan; over limit -> friendly `delta` text + `done`, NOT a 429) |
| compare | `/compare/destination` |
| discover | `/discover` |
| light_ai | `/flights*`, `/hotels*`, `/activities*`, `/visa`, `/sim`, `/tips`, `/getting-around`, `/forex`, `/itinerary`, `/events`, `/walking-tours`, `/layover`, `/stress-test`, `PUT /auth/email`, `POST /fare-watches`, `POST /fare-watches/{id}/check`, `POST /price-watches`, `POST /price-watches/{id}/check` |
| import | `/import/extract`, `/import/resolve-place` |
| none | everything else (auth, plans, preferences, recent-searches, airports, nationalities, taste, notifications, GET/PATCH/DELETE watches, feedback, analytics, admin, share) |

Note: the rate-limit dependency runs on the whole router, so `/flights/fare-calendar` (auth required) is also light_ai.

### 0.5 Browser-only things / mobile implications
- **CORS** (`CORSMiddleware`, `allow_origins = settings.cors_origins`, default `["http://localhost:5174","http://localhost:5173"]`, `allow_credentials=True`, methods/headers `*`). CORS is enforced only by browsers; a native Android HTTP client (OkHttp) ignores it. No change needed unless the Android client is a WebView (then its origin must be in `CORS_ORIGINS`).
- **No cookies**: auth is bearer-header only. The web app stores the token in JS (AuthContext). No CSRF.
- **Cleartext HTTP**: default backend is `http://localhost:8001`. Android 9+ blocks cleartext traffic by default; a `networkSecurityConfig` (or HTTPS) is needed for `http://10.0.2.2:8001` / LAN IP dev. Production was decommissioned 2026-08-30; **there is no live public host** (per CLAUDE.md), so the client needs a configurable base URL.
- **Web uses relative `/api`** via a Vite/nginx proxy; the Android client must prepend the full base URL.
- **Proxy buffering**: SSE responses send `Cache-Control: no-cache` and `X-Accel-Buffering: no`; any reverse proxy in front must not buffer.
- Frontend `<a href>`-style links: share link web URL is `<APP_BASE_URL>/share/<token>` (SharePage route; exact path **UNVERIFIED** from App.jsx - the API itself is `GET /api/share/{token}`). Fare/price-watch email unsubscribe pages return HTML (`GET/POST /api/fare-watches/unsubscribe?token=`, `/api/price-watches/unsubscribe?token=`), not for the app.
- The web app persists chat history in `localStorage` per user (not server-side) - the Android app must keep its own chat history; the server is stateless for chat (client resends `messages`, `session_context`).
- `POST /api/search` is **anonymous-OK**; `POST /api/chat` is **auth-REQUIRED** (even though the web code sends the token "optionally").

### 0.6 Health
- `GET /health` (no auth, no rate limit) -> `{"status":"ok","service":"travel-planner-backend","serpapi_configured":bool,"fare_watch_available":bool,"email_alerts_available":bool}`. Web uses these three flags to enable fare calendar / watch / email features.
- `GET /health/agents` -> `{"llm":"ok"|"empty-response"|"error: <ExcType>","serpapi_configured":bool,"backup_configured":bool}` (cached 5 min; makes an LLM call).

---------------------------------------------------------------------------
## 1. Shared request model `TravelSearchRequest` (`schemas/request.py`)
Used by `/search`, `/search/sync`, `/flights`, `/hotels`, `/activities`, `/visa`, `/sim`, `/tips`, `/getting-around`, `/forex`, `/itinerary`, `/events`, `/walking-tours`, `/compare/destination`, `/flights/fare-calendar` and (as base) the `*/filtered` and `/stress-test` models. Unknown extra fields are ignored (default pydantic).

| Field | Type | Req | Default | Constraints |
|---|---|---|---|---|
| origin | string | yes | - | Free text or IATA code. A bare 3-letter code is rewritten server-side to `"City, Country"`; airport codes resolved from local DB (typed cities too). |
| destination | string | yes | - | Same rewriting as origin. |
| departure_date | date `YYYY-MM-DD` | yes | - | |
| return_date | date\|null | no | null | No server check vs departure in this model (recent-searches does check). |
| interests | string[] | no | [] | e.g. food, history, adventure |
| nationality | string | **yes** | - | e.g. "American", "Indian" (typeahead: `/nationalities/search`) |
| residence_permits | string[] | no | [] | |
| existing_visas | string[] | no | [] | |
| budget_usd | number\|null | no | null | total trip budget |
| num_travelers | int | no | 1 | 1..20 |
| adults / children / seniors / infants | int | no | 1 / 0 / 0 / 0 | >= 0 each (no cross-check with num_travelers) |
| accessibility_needs | string[] | no | [] | e.g. wheelchair, visual_impairment, hearing_impairment, cognitive_disability |
| destinations | string[]\|null | no | null | Multi-city ordered list; **final destination last, same as `destination`**. Multi-city when length > 1. |
| destination_nights | (int\|null)[]\|null | no | null | aligned with `destinations` |
| pace | string | no | "balanced" | regex `^(relaxed\|balanced\|packed)$` |
| serendipity | number | no | 0.5 | 0.0..1.0 |
| must_include | MustIncludePlace[]\|null | no | null | max 25; deduped server-side |
| import_source | {url?:http(s) string<=2048, title?:<=200}\|null | no | null | |
| taste_context | string\|null | no | null | **ignored/overwritten server-side** |

`MustIncludePlace`: `name` (1..120, required), `kind` (<=20, default "sight"; unknown -> "sight"), `city?` (<=80), `town?` (<=80), `lat?` (-90..90), `lng?` (-180..180), `note?` (<=140), `quote?` (<=120), `verified` (bool, default false).

Example (from CLAUDE.md): `{"origin":"NYC","destination":"Tokyo","departure_date":"2026-04-01","return_date":"2026-04-08","interests":["food","history"],"nationality":"American","budget_usd":3000,"num_travelers":2}`.

Dates serialise as ISO strings. Web app only adds optional fields it has (the `*Filtered` helpers send a reduced subset: origin, destination, departure_date, return_date, interests, nationality, residence_permits, existing_visas, budget_usd, num_travelers + filters).

Filter models (extend the above):
- `FlightFilteredSearchRequest`: `max_stops` int 0..2, `max_price_usd` >=0, `departure_time_earliest|latest`, `arrival_time_earliest|latest` (regex `^\d{2}:\d{2}$`).
- `HotelFilteredSearchRequest`: `num_beds` 1..4, `max_price_per_night_usd` >=0, `wifi_quality` `^(basic|good|excellent)$`, `max_distance_from_center_km` >=0, `private_washroom` bool.
- `ActivityFilteredSearchRequest`: `filter_interests` string[], `max_price_usd` >=0, `available_from`/`available_to` date, `min_rating` 0..5.
- `DiscoveryRequest`: `origin` (req), `budget_usd?` >=0, `departure_date` (req), `return_date?`, `nationality` (req), `interests[]`, `adults` >=1 (default 1), `children`/`seniors`/`infants` >=0.

---------------------------------------------------------------------------
## 2. Endpoint catalogue

Legend: Auth = none / optional / required / admin. Bucket per 0.4.

### 2.1 Search & single-agent routes
| Method Path | Auth | Bucket | Request | Response |
|---|---|---|---|---|
| POST `/api/search` | optional | search | `TravelSearchRequest` | **SSE** `text/event-stream` (section 3). Cached 30 min when the whole run succeeded (replayed identically, instantly). Optional auth only changes taste-profile injection. |
| POST `/api/search/sync` | optional | search | same | JSON dict of all sections (`orchestrator.run`); testing only, slow. Exact keys **UNVERIFIED** (see orchestrator `run` lines 84-150: sections keyed flights, weather, hotels, activities, ..., itinerary). |
| POST `/api/flights` | none | light_ai | TravelSearchRequest | flights section (3.4.1) |
| POST `/api/flights/filtered` | none | light_ai | FlightFilteredSearchRequest | flights section + `verification` (enriched) |
| POST `/api/flights/fare-calendar` | **required** | light_ai | TravelSearchRequest | `{"dates":[{"departure_date":"2026-04-01","return_date":"2026-04-08","cheapest_usd":812.0\|null,"is_selected":bool}],"currency":"USD","source":"google_flights"}`; errors: `422 "Fare calendar is only available for single-destination trips."`, `503 "Fare calendar needs live flight data, which isn't configured."` |
| POST `/api/hotels`, `/api/hotels/filtered` | none | light_ai | TravelSearchRequest / Hotel filtered | hotels section (+verification on filtered) |
| POST `/api/activities`, `/api/activities/filtered` | none | light_ai | ... | activities section |
| POST `/api/visa` `/sim` `/tips` `/getting-around` `/forex` `/itinerary` `/events` `/walking-tours` | none | light_ai | TravelSearchRequest | the matching section (3.4) , no `verification` key |
| POST `/api/layover` | none | light_ai | `{city:string min2, duration_hours:number (0,48], nationality:string min2, airport?:string, arrival_time?:"HH:MM", interests?:string[]}` | layover mini-plan JSON; fields **UNVERIFIED** (see `.agents/layover.md`) |
| POST `/api/stress-test` | none (web sends token if it has one) | light_ai | TravelSearchRequest **plus** `itinerary: object` (required, `{days:[...]}`), `flights?`, `visa?`, `weather?` objects | stress_test section (3.4.16) |
| POST `/api/discover` | none | discover | `DiscoveryRequest` | "Surprise me": 5 destination suggestions; cached 30 min; `504 "Discovery timed out — please try again"`, `500 "Discovery failed — please try again"`. Response field names **UNVERIFIED** (see `.agents/discovery.md`, `discovery_agent.py`). |
| POST `/api/compare/destination` | **required** | compare | TravelSearchRequest (single-city only) | one-destination summary (cost, flight, hotel, weather, visa, ease, `missing[]`); `422 "Compare works with single destinations"`; `502 "Couldn't load this destination — please retry"`. Exact keys: see `services/compare.py::summarize_destination` (**UNVERIFIED**, not read). |
| POST `/api/import/extract` | required | import | `ImportRequest`: exactly one of `url` (<=2048), `text` (<=20000), `images` [{`media_type`<=64, `data_base64`}] (1..4 effective; schema max 8); **extra**: exactly-one rule violation -> 422 | `ImportPreview` `{source:{kind,url?,title?,site_name?,favicon_url?,author?}, title, summary?, destinations:[{name,city,country,airports[],lat?,lng?,place_count,nights}], places:[PreviewPlace], unresolved:[PreviewPlace], also_mentioned:[{name,place_count}], suggested_days:int, season_hint?, interests[], warnings[]}`; `PreviewPlace`={id,name,kind,city?,country?,destination?,lat?,lng?,approximate(bool),verified,address?,rating?,note?,quote?,day_hint?,confidence}. Errors are `detail:{code,message}`: `too_many_images`, `image_too_large`, `heic_unsupported`, `empty_page`, `no_places`, `extract_failed`(502) + fetch codes from `link_fetch` (422). Web uses a 90 s timeout. Images <= 5 MB each (PNG/JPEG/GIF/WebP; HEIC refused). |
| POST `/api/import/resolve-place` | required | import | `{id?(<=20), name(<=120), kind="sight", city(<=80), country?(<=80), note?(<=140), quote?(<=120)}` | `ResolvedPlace` (fields **UNVERIFIED**, `schemas/link_import.py:287`); `422 detail:{code:"city_not_found",message}` |

### 2.2 Chat
| POST `/api/chat` | **required** | chat | see 4.1 | SSE (section 4) |

### 2.3 Reference data (no auth, no limit)
- `GET /api/airports/search?q=<str min1>&limit=10 (1..50)` -> array of `{iata_code,name,city,country,country_code}`.
- `GET /api/nationalities/search?q=<str min1>&limit=10 (1..50)` -> array of `{nationality,country,country_code}`.

### 2.4 Auth
| Method Path | Auth | Request | Response / errors |
|---|---|---|---|
| POST `/api/auth/login` | none | `{username,password}` | 200 `{access_token,token_type:"bearer",user}`; `401 "Invalid username or password"` |
| GET `/api/auth/me` | required | - | 0.2 shape |
| POST `/api/auth/change-password` | required | `{current_password,new_password}` | `{access_token,token_type:"bearer"}`; `400 "Current password is incorrect"`; `400 "New password must be at least 8 characters"` |
| PUT `/api/auth/email` | required, light_ai | `{email:string<=254}` ("" clears) | `{"email":"a@b.com"|null}`; `422 "That doesn't look like an email address."`; `409 "Another account already uses that email."` |

### 2.5 Plans (auth required; owner-only, 404 otherwise)
Plan object (`plans_db._row_to_dict`): `{id:int, username, name, search_data:object, selections:object, created_at:"YYYY-MM-DD HH:MM:SS"(SQLite UTC), updated_at, share_token:string|null}`.
- `GET /api/plans` -> `Plan[]` (newest updated first).
- `POST /api/plans` `{name:string, search_data:object, selections:object}` (all required) -> `Plan` (also records taste signals).
- `GET /api/plans/{id}` -> Plan; `404 "Plan not found"`.
- `PUT /api/plans/{id}` `{name?:string, selections?:object}` (search_data is immutable after create) -> Plan.
- `DELETE /api/plans/{id}` -> `{"success":true}`.
- `POST /api/plans/{id}/share` -> `{"share_token":"<22-char urlsafe>"}` (idempotent, reuses existing).
- `DELETE /api/plans/{id}/share` -> `{"success":true}`.
- `GET /api/share/{token}` (**no auth**) -> `{name,created_at,updated_at,search_data:{origin,destination,destinations,departure_date,return_date,interests,num_travelers,adults,children,seniors,infants,pace[,import_source:{url,title}]},selections}`; personal fields (nationality, visas, permits, accessibility) are stripped; `404 "Shared plan not found"`.

### 2.6 Preferences & recent searches & taste (auth required)
- `GET /api/preferences` -> `{username, budget_category:"low|medium|high" (default "medium"), nationality:"", current_residence:"", residence_permits:[], existing_visas:[], interests:[], num_travelers:1, adults:1, children:0, seniors:0, infants:0, accessibility_needs:[]}` (saved rows also include `updated_at`).
- `PUT /api/preferences` body = same fields (all optional w/ defaults): `budget_category` regex `^(low|medium|high)$`; `num_travelers` 1..20; `adults/children/seniors/infants` 0..20 -> returns saved prefs. **PUT replaces all fields** (omitted ones reset to default).
- `GET /api/recent-searches` -> `[{id:uuid, search:{...RecentSearchIn}, last_used_at:ISO}]` (max 8 newest).
- `POST /api/recent-searches` body `RecentSearchIn`: `origin`(1..200 req), `destination`(1..200 req), `departure_date` req, `return_date?` (>= departure else 422), `stops:[{city(1..200),nights?(1..30)}]` (max 3), `nationality<=200`, `residence_permits|existing_visas|interests|accessibility_needs: string<=100 each, max 20`, `budget_usd?>=0`, `adults/children/seniors/infants 0..20` (adults default 1), `serendipity` 0..1 default .5 -> `{id,search,last_used_at}`. Identical searches bump to top.
- `DELETE /api/recent-searches/{id}` -> `204`; `404 "Recent search not found"`.
- `GET /api/taste-profile` -> `{signals:{<signal_type>:[{value,count}]},total_signals:int,context:string|null}`; `DELETE` -> `{"success":true,"deleted_signals":n}`.

### 2.7 Feedback / analytics (auth required)
- `POST /api/feedback` (201) `{page<=64, rating 1..5, category:"bug|feature_request|general|praise", message?<=500, metadata?:object}` -> stored feedback row (keys `id,username,page,rating,category,message,metadata,created_at` - **UNVERIFIED** exact shape).
- `POST /api/analytics/events` (204) `{events:[{feature<=64,page<=64,metadata?:object,ts?:int}]}` (<=50).

### 2.8 Admin (admin required)
- `POST /api/admin/users` (201) `{username,password(>=8),email?,is_admin=false}` -> user row without password_hash: `{id,username,email,is_admin,is_first_login,is_active,created_at,updated_at}`; `409 "Username already exists"`, `400 "Temporary password must be at least 8 characters"`.
- `GET /api/admin/users` -> user[]. `DELETE /api/admin/users/{username}` 204 (400 self, 404). `POST /api/admin/users/{username}/reactivate` -> `{"status":"reactivated"}`. `POST /api/admin/users/{username}/reset-password` `{new_password}` -> `{"status":"password_reset","username":...}`.
- `GET /api/admin/feedback?page=&category=&min_rating=` -> feedback list.

### 2.9 Notifications (auth required, no rate limit)
- `GET /api/notifications?unread_only=false&limit=20(1..100)&offset=0` -> `{items:[Notification],total?:int,unread:int,...}` (page keys from `notifications_db.list_notifications`; `total` presence **UNVERIFIED**, `unread` is certain).
- `GET /api/notifications/unread-count` -> `{"count":n}`.
- `POST /api/notifications/read` body `{ids:int[]<=500}` or `{all:true}` -> `{"updated":n,"unread":m}`; `422 "Pass ids or all=true"`.
- Notification: `{id:int, kind:string, title, body, data:object, created_at:ISO, read_at:ISO|null, emailed_at:ISO|null}` (user_id stripped). Known `kind`s: fare watches `fare_target`, `fare_drop`, `fare_low_level`, `fare_cheaper_date`, `watch_expired`, `watch_error`; price watches `<watchkind>_<name>` (e.g. `hotel_target`), plus `watch_expired`/`watch_error`. `data` includes at least `watch_id`, `watch_kind` for price watches; web deep link `"/alerts?kind=<kind>&watch=<id>"`. Remaining `data` keys **UNVERIFIED**.

### 2.10 Fare watches (auth required; only usable when `/health.fare_watch_available`)
Row (after `serialize`): DB columns minus `user_id, lease_until, last_error`: `id, plan_id, origin_code, destination_code, origin_label, destination_label, departure_date, return_date, num_travelers, cabin("economy"), flexible_days(0|3), alert_mode("any_drop"|"below_target"), target_price, email_enabled(0/1 int in SQLite - bool-ness UNVERIFIED), status("active"|"paused"|"error"|"expired"), baseline_price, last_price, lowest_price, lowest_price_date, last_notified_price, last_notified_at, baseline_price_level, own_peak_price, own_lowest_price, cheaper_notified_price, cheaper_notified_at, cheaper_peak_price, google_price_level, google_typical_low, google_typical_high, check_count, failure_count, last_checked_at, next_check_at, created_at, updated_at` plus computed `problem` (friendly string|null), `already_good` fields (from `fare_watch.already_good`, keys UNVERIFIED), `history:[{id,watch_id,checked_at,price,cheapest_price,cheapest_departure_date,cheapest_return_date,price_level}]`, `booking_url` (Google Flights).
- `GET /api/fare-watches` -> Watch[].
- `POST /api/fare-watches/match` body TripFields -> `{"watch":Watch|null}`.
- `POST /api/fare-watches` (light_ai): body `{plan_id?:int, origin?, destination?, destinations?, departure_date?, return_date?, num_travelers=1(1..20), alert_mode="any_drop|below_target", target_price?(>0,<=1e6; REQUIRED when below_target), flexible_days=0|3, email_enabled=false}`. If `plan_id` given the trip comes from the saved plan. -> Watch + `already_watching:bool`. Errors: `503` no live fares; `422` (multi-city / no airport / past or too-soon departure / return before departure / target missing / email not available "Email alerts aren't available on this server." / "Add an email address in Preferences to get email alerts."); `409` watch limit ("You already have 10 active watches — pause or remove one to watch another." - shared with price watches; default 10).
- `GET /api/fare-watches/{id}`; `PATCH` `{status?:"active|paused", alert_mode?, target_price?, flexible_days?, email_enabled?}` -> Watch (409 expired / limit); `DELETE` -> `{"deleted":true}`; 404 `"Fare watch not found"`.
- `POST /api/fare-watches/{id}/check` (light_ai) -> Watch + `check_status` + `notification|null`. Errors: `409` "We're checking this fare right now..." / expired; `429` budget exhausted with `Retry-After` = seconds to next UTC midnight; `503`.
- `GET|POST /api/fare-watches/unsubscribe?token=` return HTML (email links only).

### 2.11 Price watches (auth required; needs live prices, `serpapi_configured`)
Create body: `{kind:"hotel"|"activity"|"trip" (^[a-z_]+$, 1..20), "<kind>": {spec}, plan_id?:int, alert_mode="any_drop|below_target", target_price?(>0,<=1e6), target_currency?(1..8), email_enabled=false}`. The spec rides under a key equal to `kind` (extra keys allowed). Total spec JSON <= 8000 bytes (else `422 "That request is too large."`). Specs:
- hotel: `{name(<=200), city(<=120), check_in:"YYYY-MM-DD", check_out, adults(1..16), rooms?(1..8, default derived), property_token?, estimate_total?, plan_id?}`; stay 1..30 nights; check-in must be in the future; rooms <= adults.
- activity: `{name(<=200), city(<=100), travellers?(1..20, default 1), date?:"YYYY-MM-DD"(future), listing_url?(GetYourGuide/Viator activity page only), estimate_price?>0}`.
- trip: `{plan_id:int}` (top-level `plan_id` is passed into the spec; must be the caller's saved plan, else 404).
Watch row (serialized): DB columns minus `user_id, lease_until, last_error, match_key, reference_looks`: `id, kind, plan_id, title, subtitle, subject:{...}, currency, alert_mode, target_price, email_enabled, status, baseline_price, last_price, lowest_price, last_notified_price, last_notified_at, own_peak_price, failure_count, unavailable_count, last_observation:{status,link,...}|null, check_count, last_checked_at, next_check_at, expires_on, created_at, updated_at` + `problem`, `already_below_target:bool`, `link:string|null`, `history:[{id,watch_id,checked_at,price,breakdown,observed}]`; create responses also have `already_watching:bool`; check responses have `check_status` (`checked|unavailable|failed|errored|expired|postponed|deleted|...`) and `notification|null`.
Routes: `GET /api/price-watches?kind=`, `POST /api/price-watches/match` (body `{kind,<kind>:{spec}}` -> `{"watch":Watch|null}`), `POST /api/price-watches`, `GET /{id}`, `PATCH /{id}` `{status?,alert_mode?,target_price?,email_enabled?}`, `DELETE /{id}` -> `{"deleted":true}`, `POST /{id}/check`, plus HTML `unsubscribe`.
Errors: `503 "Price watch needs live prices, which aren't set up on this server."`; `422 "We can't watch prices of this kind yet."` (unknown kind); `409` limit; `502 "We couldn't reach live prices right now."`; `429` with `Retry-After` (seconds to next UTC day) "You've used your share of today's live price checks..." ; `404 "Price watch not found"`.
### 2.11a Grounded live calls (auth, `light_ai`; spec: web repo `live-check-near-me-spec.md`)
- `POST /api/nearby` v2: body `{lat, lng, limit?(1..10 per section, default 6), sections:true, language?}` -> `{place:{name,region,country,country_code,lat,lng,distance_km}, sections:[{id:"see"|"eat"|"shop"|"stay", title, items:[{name, summary, maps_uri, place_id, category}]}], attribution:"Google Maps", sources:[{title, uri}]}`. Without `sections` the v1 `{place, items}` shape is unchanged. Errors: 404 `detail:{code:"no_place"}`, 502 `agent_error`, 503 `ai_limit` / `ai_billing` / `grounding_unavailable`. No server cache; the app keeps the answer in ViewModel memory only.
- `POST /api/live-check`: body `{kind:"flight"|"hotel"|"activity"|"trip", watch_id}` (flight = fare watch id) -> `{kind, watch_id, checked_at, summary, quotes:[{label, amount, currency, source_index}], sources:[{title, uri}], searched_for:[string], disclaimer}`. Errors: 404 `"Watch not found"`, 409 `detail:{code:"watch_expired"}` (watch expired or its dates passed; the app shows its own copy, no Retry), 429 (string), 503 `ai_limit` / `ai_billing` / `grounding_unavailable`, 502 `live_check_failed`. Never stored; never feeds alerts or price history. "Searched for" queries link to `https://www.google.com/search?q=` (used instead of the Search Suggestions widget, per the spec).

**Special 422 bodies (JSON object, not just detail):**
```json
{"detail":"<msg>","code":"no_live_price","message":"<msg>","suggestions":[...<=3],"estimate":<number|null|object UNVERIFIED>}
{"detail":"This is priced in EUR (now €120). Enter your target in EUR.","code":"target_currency_mismatch","message":"...","currency":"EUR","price":120.0,"unit_price":<number|null>}
```
`suggestions` element shape is **UNVERIFIED** (see `price_watch.NoLivePrice`).

---------------------------------------------------------------------------
## 3. SSE: `POST /api/search`

### 3.1 Transport format
- Request: `Content-Type: application/json`, body = TravelSearchRequest; optional `Authorization`.
- Response: `200 text/event-stream`, headers `Cache-Control: no-cache`, `X-Accel-Buffering: no`. Errors before streaming (400/422/429/401) are normal JSON HTTP errors; once streaming starts there is **no HTTP error channel** - failures appear as section `data.error` or a premature close.
- Framing: each event is one line `data: <JSON>` terminated by a blank line (`\n\n`). JSON is `json.dumps` (ASCII-escaped, never contains raw newlines) so line-based parsing is safe. **Not** the full SSE spec: no `event:` or `id:` fields, so don't rely on an `EventSource` event-name API; parse every `data:` line (web worker does `line.startsWith('data: ')` then `JSON.parse(line.slice(6))`).
- Keepalives: comment lines `: keepalive\n\n` (ignore any line not starting with `data: `). Emitted roughly every 3 s while the orchestrator waits in Phase 2 (itinerary/enrichment/packing/stress). Not emitted during Phase 1's blocking waits (long silent gaps are possible: up to 240 s per agent); set a generous read timeout (e.g. 5+ min, or infinite with a client-side idle timer).
- Termination: final event `{"type":"done"}`. A stream that ends without `done` = interrupted (web: auto-retry once, then show "The connection was interrupted — some sections may be incomplete"). Cached replays also end with `done`; a cached replay contains the same events (no keepalives).
- Generic envelope: `{"type": <string>, "data": <object>, "source": "static"|"ai"}`; `agent_status` events instead carry `agent` and `status`; `done` carries nothing else. There is **no `type:"error"` event in /api/search**; errors are carried as `data:{"error":"<msg>"}` inside a section event (e.g. `"timed out"`).

### 3.2 Event types (search)
| `type` | Payload | Notes |
|---|---|---|
| `visa`,`sim`,`tips`,`getting_around`,`forex`,`emergency_card` | `data`, `source:"static"` | Phase 0 (instant), only if the static table has the entry. Web shows these as status "enhancing". |
| `confidence` | `data` (3.4.17), `source:"static"` | Travel Ease grade; only if destination in table. Not a section tile; web stores separately. |
| `agent_status` | `{"agent":"<name>","status":"searching"}` | Sent once per name in order: flights, weather, hotels, activities, places_to_see, walking_tours, events, visa, sim, tips, emergency_card, getting_around, forex, packing_list, pricing_advisor. Later `{"agent":"stress_test","status":"searching"}` when itinerary is final and `{"agent":"stress_test","status":"done"}` only when stress test errored/timed out. **The web ResultsPage ignores agent_status entirely** (it uses its own loading state); treat as optional progress hints. No "done" status for other agents (arrival of the section event itself means done). |
| `flights`,`weather`,`hotels`,`activities`,`places_to_see`,`walking_tours`,`events`,`visa`,`sim`,`tips`,`emergency_card`,`getting_around`,`forex` | `data`, `source:"ai"` | Phase 1, each as its agent finishes, in completion order (non-deterministic). Static-backed six (visa,sim,tips,getting_around,forex,emergency_card): if the AI agent errors, **no event is sent** (static data stays). Other sections can arrive with `data:{"error":"..."}`; web rule: if a `source:"ai"` event is an error and a good result already exists for that section, keep the old one. |
| (re-yield) `hotels`,`activities`,`places_to_see` | `data` with enriched links, `source:"ai"` | Second event for the same type after URL enrichment (replace the previous). The first yield has `data.verification.pending:true` (only if enrichment will do work); if enrichment fails, a re-yield with pending resolved still arrives. Other agents (flights, walking_tours...) may also be re-yielded after enrichment (every non-error agent with an `enrich` method) - **always treat repeated `type` as replace-by-type**. |
| `itinerary` | `data` (3.4.14), no `source` | Phase 2, once (AI result or template fallback). Starts after activities+hotels exist; 60 s ceiling (from phase-2 start). |
| `stress_test` | `data` (3.4.16) or `{"error":"timed out"}`, `source:"ai"` | After itinerary; 90 s ceiling. |
| `packing_list` | `data` (3.4.15), `source:"ai"` or `"static"` (template fallback) | Deferred; 120 s ceiling then template. Web marks `waiting` until activities & weather present. |
| `pricing_advisor` | `data` (3.4.18), `source:"ai"` | Only if flights had >= 3 results/prices; may never arrive. Web stores separately (`pricingData`). |
| `done` | - | Always last (unless interrupted). |

Web `AGENT_ORDER` (sections it renders): flights, weather, hotels, activities, places_to_see, walking_tours, events, visa, sim, tips, emergency_card, getting_around, forex, itinerary, stress_test, packing_list. Unknown types are ignored (`if (!AGENT_ORDER.includes(type)) return`); do the same for forward compatibility.

Section status machine used by web (reproduce on Android): initial `loading` for the 13 phase-1 sections, `waiting` for itinerary, stress_test, packing_list; event with `source:"static"` -> `enhancing`, `source:"ai"`/absent -> `done`; itinerary `loading` once activities & hotels are done/enhancing; stress_test `loading` after itinerary `done`; on stream end any non-done -> `done`; if no itinerary arrived, web builds a client-side fallback from activities+hotels.

### 3.3 Verification object (on every non-error section except `confidence`, `pricing_advisor`... exact exclusions UNVERIFIED; present when `verify_section` returns non-None)
```json
"verification": {"level":"verified|partial|unverified|conflict","label":"Verified|Partly verified|AI-generated|Check details","summary":"string","checks":[{"label":"","status":"pass|...(UNVERIFIED enum)","detail":"","url":null}],"items_verified":null,"items_total":null,"pending":false}
```
It is merged into the section object (`{...data,"verification":{...}}`), never contains an `error` key. Not used by chat.

### 3.4 Section `data` shapes
Field lists are from agent prompts (`.agents/*.md`), which constrain the LLM; the Python layer adds some fields. Treat all fields as nullable/optional and ignore unknown ones (LLM output; `BaseAgent._parse_json` has fallbacks). "Realistic example" values are from the prompt specs.

**3.4.1 flights** `{"results":[Flight], "price_insights"?:{...live}, "trip_type"?:"multi_city", "legs"?:[...]}`
`Flight`: `price_usd`:number (total), `trip_type`:"round_trip"|"one_way", `booking_url`, `source` ("google_flights" when live, "estimate" fallback, or platform), `outbound`:Leg, `return`:Leg|absent, and live-only extras `live_fare`:bool, `carbon_emissions_grams`:int|null, `often_delayed`:bool; multi-city extras `leg_index`:int(0-based), `leg_from`, `leg_to`, `leg_date`, `city`. `Leg`: `{airline,flight_number,origin,destination,departure_date,departure_time:"HH:MM",arrival_time:"HH:MM" or "15:30+1",duration_minutes:int,stops:int,layovers:[{city,airport,duration_hours:number}]}`. Sorted by price asc, 8-12 results (<=12). Multi-city: top-level `trip_type:"multi_city"`, `legs:[{leg_index,label,date,from,to,results[],error?}]`, `results` = flattened. Note: `live_fare` / `price_insights` may be stripped (`strip_live_fare`) when not trustworthy.
```json
{"results":[{"price_usd":1200.0,"trip_type":"round_trip","booking_url":"https://www.google.com/travel/flights...","source":"google_flights","live_fare":true,"outbound":{"airline":"Japan Airlines","flight_number":"JL001","origin":"JFK","destination":"NRT","departure_date":"2026-05-01","departure_time":"11:00","arrival_time":"15:30+1","duration_minutes":810,"stops":0,"layovers":[]},"return":{"...":"same"}}]}
```
**3.4.2 weather** `{"days":[{"date":"YYYY-MM-DD","city"?,"description","weather_code"(WMO),"temp_high_c","temp_low_c","precipitation_mm","wind_kmh","is_poor":bool}],"poor_weather_day_count":int,"source":"open-meteo"|"llm-estimate"}` (flat `days` even for multi-city).
**3.4.3 hotels** `{"results":[{"name","star_rating":number,"price_per_night_usd","total_price_usd","location","amenities":[str],"booking_url","review_score","source","source_snippet","link_verified":bool}]}` (8-12, star desc; `link_verified`/`booking_url` rewritten by enrich; multi-city adds `city`).
**3.4.4 activities** `{"results":[{"name","description","category"(food|history|adventure|culture|nature|shopping|nightlife|wellness|art|sport|family|general),"duration_hours","price_usd","location","source"(getyourguide|viator|klook|tripadvisor|tiqets|musement|web),"similarity_score":0..1,"rating","review_count","accessibility_features":[str],"family_friendly":bool,"age_suitability","hidden_gem":bool,"booking_url"(server-generated by enrich),"city"?(multi),"from_link"?...}]}` (15-20; link-import extras UNVERIFIED).
**3.4.5 places_to_see** `{"results":[{"name","category"(Landmark|Temple/Mosque/Church|Museum|Viewpoint|Park/Garden|Market|Palace/Castle|Natural Wonder|Historic District|Monument),"description","neighbourhood","address","rating","review_count","visit_duration_hours","best_time_to_visit","admission_fee_usd"(0 free,null unknown),"highlights":[str],"info_url"(server),"source"(server),"accessibility_features":[str],"wheelchair_accessible":bool|null,"family_friendly":bool,"hidden_gem":bool}]}` (8-12).
**3.4.6 walking_tours** `{"results":[{"id":"guruwalk-barcelona-0","name","provider","provider_key","url","image_url","description","rating","review_count","duration","price_note","city","reason","top_pick":bool}],"sources":[{"status":"error|ok|...", ...UNVERIFIED}]}`; whole-section error `{"error":"Couldn't reach the walking-tour sites right now"}`; empty `{"results":[],"sources":[...]}`.
**3.4.7 events** `{"results":[{"name","category"(festival|music|exhibition|sports|market|seasonal|holiday|other),"description","start_date","end_date","date_certainty"("confirmed_annual"|"typical_season"),"location","price"("Free"|"$30-80"|"Varies"),"impact"("highlight"|"consider"),"interest_match":[str]}]}` (4-8).
**3.4.8 visa** `{"requirement":{"visa_type"("visa-free"|"visa-on-arrival"|"e-visa"|"visa-required"),"max_stay_days","requirements":[str],"processing_time","fee_usd","official_url","confidence"("high"...),"notes"},"vaccinations":{"required":[],"recommended":[],"covid_status","notes","source_url"},"customs":{"duty_free_allowances":{alcohol,tobacco,currency,gifts},"prohibited_items":[],"declaration_required":[],"notes","source_url"}}` (static Phase-0 version contains only `requirement`; multi-city may differ - UNVERIFIED).
**3.4.9 sim** `{"plans":[{"provider","plan_name","data_gb","validity_days","price_usd","purchase_location","url","snippet","network_quality":{"speed","coverage_rating"(excellent|good|moderate|...),"coverage_description"}}]}`.
**3.4.10 tips** `{"tips":[{"title","body","category"(e.g. tourist_trap),"severity"(e.g. warning),"source_url"}]}`.
**3.4.11 emergency_card** `{"emergency_numbers":{"police","ambulance","fire","tourist_police"},"embassy":{"name","address","phone","emergency_after_hours","website","hours","note"},"hospitals":[{"name","phone","address","notes"}],"local_phrases":[{"english","local","phonetic"}],"local_laws":[{"law","detail","severity"("critical"|"warning")}],"home_country_note":null|string}`. Multi-city: `{"cities":[{"city":"Berlin, Germany", ...same keys}]}`.
**3.4.12 getting_around** `{"options":[{"name","type"(metro|...),"scope"("intra_city"|"inter_city"),"description","coverage","price_info","operating_hours","tips","booking_url","tourist_pass"}]}`.
**3.4.13 forex** `{"local_currency":{"name","code","symbol"},"exchange_rates":[{"from_currency","to_currency","rate":number,"description","trend"}],"exchange_locations":[{"type","name","description","rating","fees","tip"}],"card_acceptance":{visa_mastercard,amex,contactless,digital_wallets,surcharges},"cash_advice":{cash_dependency("high|medium|low"),recommendation,denominations,bring_usd_eur},"atm_info":{availability,networks,withdrawal_limit,fees,best_option},"tipping":{"expected":bool,"description"},"money_tips":[{"title","body"}],"source_urls":[str]}`.
**3.4.14 itinerary** `{"days":[{"day_number":int,"date":"YYYY-MM-DD","theme","city","slots":[{"time_of_day":"morning|afternoon|evening","activity","location","city","lat","lng","duration_hours","notes","estimated_cost_usd", + optional server extras: "from_link","link_quote","key","start_time","end_time"... (UNVERIFIED; from_link/link_coverage/link_extras per CLAUDE.md)}],"daily_estimated_cost_usd"}],"total_estimated_cost_usd":number}`. Slot identity key used by web: `"<day_number>-<time_of_day>"` (e.g. `"1-morning"`). Template fallback has the same shape. **Times of day are derived client-side** (`utils/schedule.js`), not sent.
**3.4.15 packing_list** `{"categories":[{"name","icon"(emoji),"weather_note"?,"items":[{"item","essential":bool,"note":str|null}]}],"luggage_note","total_items":int}`.
**3.4.16 stress_test** `{"overall":"green|amber|red","summary","score":0-100,"findings":[{"severity":"high|...","category":"timing|...","day_number":int,"issue","suggestion"}]}` or `{"error":"timed out"}`.
**3.4.17 confidence** `{"total":int,"grade":"green|amber|red","destination","sub_scores":{"visa_ease|safety|english_friendliness|cost_vs_budget|tourist_infrastructure":{"score":int,"max":20,"label","note"}}}` (green >= 71, amber >= 41).
**3.4.18 pricing_advisor** `{"route":"NYC → Tokyo","current_avg_price_usd","price_status","price_status_label","recommendation"("wait"|...),"recommendation_detail","optimal_booking_window","trend_data":[{"days_before","relative_price"}],"confidence","disclaimer"}`.

---------------------------------------------------------------------------
## 4. SSE: `POST /api/chat`

### 4.1 Request (`api/routes/chat.py`) - auth **required**, bucket `chat`
```json
{"messages":[{"role":"user|assistant","content":"..."}],
 "selections":{},          // My Plan selections object (5.x); default {}
 "search_results":{},      // latest sections object the chat received ({flights:{...},hotels:{...}}); default {}
 "session_context":{}}     // echo of last session_context_update.context; default {}
```
`messages` is required (no server-side length cap seen; web resends the full history, converting planning-only turns to text; empty `content` is rejected by the model, so never send empty strings). `role` is a plain string (not validated).
`session_context` keys written by server: `destination, destinations, origin, departure_date, return_date, budget_usd, num_travelers, interests, nationality, topics_discussed`, and transient `awaiting:"origin"`. **Client must round-trip it** (replace with each `session_context_update`).

Response headers like search. Same framing (`data: {json}\n\n`, **no `: keepalive` comments are emitted by chat** - verified by grep; long planning phases may be silent up to 60 s / 120 s multi-city), terminates with `done` or `planning_done`.

### 4.2 Event types (chat). All have a top-level `type`; payload keys are siblings (no `data` envelope except where noted)
| `type` | Fields | Meaning |
|---|---|---|
| `delta` | `text` | Append to the assistant message (markdown). Also used for refusals/limit messages. |
| `suggestions` | `chips:string[]` (<=4) | Tappable follow-up chips. |
| `session_context_update` | `context:object` | Store and resend as `session_context`. |
| `plan_action` | `action:"set|add|remove|clear"`, `field:"flight|hotel|sim|activities|tips|getting_around|itinerary_slots|all"`, `data:object|null` | Mutate My Plan. Web `applyPlanAction`: clear+all -> EMPTY_SELECTIONS; clear on array fields (`activities`,`tips`,`getting_around`,`itinerary_slots`) -> `[]`, else `null`; `set` -> `selections[field]=data`; `add` -> append to array deduped by id key (`title` for tips, `key` for itinerary_slots, else `name`); `remove` -> filter by that key. |
| `planning_start` | `destination` | A plan/specialist run began. |
| `trip_map` | `origin, origin_lat, origin_lng, cities:[{city,lat,lng}], departure_date, return_date, num_travelers` | lat/lng may be null. |
| `itinerary_generating` | - | Spinner for itinerary. |
| `comprehensive_itinerary` | `data`: chat-itinerary object (4.3) or `{"error":"..."}` | The planning result. |
| `agent_status` | `agent`, `status:"loading"` | Specialist fallback only. |
| `section_result` | `section`, `data`, `source:"ai"|"static"` | Specialist fallback/refinement only; `section` names as in 3.2; shapes as 3.4; `data` may be `{"error":..}` (keep prior good data). **No verification key** in chat. |
| `planning_done` | - | End of planning stream (web also treats as completion, stops streaming spinner). |
| `import_link` | `url`, `href` | User pasted a trip link: show "open Plan from a link" (href is a web route `/?import=<encoded>`; Android should route to its import screen with `url`). Followed by `done`. |
| `error` | `text` | Stream failed (also emitted by route-level catch after a `delta` apology, then `done`). Web shows generic apology if no content. |
| `done` | - | End of a normal chat reply. |
| `message` / `result` | `text` | Legacy: web uses `text` only if no delta received. Not seen being emitted by the current backend (UNVERIFIED). |
| `plan_clear`, `plan_ready`, `search_context` | (`params`) | Handled by web but **not emitted by the current backend** (grep of `chat_agent.py`); ignore safely. |

Typical sequences:
- Q&A: `delta`* -> (`suggestions`) -> (`session_context_update`) -> `done`.
- Plan command: `plan_action`* -> `delta` -> `done`.
- Full plan: `planning_start` -> `trip_map` -> `itinerary_generating` -> `comprehensive_itinerary` -> (`delta` "Heads up" warnings) -> `session_context_update` -> `suggestions` -> `planning_done` (**no `done`**; treat both `done` and `planning_done` as terminal).
- Specialist fallback: `planning_start` -> `agent_status`(loading)* -> `section_result`* -> `session_context_update` -> `suggestions` -> `planning_done`.
- Clarify missing info: `delta` (question) -> `suggestions` -> `session_context_update` (with `awaiting:"origin"`) -> `done`.
- Over the full-plan rate limit: `delta` (friendly text with wait time) -> `done` (HTTP 200).
Streams whose reader ends without `done`/`planning_done`: web treats `__stream_end` as completion (no interrupt retry for chat).

### 4.3 `comprehensive_itinerary.data` (from `.agents/chat-itinerary.md`)
```json
{"trip_summary":{"origin","origin_lat","origin_lng","cities":[{"name","lat","lng","nights"}],"departure_date","return_date","total_nights","total_cost_usd","travelers"},
 "intercity_travel":[{"from","to","options":[{"mode","duration","price_usd","tip"}]}],
 "days":[{"day_number","date","city","country","theme","is_travel_day":false,
   "hotel":{"name","neighbourhood","stars","price_per_night_usd","tier":"budget|...","highlight"},
   "morning|afternoon|evening":{"activity","place","lat","lng","duration_hours","cost_usd","tip"},
   "places_to_see":[{"name","category","lat","lng","entry_usd","why"}],
   "dining":[{"name","cuisine","price_range":"$","neighbourhood"}],
   "daily_cost_usd"}]}
```
Note: **different schema from the search `itinerary`** (slots[] vs morning/afternoon/evening objects).

---------------------------------------------------------------------------
## 5. My Plan `selections` (what web writes; server stores opaque JSON)
Server treats `selections` and `search_data` as arbitrary JSON objects; only `taste_db.record_plan_signals` reads them. Web initial/empty value (`EMPTY_SELECTIONS`, `utils/planHelpers.js`):
```json
{"flight":null,"flights":[],"hotel":null,"activities":[],"places_to_see":[],"walking_tours":[],
 "sim":null,"tips":[],"getting_around":[],"events":[],
 "itinerary_notes":{},"itinerary_edits":{},"itinerary_slots":[],"itinerary_layout":null,"packing_list":null}
```
Semantics (each item is the full section result object the user picked, link-evidence keys stripped by `stripLinkEvidence` before save):
- `flight`: one Flight (3.4.1); `flights`: array (multi-city: one per `leg_index`; identity via `sameFlight`).
- `hotel`: one hotel result. `sim`: one sim plan.
- `activities`, `getting_around`, `events`, `places_to_see`: arrays; dedupe key `name`. `tips`: dedupe by `title`. `walking_tours`: dedupe by `url`.
- `itinerary_slots`: array of slot objects each with a `key` (`"<day>-<tod>"`), `day_number`, `date`, plus slot fields.
- `itinerary_notes`: `{ "<slotKey>": "text" }`; `itinerary_edits`: `{ "<slotKey>": {activity?,cost?,...(UNVERIFIED which fields: `activity`, `cost` seen)} }`.
- `itinerary_layout`: `null` or `{"fingerprint":"<fnv1a base36>","positions":{"<originalKey>":"<day>-<tod>"|null}}` (null = removed). The fingerprint is a hash of the itinerary lines `"<day>|<tod>|<activity>"` joined by `\n` (see `utils/itineraryLayout.js`, FNV-1a 32-bit: offset 0x811c9dc5, prime 0x01000193, base-36); if it does not match the current itinerary the layout is ignored.
- `packing_list`: `null` or `{ "checked_items": ... }` (ResultsPage line 2228 reads `selections.packing_list.checked_items`; element type UNVERIFIED).
- On save, ResultsPage additionally adds `selections.itinerary = {days:[...], total_estimated_cost_usd}` (snapshot of the live itinerary) so a saved plan is self-contained.
Save flow: `POST /api/plans {name, search_data: <the TravelSearchRequest used, incl. destinations etc.>, selections}`; later `PUT /api/plans/{id} {name, selections}`. Default plan name in web: "My Trip Plan" (`generatePlanName` in planHelpers exists). The chat page uses the same `EMPTY_SELECTIONS` and sends `selections` with each chat request. "Add whole best-value package" is client-side only.

---------------------------------------------------------------------------
## 6. How the web app calls things (confirmation)
- axios base `/api`, `Content-Type: application/json`; auth via `headers:{Authorization:'Bearer '+token}` per call (no interceptor).
- SSE: `fetch(POST)` inside a Web Worker, manual `ReadableStream` reader + `TextDecoder`, split on `\n`, buffer last partial line. Search: `__interrupted` (no `done`) -> retry once. Non-2xx before streaming -> `responseErrorMessage` (uses string `detail`).
- Plans/share use raw `fetch('/api/plans...')` with Bearer header.
- Non-streaming search helpers (`searchFlightsFiltered` etc.) use a reduced payload (see 1).
- `getCapabilities()` reads `/health` once per page load.
- Recent searches are saved on submit; `GET/POST/DELETE /recent-searches`.

---------------------------------------------------------------------------
## 7. UNVERIFIED / not read
- Exact keys of `/api/search/sync`, `/api/discover` result, `/api/compare/destination` summary (`services/compare.py`), `/api/layover` result, `ResolvedPlace`.
- Notification `data` payload beyond `watch_id`/`watch_kind`; `already_good` keys; `NoLivePrice.suggestions`/`estimate` shape.
- Exact 413 body; share-page web URL path; `verification.checks[].status` enum; extra itinerary slot keys added server-side (`start_time`, `end_time`, `from_link`, `link_extras`, `link_coverage`).
- `email_enabled` JSON type on watches (sqlite int vs bool) - check at runtime.
- Nothing was executed; field lists for AI sections come from agent prompts and may vary at runtime (LLM JSON, three-strategy parser). Use tolerant decoding (`ignoreUnknownKeys`, nullable fields, `coerceInputValues`; some numeric fields can arrive as strings or "varies" - e.g. `_amount()` in price sources handles "AI prices may be strings").
