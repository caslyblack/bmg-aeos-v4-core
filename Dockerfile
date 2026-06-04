# Multi-stage build for B.M.G. AEOS v4 Core
FROM alpine:3.18 as builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    git \
    curl

# Copy application files
COPY . .

# Build application
RUN echo "Build stage - add your build commands here"

# Production stage
FROM alpine:3.18

WORKDIR /app

# Install runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    curl \
    tini

# Security: Create non-root user
RUN addgroup -g 1000 aeos && \
    adduser -D -u 1000 -G aeos aeos

# Copy built application from builder
COPY --from=builder /app /app
RUN chown -R aeos:aeos /app

USER aeos

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

EXPOSE 8080

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["./start.sh"]
