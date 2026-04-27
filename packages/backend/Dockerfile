# ── Build stage ─────────────────────────────────────────────────────────────
FROM node:22-alpine AS builder
WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY tsconfig.json drizzle.config.ts ./
COPY src/ ./src/
COPY drizzle/ ./drizzle/
RUN npm run build && npm prune --production

# ── Runtime stage ────────────────────────────────────────────────────────────
FROM node:22-alpine AS runner

RUN addgroup --system --gid 1001 nodejs \
 && adduser  --system --uid 1001 fastify

WORKDIR /app

COPY --from=builder --chown=fastify:nodejs /app/dist         ./dist
COPY --from=builder --chown=fastify:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=fastify:nodejs /app/assets       ./assets
COPY --from=builder --chown=fastify:nodejs /app/package.json ./package.json

USER fastify

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD wget -qO- http://localhost:3000/health 2>/dev/null | grep -q '"status":"ok"' || exit 1

CMD ["node", "dist/index.js"]