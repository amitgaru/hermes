-module(hermes).
-export([start/0, start/6]).

start() ->
    ListenHost = os:getenv("LISTEN_HOST", "127.0.0.1"),
    ListenPort = list_to_integer(os:getenv("LISTEN_PORT", "6380")),
    ForwardHost = os:getenv("FORWARD_HOST", "127.0.0.1"),
    ForwardPort = list_to_integer(os:getenv("FORWARD_PORT", "6379")),
    LatencyMs = round(list_to_integer(os:getenv("LATENCY_MSECS", "0"))),
    BufferSize = list_to_integer(os:getenv("BUFFER_SIZE", "65536")),
    start(ListenHost, ListenPort, ForwardHost, ForwardPort, LatencyMs, BufferSize).

start(ListenHost, ListenPort, ForwardHost, ForwardPort, LatencyMs, BufferSize) ->
    {ok, _} = hermes_config:start_link(LatencyMs),

    ApiHost = os:getenv("API_HOST", "127.0.0.1"),
    ApiPort = list_to_integer(os:getenv("API_PORT", "8000")),
    case hermes_api:start_link(ApiHost, ApiPort) of
        {ok, _} ->
            io:format("API listening on ~s:~p~n", [ApiHost, ApiPort]);
        {error, Reason} ->
            io:format("WARNING: API server failed to start on ~s:~p: ~p~n", [
                ApiHost, ApiPort, Reason
            ]),
            io:format("Proxy will run without HTTP API~n")
    end,

    {ok, ListenSock} = gen_tcp:listen(ListenPort, [
        binary,
        {active, false},
        {reuseaddr, true},
        {nodelay, true},
        {ip, parse_host(ListenHost)},
        {recbuf, BufferSize},
        {sndbuf, BufferSize}
    ]),
    io:format(
        "Forwarding ~s:~p -> ~s:~p with initial delay ~pms~n",
        [ListenHost, ListenPort, ForwardHost, ForwardPort, LatencyMs]
    ),
    accept_loop(ListenSock, ForwardHost, ForwardPort, BufferSize).

parse_host(Host) ->
    {ok, Addr} = inet:parse_address(Host),
    Addr.

accept_loop(ListenSock, ForwardHost, ForwardPort, BufferSize) ->
    case gen_tcp:accept(ListenSock) of
        {ok, ClientSock} ->
            spawn(fun() ->
                handle_connection(ClientSock, ForwardHost, ForwardPort, BufferSize)
            end),
            accept_loop(ListenSock, ForwardHost, ForwardPort, BufferSize);
        {error, closed} ->
            io:format("Listen socket closed, shutting down~n");
        {error, Reason} ->
            io:format("accept error: ~p, continuing~n", [Reason]),
            accept_loop(ListenSock, ForwardHost, ForwardPort, BufferSize)
    end.

handle_connection(ClientSock, ForwardHost, ForwardPort, BufferSize) ->
    case
        gen_tcp:connect(ForwardHost, ForwardPort, [
            binary,
            {active, false},
            {nodelay, true},
            {recbuf, BufferSize},
            {sndbuf, BufferSize}
        ])
    of
        {ok, ServerSock} ->
            Parent = self(),
            WriterPid = spawn_link(fun() -> upstream_writer(ServerSock, Parent) end),
            Up = spawn_link(fun() -> upstream_reader(ClientSock, WriterPid, Parent) end),
            Down = spawn_link(fun() -> downstream(ServerSock, ClientSock, Parent) end),
            wait_for_done(Up, Down, WriterPid, ClientSock, ServerSock);
        {error, Reason} ->
            io:format("Failed to connect to target: ~p~n", [Reason]),
            gen_tcp:close(ClientSock)
    end.

upstream_reader(ClientSock, WriterPid, Parent) ->
    case gen_tcp:recv(ClientSock, 0) of
        {ok, Data} ->
            % Latency is in milliseconds
            RcvTime = erlang:monotonic_time(millisecond),
            Latency = hermes_config:get_latency(),
            Deadline = RcvTime + Latency,
            erlang:send_after(max(0, Latency - 1), WriterPid, {send, Deadline, Data}),
            upstream_reader(ClientSock, WriterPid, Parent);
        {error, _} ->
            Parent ! {done, self()}
    end.

busy_wait(Deadline) ->
    case erlang:monotonic_time(millisecond) >= Deadline of
        true -> ok;
        false -> busy_wait(Deadline)
    end.

upstream_writer(ServerSock, Parent) ->
    receive
        {send, Deadline, Data} ->
            busy_wait(Deadline),
            case gen_tcp:send(ServerSock, Data) of
                ok -> upstream_writer(ServerSock, Parent);
                {error, _} -> Parent ! {done, self()}
            end
    end.

downstream(ServerSock, ClientSock, Parent) ->
    case gen_tcp:recv(ServerSock, 0) of
        {ok, Data} ->
            case gen_tcp:send(ClientSock, Data) of
                ok -> downstream(ServerSock, ClientSock, Parent);
                {error, _} -> Parent ! {done, self()}
            end;
        {error, _} ->
            Parent ! {done, self()}
    end.

wait_for_done(Up, Down, WriterPid, ClientSock, ServerSock) ->
    receive
        {done, _Pid} ->
            exit(Up, shutdown),
            exit(Down, shutdown),
            exit(WriterPid, shutdown),
            gen_tcp:close(ClientSock),
            gen_tcp:close(ServerSock)
    end.
