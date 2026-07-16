# Production image for @goat/server
FROM node:22-alpine AS build
WORKDIR /repo
COPY package.json package-lock.json tsconfig.base.json ./
COPY packages/shared/package.json packages/shared/
COPY packages/engine/package.json packages/engine/
COPY packages/server/package.json packages/server/
RUN npm ci --workspaces --include-workspace-root
COPY packages ./packages
RUN npx tsc -b packages/shared packages/engine packages/server

FROM node:22-alpine
ENV NODE_ENV=production
WORKDIR /repo
COPY package.json package-lock.json ./
COPY packages/shared/package.json packages/shared/
COPY packages/engine/package.json packages/engine/
COPY packages/server/package.json packages/server/
RUN npm ci --workspaces --include-workspace-root --omit=dev && npm cache clean --force
COPY --from=build /repo/packages/shared/dist packages/shared/dist
COPY --from=build /repo/packages/engine/dist packages/engine/dist
COPY --from=build /repo/packages/server/dist packages/server/dist
USER node
EXPOSE 2568
HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://localhost:2568/health || exit 1
CMD ["node", "packages/server/dist/index.js"]
