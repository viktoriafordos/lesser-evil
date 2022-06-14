%%%-------------------------------------------------------------------
%% @doc lesser_evil top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(lesser_evil_sup).

-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%% sup_flags() = #{strategy => strategy(),         % optional
%%                 intensity => non_neg_integer(), % optional
%%                 period => pos_integer()}        % optional
%% child_spec() = #{id => child_id(),       % mandatory
%%                  start => mfargs(),      % mandatory
%%                  restart => restart(),   % optional
%%                  shutdown => shutdown(), % optional
%%                  type => worker(),       % optional
%%                  modules => modules()}   % optional
init([]) ->
    SupFlags = #{strategy => one_for_all,
                 intensity => 0,
                 period => 1},
    ChildSpecs = [#{id => le_monitor_server,
                    start => {le_monitor_server, start_link, []}
                   },
                  #{id => lesser_evil_node_sup,
                    start => {lesser_evil_node_sup,start_link,[]},
                    restart => permanent,
                    shutdown => 5000,
                    type => supervisor,
                    modules => [lesser_evil_node_sup, le_node]
                   }],
    {ok, {SupFlags, ChildSpecs}}.

%% internal functions
