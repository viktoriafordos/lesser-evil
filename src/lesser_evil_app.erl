%%%-------------------------------------------------------------------
%% @doc lesser_evil public API
%% @end
%%%-------------------------------------------------------------------

-module(lesser_evil_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
  lesser_evil_sup:start_link().

stop(_State) ->
  ok.

%% internal functions
