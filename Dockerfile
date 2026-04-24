FROM erlang:27-alpine AS builder

WORKDIR /app
COPY app/hermes_config.erl app/hermes_api.erl app/hermes.erl .
RUN erlc hermes_config.erl hermes_api.erl hermes.erl \
    && ls -la *.beam

FROM erlang:27-alpine

WORKDIR /app
COPY --from=builder /app/hermes_config.beam .
COPY --from=builder /app/hermes_api.beam .
COPY --from=builder /app/hermes.beam .

CMD ["erl", "-noshell", "-eval", "hermes:start()"]
