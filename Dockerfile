# Build stage
FROM hexpm/elixir:1.19.5-erlang-28.3.2-debian-bookworm-20260202-slim AS build

RUN apt-get update -y && \
    apt-get install -y build-essential git && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

# Install dependencies first for better layer caching
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Copy app code, runtime config, and release overlays
COPY lib lib
COPY priv priv
COPY config/runtime.exs config/
COPY rel rel

# Compile the project (generates colocated hooks needed by esbuild)
RUN mix compile --warnings-as-errors

# Build assets (uses Elixir-managed esbuild + tailwind, no Node.js needed)
COPY assets assets
RUN mix assets.deploy

# Build release
RUN mix release

# Runtime stage
FROM debian:bookworm-slim AS runtime

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Set locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app

# Create non-root user
RUN groupadd --gid 1000 app && \
    useradd --uid 1000 --gid app --shell /bin/bash --create-home app

# Copy release from build stage
COPY --from=build --chown=app:app /app/_build/prod/rel/event_modeler ./

USER app

EXPOSE 4000

ENV PHX_SERVER=true

ENTRYPOINT ["bin/event_modeler"]
CMD ["start"]
