FROM hexpm/elixir:1.16.2-erlang-26.0.2-alpine-3.19.1 as builder

ENV MIX_ENV=prod
WORKDIR /build

COPY mix.exs mix.lock ./
COPY config config
COPY lib lib

RUN mix local.hex --force

RUN mix deps.get; mix release

FROM alpine:3.19.1 as runner

RUN apk add \
  ca-certificates \
  openssl \
  # needed for health check
  ncurses-libs \
  curl \
  # needed for distillery
  bash \
  libstdc++

COPY --from=builder /build/_build/prod/rel/hh_discord_app .

RUN ls -R releases

USER nobody

ENTRYPOINT [ "bin/hh_discord_app" ]