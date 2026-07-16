# Deploying the Goat server

## Prerequisites
- A VPS (2 vCPU / 2 GB is plenty for hundreds of concurrent rooms) with Docker installed.
  Pick a region close to the player base (Frankfurt / Warsaw / Almaty for a
  Russian-speaking audience) — one region is correct for v1.
- A domain (e.g. `play.example.com`) with an A record pointing at the VPS.

## Steps

```bash
git clone <repo> goat && cd goat
cat > docker/.env <<EOF
DOMAIN=play.example.com
JWT_SECRET=$(openssl rand -hex 32)
PG_PASSWORD=$(openssl rand -hex 16)
EOF
docker compose -f docker/compose.prod.yml --env-file docker/.env up -d --build
curl https://play.example.com/health   # → {"ok":true}
```

Caddy obtains and renews TLS automatically; WebSocket upgrade passes through.
The Flutter app then needs `--dart-define=GOAT_SERVER=https://play.example.com`
(the transport turns `https` into `wss`).

## Persistence

`DATABASE_URL` is set by compose → stats and achievements live in Postgres
(`player_stats`, `achievements`; schema auto-migrates on boot). Without the
variable the server falls back to an in-memory store (dev mode).

## Deploys mid-game

`docker compose up -d --build` restarts the server; running games are lost
(process-local rooms — accepted for v1). Deploy at low-traffic hours. The
graceful-drain path (stop accepting rooms, let games finish) is a follow-up.

## Monitoring

- `GET /health` — wire it to uptime monitoring.
- `docker logs goat-server-1` — Colyseus logs; secret state is never logged.
