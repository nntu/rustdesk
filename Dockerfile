# syntax=docker/dockerfile:1

# ==============================================================================
# STAGE 1: Build Vue 3 Web Admin Frontend
# ==============================================================================
FROM node:24-alpine AS frontend-builder
WORKDIR /frontend

# Install standalone pnpm v12 (no corepack)
RUN npm install -g pnpm@12

COPY ./rustdesk-api-web/package.json ./rustdesk-api-web/pnpm-lock.yaml ./rustdesk-api-web/pnpm-workspace.yaml ./rustdesk-api-web/.npmrc ./
RUN --mount=type=cache,id=pnpm,target=/root/.local/share/pnpm/store \
    pnpm install --ignore-scripts

COPY ./rustdesk-api-web/ ./
RUN pnpm run build

# ==============================================================================
# STAGE 2: Build Go Backend
# ==============================================================================
FROM golang:1.26.4-alpine AS backend-builder
WORKDIR /app

RUN apk add --no-cache gcc musl-dev git

# Pin swag to match go.mod (avoid @latest invalidating cache on every build)
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go install github.com/swaggo/swag/cmd/swag@v1.16.6

COPY ./rustdesk-api/go.mod ./rustdesk-api/go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

COPY ./rustdesk-api/ ./

RUN swag init -g cmd/apimain.go --output docs/api --instanceName api --exclude http/controller/admin && \
    swag init -g cmd/apimain.go --output docs/admin --instanceName admin --exclude http/controller/api

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=1 GOOS=linux go build -ldflags "-s -w -extldflags '-static'" -o release/apimain cmd/apimain.go

# ==============================================================================
# STAGE 3: Final Production Image
# ==============================================================================
FROM alpine:3.21
WORKDIR /app

RUN apk add --no-cache tzdata ca-certificates sqlite

COPY --from=backend-builder /app/release/apimain /app/apimain
COPY --from=backend-builder /app/conf /app/conf/
COPY --from=backend-builder /app/resources /app/resources/
COPY --from=backend-builder /app/docs /app/docs/
COPY --from=frontend-builder /frontend/dist/ /app/resources/admin/

RUN mkdir -p /app/data /app/runtime

VOLUME /app/data
EXPOSE 21114

CMD ["./apimain"]
