# Goat (Козёл)

Online multiplayer implementation of the Russian card game **Козёл** for Android and iOS
(web later). Authoritative Colyseus (TypeScript) server, Flutter client.

- Game rules: [`docs/RULES.md`](docs/RULES.md) (normative)
- Design documents: [`docs/design/`](docs/design/) — read together with
  [`docs/design/CORRECTIONS.md`](docs/design/CORRECTIONS.md), which supersedes them where they conflict.

## Layout

```
packages/shared    @goat/shared — card encoding, enums, protocol contract (single source of truth)
packages/engine    @goat/engine — pure deterministic rules engine (no I/O, no Colyseus)
packages/server    @goat/server — Colyseus app: rooms, auth, matchmaking, meta
app/               Flutter client
docker/            dev compose (Postgres + Redis), production Dockerfile
```

## Development

```bash
npm install                 # workspace install
npm test                    # engine + shared + server tests
npm run simulate -- --deals 10000   # engine fuzz simulator
docker compose -f docker/compose.dev.yml up -d   # Postgres + Redis
npm run dev                 # Colyseus server with hot reload

cd app && flutter run       # client (point it at ws://localhost:2568)
```
