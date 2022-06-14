%%%-------------------------------------------------------------------
%% @doc lesser_evil top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(lesser_evil_node_sup).

-behaviour(supervisor).

-export([start_link/0, new_agent/2, node_handler/1]).

-export([init/1]).

-define(SERVER, ?MODULE).

-ignore_xref([start_link/0]).
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

init([]) ->
    SupFlags = #{strategy => one_for_one,
                 intensity => 10,
                 period => 1},
    ChildSpecs = [],
    {ok, {SupFlags, ChildSpecs}}.

%% internal functions
new_agent(Node, Pid) ->
    case supervisor:start_child(?SERVER,
                                #{id => Node,
                                  start => {le_node, start_link, [Node, Pid]},
                                  restart => transient,
                                  shutdown => 5000,
                                  type => worker,
                                  modules => [le_node]}) of
        {error, {already_started, NodePid}} ->
            le_node:new_agent(NodePid, Pid);
        {ok, _} ->
            ok;
        {ok, _, _} ->
            ok
    end.

node_handler(Node) ->
    case [Child || {Id, Child, _, _} <- supervisor:which_children(?SERVER),
                                        Id =:= Node,
                                        is_pid(Child)] of
        [NodeHandlerPid] -> {ok, NodeHandlerPid};
        [] -> {error, not_found}
    end.

