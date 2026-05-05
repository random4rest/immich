# Architecture (fork view)

A fast tour of the Immich codebase from this fork's perspective. For the full upstream view, read [`docs/docs/developer/architecture.mdx`](../docs/docs/developer/architecture.mdx) — we don't duplicate it here.

## High-level

```mermaid
graph LR
  subgraph clients [Clients]
    web[Web SvelteKit]
    mobile[Mobile Flutter]
    cli[CLI npm]
    api[3rd-party API]
  end
  subgraph server [Backend]
    api2[immich-server NestJS]
    micro[microservices NestJS]
    ml[immich-machine-learning Python]
  end
  subgraph stores [Data]
    pg[("Postgres + pgvector")]
    redis[("Redis / Valkey")]
    fs[("Filesystem UPLOAD_LOCATION")]
  end
  web --> api2
  mobile --> api2
  cli --> api2
  api --> api2
  api2 --> pg
  api2 --> redis
  api2 --> fs
  api2 --> ml
  micro --> pg
  micro --> redis
  micro --> fs
  micro --> ml
```

## Key directories

| Path | What |
|---|---|
| `server/src/controllers/` | HTTP route handlers. Thin — delegate to services. |
| `server/src/services/` | Business logic. The bulk of the backend. |
| `server/src/repositories/` | DB and external-system access. Used by services. Hexagonal-architecture-style boundary. |
| `server/src/schema/` | Kysely table definitions and migrations. **Migrations are the highest-risk surface for upstream merges.** |
| `server/src/dtos/` | Zod schemas. These auto-generate the OpenAPI spec. |
| `web/src/routes/` | SvelteKit route components. |
| `web/src/lib/` | Shared web components, stores, utilities. |
| `mobile/lib/` | Flutter app. |
| `machine-learning/immich_ml/` | Python ML service (CLIP, face recognition, etc.). |
| `cli/` | npm package for `immich` CLI. |
| `e2e/` | Playwright + API integration tests. |
| `docker/` | Compose files. `docker-compose.dev.yml` for development; the prod compose lives in the sibling `immich-app/` repo. |
| `open-api/` | Generated API clients consumed by web/mobile/cli. Re-generate with `make open-api`. |
| `fork/` | This fork's own docs and metadata. |

## Request flow

```mermaid
sequenceDiagram
  participant C as Client
  participant Ctrl as Controller
  participant Svc as Service
  participant Repo as Repository
  participant DB as Postgres
  C->>Ctrl: HTTP POST /api/albums
  Ctrl->>Ctrl: validate DTO
  Ctrl->>Svc: createAlbum(dto)
  Svc->>Svc: business rules (perms, defaults)
  Svc->>Repo: insert(...)
  Repo->>DB: SQL via Kysely
  DB-->>Repo: row
  Repo-->>Svc: entity
  Svc-->>Ctrl: response DTO
  Ctrl-->>C: 201 Created
```

When you change a route, you usually touch a controller + service + repository in lockstep.

## Migrations

Migrations live in `server/src/schema/migrations/`. Each is a Kysely script with `up()` (and sometimes `down()`). The server runs all pending migrations on boot.

**This is the riskiest surface for fork merges.** Upstream sometimes drops or rewrites tables in ways that aren't reversible. The sync ritual ([upstream-sync.md](./upstream-sync.md)) includes a pre-flight migration dry-run against a copy of the prod DB — always run it before deploying a sync.

## Build outputs

The server is compiled with NestJS CLI. Its output lives in `server/dist/`. **Never trust `dist/` across branch switches** — see [agents.md §9.2](./agents.md#92-the-stale-dist-migrations-footgun). When in doubt, `rm -rf server/dist`.

## Dev vs prod runtime

```mermaid
graph TB
  subgraph host [Windows host - Docker Desktop auto-starts on login]
    subgraph prodStack [immich - prod, restart: always]
      pSrv[immich_server :2283]
      pDb[("immich_pgdata vol :5432")]
      pMl[immich_ml cuda]
    end
    subgraph devStack [immich-dev - manual start, shifted ports]
      dSrv[immich_server :3283]
      dWeb[immich_web :3001]
      dDb[("dev pg :5433 - bind mount")]
    end
  end
  ts[Tailscale clients] --> pSrv
  br[Local browser] --> dWeb
```

Both stacks coexist on the same Docker Desktop. They have separate Docker project names (`immich` vs `immich-dev`), separate volumes, separate networks, separate host ports.
