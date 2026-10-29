# Production image; build with the repo root as context (see docker/Makefile).
FROM perl:slim AS build

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential libgd-dev && \
    rm -rf /var/lib/apt/lists/* && \
    cpanm --notest Carton

WORKDIR /app
COPY cpanfile /app/
RUN --mount=type=cache,target=/root/.cpanm \
    carton install --deployment 2>/dev/null || carton install

FROM perl:slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends libgd3 locales && \
    echo en_US.UTF-8 >>/etc/locale.gen && \
    locale-gen && \
    rm -rf /var/lib/apt/lists/* && \
    useradd --system --create-home --shell /usr/sbin/nologin sonos

ENV LANG=en_US.UTF-8 \
    PERL5LIB=/app/local/lib/perl5:/app/lib \
    PATH=/app/local/bin:$PATH

WORKDIR /app
COPY --from=build /app/local /app/local
COPY lib /app/lib
COPY html /app/html
COPY scripts /app/scripts
COPY cpanfile /app/

RUN chown -R sonos:sonos /app
USER sonos

# Sonos discovery uses SSDP multicast, so run with --network host.
EXPOSE 9999

CMD ["perl", "scripts/sonod"]
