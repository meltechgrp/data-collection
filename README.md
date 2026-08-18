# Business Registry

A two-page data collection app built with Next.js 16, Prisma 7 and SQLite.

- **`/`** — registration form (full name, business name, role, phone, email,
  business type, location, RIN/TIN).
- **`/records`** — table of every submission, newest first.

Both pages link to each other from the header.

## Tech stack

| Concern  | Choice                                        |
| -------- | --------------------------------------------- |
| Framework| Next.js 16 (App Router, Server Actions)       |
| Styling  | Tailwind CSS v4                                |
| Database | SQLite via Prisma 7 + `better-sqlite3` adapter |
| Hosting  | Docker / Coolify                               |

## Local development

```bash
bun install
cp .env.example .env      # DATABASE_URL="file:./data/dev.db"
bun run db:migrate        # create data/dev.db and apply migrations
bun run dev
```

Open http://localhost:3000.

> **Note:** `better-sqlite3` is a native module. Its build script must be
> trusted once (`bun pm trust better-sqlite3`); it is already listed under
> `trustedDependencies` in `package.json`. The Next.js server runs on Node,
> where the compiled binding resolves correctly.

### Useful scripts

| Script                | Purpose                                     |
| --------------------- | ------------------------------------------- |
| `bun run dev`         | Start the dev server                        |
| `bun run build`       | Generate the Prisma client, then build      |
| `bun run db:migrate`  | Create and apply a migration (development)  |
| `bun run db:deploy`   | Apply pending migrations via the Prisma CLI |
| `bun run db:migrate:run` | Apply migrations without the CLI (used in Docker) |
| `bun run db:studio`   | Browse the data in Prisma Studio            |

## Data model

`prisma/schema.prisma` defines a single `Submission` model. The SQLite file
lives in `data/`, which is mounted as a volume in Docker so records survive
redeploys.

## Deploying with Docker

```bash
docker compose up --build
```

The container applies migrations on every start via `docker-entrypoint.sh`, so
a fresh volume initialises itself and redeploys stay in sync.

Migrations in the container are applied by `scripts/migrate.cjs` rather than the
Prisma CLI. The CLI pulls in Studio, pglite and `effect` (~170MB) that a running
container never uses, so it is left out of the runtime image. The script reads
the same `prisma/migrations` directory and writes the same `_prisma_migrations`
table, so `prisma migrate status` and local `prisma migrate dev` stay in sync.

## Deploying on Coolify

1. **Create the resource** — in your Coolify project choose
   **+ New Resource → Docker Compose**, and point it at this Git repository.
   Coolify reads `docker-compose.yaml` from the repo root.

2. **Set the environment variables** (Environment Variables tab):

   | Variable              | Value                     |
   | --------------------- | ------------------------- |
   | `DATABASE_URL`        | `file:./data/dev.db`      |
   | `APP_ROOT`            | `/app`                    |
   | `NEXT_PUBLIC_APP_URL` | your public URL           |

3. **Confirm the persistent volume.** The compose file declares a named `data`
   volume mounted at `/app/data`. Keep it — deleting it deletes every
   submission.

4. **Set the port and domain.** The app listens on **3000**. Set that as the
   "Ports Exposes" value in Coolify, add your domain, and Coolify's proxy
   handles HTTPS.

   The compose file deliberately has **no `ports:` mapping** — Coolify reaches
   the container through its own proxy network. Publishing a host port causes
   `Bind for 0.0.0.0:3000 failed: port is already allocated` when anything else
   on the server already uses that port.

5. **Health check.** `GET /api/health` returns `{"status":"ok"}` once the app
   and database are reachable; the compose file already wires it up.

6. **Deploy.** Coolify builds the image and starts the container. Migrations
   run automatically before the server accepts traffic.

### Backing up

The whole database is one file. To copy it off the server:

```bash
docker compose cp app:/app/data/dev.db ./backup.db
```
