# ── Build stage ─────────────────────────────────────────────────────────────
FROM node:22-alpine AS builder
WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY tsconfig.json drizzle.config.ts ./
COPY src/ ./src/
COPY drizzle/ ./drizzle/
COPY assets/ ./assets/
# Type-check only; allowImportingTsExtensions requires noEmit:true in tsconfig.json
RUN npm run build

# ── Runtime stage ────────────────────────────────────────────────────────────
# tsx is the runtime — project uses .ts import extensions so tsc cannot emit
FROM node:22-alpine AS runner

RUN addgroup --system --gid 1001 nodejs \
 && adduser  --system --uid 1001 fastify

WORKDIR /app

COPY --from=builder --chown=fastify:nodejs /app/node_modules  ./node_modules
COPY --from=builder --chown=fastify:nodejs /app/src           ./src
COPY --from=builder --chown=fastify:nodejs /app/assets        ./assets
COPY --from=builder --chown=fastify:nodejs /app/package.json  ./package.json
COPY --from=builder --chown=fastify:nodejs /app/tsconfig.json ./tsconfig.json

USER fastify

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD wget -qO- http://localhost:3000/health 2>/dev/null | grep -q '"status":"ok"' || exit 1

CMD ["node_modules/.bin/tsx", "src/index.ts"]
