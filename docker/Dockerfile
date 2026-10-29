# Production image; build with perl/ as the context.
FROM perl:5.40 AS builder

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential libgd-dev libxml2-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY cpanfile ./
RUN --mount=type=cache,target=/root/.cpanm \
    cpanm --notest --local-lib=/opt/sonos \
        https://github.com/tvandera/perlupnp/archive/refs/tags/v0.5.tar.gz && \
    cpanm --notest --local-lib=/opt/sonos --installdeps /src

COPY . .
RUN PERL5LIB=/opt/sonos/lib/perl5 perl Makefile.PL INSTALL_BASE=/opt/sonos && \
    make install

FROM perl:5.40-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends libgd3 libxml2 locales shared-mime-info && \
    echo 'en_US.UTF-8 UTF-8' >>/etc/locale.gen && \
    locale-gen && \
    rm -rf /var/lib/apt/lists/* && \
    useradd --system --create-home --shell /usr/sbin/nologin sonos

ENV LANG=en_US.UTF-8 \
    PERL5LIB=/opt/sonos/lib/perl5 \
    PATH=/opt/sonos/bin:$PATH

WORKDIR /opt/sonos
COPY --from=builder /opt/sonos /opt/sonos

RUN chown -R sonos:sonos /opt/sonos
USER sonos

# Sonos discovery uses SSDP multicast, so run with --network host.
EXPOSE 9999

CMD ["perl", "/opt/sonos/bin/sonod"]