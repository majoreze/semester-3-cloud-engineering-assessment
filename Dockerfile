# Stage 1: Compile the Go application
FROM golang:1.25.1-alpine AS builder

WORKDIR /src

# Copy dependency definitions first for better build caching
COPY Server/MuchToDo/go.mod ./
COPY Server/MuchToDo/go.sum ./

RUN go mod download

# Copy the application source code
COPY Server/MuchToDo/ ./

# Compile a Linux executable
RUN CGO_ENABLED=0 GOOS=linux go build \
    -trimpath \
    -ldflags="-s -w" \
    -o /out/muchtodo \
    ./cmd/api

# Stage 2: Run the compiled application
FROM alpine:3.22

RUN apk add --no-cache ca-certificates wget \
    && addgroup -S app \
    && adduser -S -G app app

WORKDIR /app

COPY --from=builder --chown=app:app /out/muchtodo ./muchtodo

USER app

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1:8080/health || exit 1

ENTRYPOINT ["./muchtodo"]
