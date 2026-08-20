# Build stage: compile TypeScript with dev dependencies present.
FROM node:22-alpine AS build

WORKDIR /app
COPY package.json package-lock.json tsconfig.json ./
RUN npm ci
COPY src ./src
RUN npm run build

# Runtime stage: production dependencies + compiled JS only.
FROM node:22-alpine

WORKDIR /app
ENV NODE_ENV=production

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY --from=build /app/dist ./dist

USER node
EXPOSE 3000
CMD ["node", "dist/server.js"]
