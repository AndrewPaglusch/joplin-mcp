# syntax=docker/dockerfile:1

FROM node:22-bookworm AS builder

ARG JOPLIN_TAG_FILTER=v3.*

ENV HUSKY=0 \
    DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        git python3 make g++ pkg-config libsecret-1-dev ca-certificates rsync \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /joplin
RUN git clone --filter=blob:none https://github.com/laurent22/joplin.git . \
    && REF="$(git tag -l "$JOPLIN_TAG_FILTER" --sort=-v:refname | head -1)" \
    && echo "Building Joplin @ ${REF}" \
    && git checkout --detach "${REF}"

RUN corepack enable \
    && yarn install --inline-builds

RUN yarn workspace joplin build

# --------------------------------------------------------------------------------

FROM node:22-bookworm-slim AS runtime

ENV DEBIAN_FRONTEND=noninteractive \
    JOPLIN_PROFILE=/profile

RUN apt-get update && apt-get install -y --no-install-recommends \
        nginx-light gettext-base jq tini libsecret-1-0 ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/nginx/sites-enabled/default

COPY --from=builder /joplin /joplin

COPY entrypoint.sh /entrypoint.sh
COPY nginx.conf.template /etc/nginx/templates/joplin-mcp.conf.template
RUN chmod +x /entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
