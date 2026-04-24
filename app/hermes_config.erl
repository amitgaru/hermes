-module(hermes_config).
-behaviour(gen_server).

-export([start_link/1, get_latency/0, set_latency/1]).
-export([init/1, handle_call/3]).

-define(KEY, hermes_latency).

start_link(InitialLatency) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, InitialLatency, []).

get_latency() ->
    persistent_term:get(?KEY).

set_latency(Latency) when is_integer(Latency), Latency >= 0 ->
    gen_server:call(?MODULE, {set_latency, Latency}).

init(InitialLatency) ->
    persistent_term:put(?KEY, InitialLatency),
    {ok, InitialLatency}.

handle_call({set_latency, Latency}, _From, _State) ->
    persistent_term:put(?KEY, Latency),
    io:format("Latency updated to ~pms~n", [Latency]),
    {reply, ok, _State}.
