# syntax=docker/dockerfile:1

# ---- Dependencies ----------------------------------------------------------
FROM node:22-bookworm-slim AS deps
WORKDIR /app

# better-sqlite3 may need to compile from source if no prebuilt binary matches.
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 make g++ openssl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json ./
# `npm ci` installs exactly what the lockfile pins, and runs the
# better-sqlite3 build script so the native binding is compiled for Linux.
RUN npm ci --no-audit --no-fund

# ---- Builder ---------------------------------------------------------------
FROM node:22-bookworm-slim AS builder
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends openssl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# `npm run build` runs `prisma generate` first, emitting the client into
# src/generated/prisma before Next.js compiles.
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

# ---- Runner ----------------------------------------------------------------
FROM node:22-bookworm-slim AS runner
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends openssl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000
ENV HOSTNAME=0.0.0.0
# Anchors the relative SQLite path regardless of the server's CWD.
ENV APP_ROOT=/app

RUN groupadd --system --gid 1001 nodejs \
    && useradd --system --uid 1001 --gid nodejs nextjs

# Standalone output includes a minimal server plus only the traced dependencies.
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public

# The standalone trace already includes the Prisma runtime client and the
# compiled better-sqlite3 binding, so only the migration SQL and the small
# script that applies it are needed here. The Prisma CLI is deliberately not
# copied: it drags in Studio, pglite and effect (~170MB) that never run.
COPY --from=builder /app/prisma/migrations ./prisma/migrations
COPY --from=builder /app/scripts ./scripts

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# The SQLite file lives here and is backed by a named volume.
RUN mkdir -p /app/data && chown -R nextjs:nodejs /app/data

USER nextjs
EXPOSE 3000

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["node", "server.js"]
