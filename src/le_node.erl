-module(le_node).
-behavior(gen_server).

-export([start_link/2,
         new_agent/2,
         new_data/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3, format_status/2]).

-record(state, {agent,
                agent_ref,
                cpu_bound,
                max_cpu_load,
                memory_bound,
                max_memory,
                procs = [],
                last_action_ts,
                log}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%% @end
%%--------------------------------------------------------------------
-spec start_link(node(), pid()) -> {ok, Pid :: pid()} |
        {error, Error :: {already_started, pid()}} |
        {error, Error :: term()} |
        ignore.
-ignore_xref([start_link/2]).
start_link(Node, AgentPid) ->
  gen_server:start_link(?MODULE, [Node, AgentPid], []).

new_agent(NPid, AgentPid) ->
    gen_server:cast(NPid, {new_agent, AgentPid}).

new_data(NPid, Data) ->
    gen_server:cast(NPid, {new_data, Data}).
%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%% @end
%%--------------------------------------------------------------------
-spec init(Args :: term()) -> {ok, State :: term()} |
        {ok, State :: term(), Timeout :: timeout()} |
        {ok, State :: term(), hibernate} |
        {stop, Reason :: term()} |
        ignore.
init([Node, AgentPid]) ->
    process_flag(trap_exit, true),
    {ok, NodeSettings} = application:get_env(lesser_evil, per_node_settings),
    {ok, Dir} = application:get_env(lesser_evil, log),
    case lists:keyfind(Node, 1, NodeSettings) of
        false ->
            Error = {error, {missing_config,
                             [lesser_evil, per_node_settings, Node]}},
            {stop, Error};
        {Node, Config}  ->
            State = init_log(Dir, init_state(AgentPid, Config)),
            {ok, State}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%% @end
%%--------------------------------------------------------------------
-spec handle_call(Request :: term(), From :: {pid(), term()}, State :: term()) ->
        {reply, Reply :: term(), NewState :: term()} |
        {reply, Reply :: term(), NewState :: term(), Timeout :: timeout()} |
        {reply, Reply :: term(), NewState :: term(), hibernate} |
        {noreply, NewState :: term()} |
        {noreply, NewState :: term(), Timeout :: timeout()} |
        {noreply, NewState :: term(), hibernate} |
        {stop, Reason :: term(), Reply :: term(), NewState :: term()} |
        {stop, Reason :: term(), NewState :: term()}.
handle_call(_Request, _From, State) ->
  Reply = ok,
  {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%% @end
%%--------------------------------------------------------------------
-spec handle_cast(Request :: term(), State :: term()) ->
        {noreply, NewState :: term()} |
        {noreply, NewState :: term(), Timeout :: timeout()} |
        {noreply, NewState :: term(), hibernate} |
        {stop, Reason :: term(), NewState :: term()}.
handle_cast({new_data, Data}, State) ->
    NewState = process_data(Data, State),
    {noreply, NewState};
handle_cast({new_agent, AgentPid}, #state{agent_ref = OldMonRef} = State) ->
    case is_reference(OldMonRef) of
        false -> ok;
        _ -> erlang:demonitor(OldMonRef, [flush])
    end,
    MonRef = erlang:monitor(process, AgentPid),
    {noreply, State#state{agent_ref = MonRef, agent = AgentPid}};
handle_cast(_Request, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%% @end
%%--------------------------------------------------------------------
-spec handle_info(Info :: timeout() | term(), State :: term()) ->
        {noreply, NewState :: term()} |
        {noreply, NewState :: term(), Timeout :: timeout()} |
        {noreply, NewState :: term(), hibernate} |
        {stop, Reason :: normal | term(), NewState :: term()}.
handle_info(timeout, #state{agent=Agent} = State) when is_pid(Agent) ->
    {noreply, State};
handle_info(timeout, #state{agent=undefined} = State) ->
    {stop, normal, State};
handle_info({'DOWN', Ref, _, _, _}, #state{agent_ref = Ref} = State) ->
    NewState = State#state{agent = undefined, agent_ref = undefined},
    {noreply, NewState, (10*60*1000)};
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%% @end
%%--------------------------------------------------------------------
-spec terminate(Reason :: normal | shutdown | {shutdown, term()} | term(),
                State :: term()) -> any().
terminate(_Reason, #state{log = Fd} = State) ->
  file:close(Fd).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%% @end
%%--------------------------------------------------------------------
-spec code_change(OldVsn :: term() | {down, term()},
                  State :: term(),
                  Extra :: term()) -> {ok, NewState :: term()} |
        {error, Reason :: term()}.
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called for changing the form and appearance
%% of gen_server status when it is returned from sys:get_status/1,2
%% or when it appears in termination error logs.
%% @end
%%--------------------------------------------------------------------
-spec format_status(Opt :: normal | terminate,
                    Status :: list()) -> Status :: term().
format_status(_Opt, Status) ->
  Status.

%%%===================================================================
%%% Internal functions
%%%===================================================================
init_state(AgentPid, Config) ->
    State = memory_config(Config, cpu_config(Config, #state{})),
    MonRef = erlang:monitor(process, AgentPid),
    State#state{agent = AgentPid, agent_ref = MonRef}.

init_log(undefined, #state{} = State) -> State;
init_log(Path, State) when is_list(Path) ->
    Name = "lesser_evil_"++integer_to_list(erlang:unique_integer([positive])),
    File = filename:join([Path, Name]),
    {ok, Fd} = file:open(File, [append]),
    State#state{log=Fd}.

cpu_config(Config, State) ->
    case lists:keyfind(cpu_bound, 1, Config) of
        {cpu_bound, true} ->
            {max_cpu_load, Load} = lists:keyfind(max_cpu_load, 1, Config),
            true = (is_float(Load) andalso Load > 0.0),
            State#state{cpu_bound = true,
                        max_cpu_load = Load};
        _ ->
            State#state{cpu_bound = false}
    end.

memory_config(Config, State) ->
    case lists:keyfind(memory_bound, 1, Config) of
        {memory_bound, true} ->
            {max_memory, Memory} = lists:keyfind(max_memory, 1, Config),
            true = (Memory =:= system orelse
                        is_integer(Memory) andalso Memory > 0),
            case Memory of
                system ->
                    State#state{memory_bound = true,
                                max_memory = system};
                _ -> 
                    State#state{memory_bound = true,
                                max_memory = Memory * 1024 * 1024}
            end;
        _ ->
            State#state{memory_bound = false}
    end.

process_data(_Data, #state{memory_bound = false, cpu_bound = false} = State) ->
    State;
process_data({PData, SysData}, State) ->
    case compensating_action_needed(SysData, State) of
        false ->
            update_procs(PData, State);
        Action ->
            exec_action(Action, update_procs(PData, State))
    end.

compensating_action_needed(#{erlang_vm_total_memory := VmMem,
                             host_total_memory := HostMem},
                           #state{memory_bound = true,
                                  max_memory = system,
                                  last_action_ts = Ts}) ->
    case not_in_cooldown_period(Ts) of
        true when (HostMem * 0.85) < VmMem -> {kill, VmMem - (HostMem * 0.85)};
        true when (HostMem * 0.7) < VmMem -> {gc, VmMem - (HostMem * 0.7)};
        _ -> false
    end;
compensating_action_needed(#{erlang_vm_total_memory := VmMem},
                           #state{memory_bound = true,
                                  max_memory = MaxMem,
                                  last_action_ts = Ts}) ->
    case not_in_cooldown_period(Ts) of
        true when MaxMem < VmMem -> {kill, VmMem - MaxMem};
        true when (MaxMem * 0.8) < VmMem -> {gc, VmMem - (MaxMem * 0.8)};
        %% true when (MaxMem * 0.85) < VmMem -> {kill, VmMem - (MaxMem * 0.85)};
        %% true when (MaxMem * 0.7) < VmMem -> {gc, VmMem - (MaxMem * 0.7)};
        _ -> false
    end.

update_procs(Procs, #state{procs = Procs0} = State) ->
    SortedProcs = lists:usort(fun(#{pid := P1}, #{pid := P2}) ->
                                 P1 =< P2
                              end, Procs),
    State#state{procs = update_procs0(SortedProcs, Procs0, [])}.

update_procs0([], _DeadProcs, Procs) -> lists:reverse(Procs);
update_procs0(NewProcs, [], Procs) ->
    lists:reverse(Procs) ++
        [NProc#{score => calculate_score(NProc, new),
                age => 1} || NProc <- NewProcs];
update_procs0([#{pid := NP} = NProc0|NPs],
              [#{pid := NP, age := Age} = OProc|OPs], Procs) ->
    NProc = NProc0#{score => calculate_score(NProc0, OProc),
                    age => Age + 1},
    update_procs0(NPs, OPs, [NProc|Procs]);
update_procs0([#{pid := NP} = NProc0|NPs],
              [#{pid := OP}|OPs], Procs) when NP < OP ->
    % NP is new
    NProc = NProc0#{score => calculate_score(NProc0, new),
                    age => 1},
    update_procs0(NPs, OPs, [NProc|Procs]);
update_procs0([#{pid := NP} = NProc0|NPs],
              [#{pid := OP}|OPs], Procs) when NP > OP ->
    % OP is dead
    update_procs0([NProc0|NPs], OPs, Procs).

calculate_score(#{links := Links, monitored_by := MonBy}, _) when Links > 10;
                                                                  MonBy > 10 ->
    -100;
calculate_score(#{links := Links, memory := Memory,
                  message_queue_len := MsgQLen, monitored_by := MonBy,
                  priority := Prio, reductions := Reds}, new) ->
    Age = 1,
    Memory/1024 * (MsgQLen+1) /
        math:log10(Reds) / (Links+1) / Age / prio(Prio) / (MonBy+1);
calculate_score(#{links := Links, memory := Memory,
                  message_queue_len := MsgQLen, monitored_by := MonBy,
                  priority := Prio, reductions := Reds}, #{age := Age}) ->
    Memory/1024 * (MsgQLen+1) /
        math:log10(Reds) / (Links+1) / Age / prio(Prio) / (MonBy+1).

prio(low) -> 1;
prio(normal) -> 1;
prio(high) -> 10;
prio(max) -> 100;
prio(_) -> 1.

not_in_cooldown_period(undefined) -> true; % first action
not_in_cooldown_period(Ts) ->
    erlang:convert_time_unit(erlang:monotonic_time() - Ts, native, second) > 5.

exec_action({Action, Mem},
            #state{procs = Procs, agent = AgentPid, log = Fd} = State) ->
    TroubleMakers =
        satisfy_mem(Mem,
                    lists:usort(fun(#{score := S1}, #{score := S2}) ->
                                    S1 >= S2
                                end, Procs),
                    []),
    log(Fd, Action, TroubleMakers),
    exec_action(AgentPid, Action, TroubleMakers),
    State#state{last_action_ts = erlang:monotonic_time()}.

satisfy_mem(_Mem, [], TroubleMakers) -> lists:reverse(TroubleMakers);
%satisfy_mem(_Mem, _Procs, [_,_,_,_,_,_,_,_,_,_,_] = TroubleMakers) -> TroubleMakers;
satisfy_mem(Mem, _Procs, TroubleMakers) when Mem =< 0 -> TroubleMakers;
satisfy_mem(Mem, [#{score := Score} | Procs], TroubleMakers) when Score < 0 ->
    satisfy_mem(Mem, Procs, TroubleMakers);
satisfy_mem(Mem, [#{memory := Memory} | Procs], TroubleMakers) when Memory < 15360 ->
    satisfy_mem(Mem, Procs, TroubleMakers);
satisfy_mem(Mem, [#{memory := MemB} = P | Procs], TroubleMakers)  ->
    satisfy_mem(Mem - MemB, Procs, [P | TroubleMakers]).

exec_action(_AgentPid, _Action, [] = _TroubleMakers) -> ok;
exec_action(AgentPid, Action, TroubleMakers) ->
    AgentPid ! {Action, [Pid  || #{pid := Pid} <- TroubleMakers]}.

log(_Fd, _Action, [] = _TroubleMakers) -> ok;
log(Fd, Action, TroubleMakers) ->
    spawn(fun() ->
              Log = io_lib:format("~p~n", [{Action, TroubleMakers}]),
              file:write(Fd, Log)
          end),
    ok.