-module(hermes_api).
-behaviour(gen_server).

-export([start_link/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

start_link(Host, Port) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, {Host, Port}, []).

init({Host, Port}) ->
    case
        gen_tcp:listen(Port, [
            binary,
            {active, false},
            {reuseaddr, true},
            {ip, parse_host(Host)},
            {packet, http_bin}
        ])
    of
        {ok, LSock} ->
            self() ! accept,
            {ok, LSock};
        {error, Reason} ->
            {stop, {listen_failed, Host, Port, Reason}}
    end.

handle_info(accept, LSock) ->
    case gen_tcp:accept(LSock) of
        {ok, Sock} ->
            spawn(fun() -> handle_request(Sock) end),
            self() ! accept;
        {error, Reason} ->
            io:format("API accept error: ~p~n", [Reason]),
            self() ! accept
    end,
    {noreply, LSock};
handle_info(_Msg, State) ->
    {noreply, State}.

handle_call(_Req, _From, State) -> {reply, ok, State}.
handle_cast(_Msg, State) -> {noreply, State}.

parse_host(Host) ->
    {ok, Addr} = inet:parse_address(Host),
    Addr.

handle_request(Sock) ->
    case read_request(Sock) of
        {ok, Method, Path, Body} ->
            handle_route(Sock, Method, Path, Body);
        {error, Reason} ->
            io:format("API read error: ~p~n", [Reason])
    end,
    gen_tcp:close(Sock).

read_request(Sock) ->
    case gen_tcp:recv(Sock, 0, 5000) of
        {ok, {http_request, Method, {abs_path, Path}, _Vsn}} ->
            ContentLength = read_headers(Sock),
            Body = read_body(Sock, ContentLength),
            {ok, Method, Path, Body};
        {error, Reason} ->
            {error, Reason}
    end.

read_headers(Sock) ->
    read_headers(Sock, 0).

read_headers(Sock, ContentLength) ->
    case gen_tcp:recv(Sock, 0, 5000) of
        {ok, {http_header, _, 'Content-Length', _, Value}} ->
            read_headers(Sock, binary_to_integer(Value));
        {ok, http_eoh} ->
            ContentLength;
        {ok, _} ->
            read_headers(Sock, ContentLength);
        {error, _} ->
            ContentLength
    end.

read_body(_Sock, 0) ->
    <<>>;
read_body(Sock, Len) ->
    inet:setopts(Sock, [{packet, raw}]),
    case gen_tcp:recv(Sock, Len, 5000) of
        {ok, Body} -> Body;
        {error, _} -> <<>>
    end.

handle_route(Sock, 'GET', <<"/latency">>, _Body) ->
    LatencyMs = hermes_config:get_latency(),
    Json = iolist_to_binary(io_lib:format("{\"latency\":~p}", [LatencyMs])),
    send_response(Sock, 200, Json);
handle_route(Sock, 'POST', <<"/latency">>, Body) ->
    case parse_latency_json(Body) of
        {ok, LatencyMs} ->
            hermes_config:set_latency(LatencyMs),
            Json = iolist_to_binary(io_lib:format("{\"latency\":~p}", [LatencyMs])),
            send_response(Sock, 200, Json);
        error ->
            send_response(Sock, 400, <<"{\"error\":\"expected {\\\"latency\\\":N}\"}">>)
    end;
handle_route(Sock, _Method, _Path, _Body) ->
    send_response(Sock, 404, <<"{\"error\":\"not found\"}">>).

send_response(Sock, Code, Body) ->
    Status = status_line(Code),
    Len = integer_to_binary(byte_size(Body)),
    Response = [
        Status,
        "\r\n",
        "Content-Type: application/json\r\n",
        "Content-Length: ",
        Len,
        "\r\n",
        "Connection: close\r\n",
        "\r\n",
        Body
    ],
    gen_tcp:send(Sock, Response).

status_line(200) -> <<"HTTP/1.1 200 OK">>;
status_line(400) -> <<"HTTP/1.1 400 Bad Request">>;
status_line(404) -> <<"HTTP/1.1 404 Not Found">>.

parse_latency_json(Body) ->
    case re:run(Body, <<"\"latency\"\\s*:\\s*(\\d+)">>, [{capture, [1], binary}]) of
        {match, [LatencyMs]} -> {ok, binary_to_integer(LatencyMs)};
        nomatch -> error
    end.
