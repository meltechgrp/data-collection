#!/bin/sh
set -e

# Apply any pending migrations before the server accepts traffic. This is
# idempotent, so it is safe on every container start, including redeploys
# against an existing volume.
#
# Uses scripts/migrate.cjs rather than the Prisma CLI: the CLI needs ~170MB of
# extra dependencies (Studio, pglite, effect) that a runtime image should not
# carry. The script writes the same _prisma_migrations table.
echo "==> Applying database migrations..."
node ./scripts/migrate.cjs

echo "==> Starting Next.js..."
exec "$@"
