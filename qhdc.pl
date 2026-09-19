:- module(qhdc,
    [ qhdc_memory_model/1,
      qhdc_trace/1,
      qhdc_reset/0,
      qhdc_compile/2,
      qhdc_run/2,
      qhdc_create_instance/4,
      qhdc_load_instance/1,
      qhdc_run_instance/1,
      qhdc_complete_instance/1,
      qhdc_delete_instance/1,
      qhdc_serialize_instance/2,
      qhdc_restore_instance/1,
      qhdc_transfer/6,
      qhdc_make_packet/7,
      qhdc_receive_packet/2,
      parameter_packet/7,
      carrier/1,
      carrier_send/2,
      carrier_receive/2,
      carrier_verify/1,
      bag_project/2,
      bag_read/2,
      mind_project/3,
      mind_read/2,
      aether_register/2,
      aether_unregister/1,
      aether_lookup/2,
      aether_run/4,
      registered_code/4,
      event/4,
      state_at/2,
      run_from/3,
      rewind_to/1,
      replay_from/1,
      qhdc_replay/1,
      qhdc_gc/0,
      qhdc_logical_duration/2,
      simulation_wall_time/2,
      depends/3,
      compare_ssi_qhdc/3,
      correct_code/1,
      correct_parameters/1,
      correct_time/1,
      correct_parent/1,
      correct_continuation/1,
      qhdc_instance/9,
      instance_failed/2,
      transfer_failed/2,
      code_lookup_failed/1,
      causality_error/1,
      integrity_error/1,
      commit/3
    ]).

:- use_module(library(apply)).
:- use_module(library(crypto)).
:- use_module(library(gensym)).
:- use_module(library(lists)).

:- dynamic qhdc_instance/9.
:- dynamic instance_goal/2.
:- dynamic instance_execution/2.
:- dynamic instance_code_ref/3.
:- dynamic instance_status/2.
:- dynamic execution_goal/2.
:- dynamic execution_instances/2.
:- dynamic execution_started/2.
:- dynamic execution_finished/2.
:- dynamic registered_code/4.
:- dynamic event/4.
:- dynamic depends/3.
:- dynamic parameter_packet/7.
:- dynamic carrier_queue/2.
:- dynamic received_packet/1.
:- dynamic instance_failed/2.
:- dynamic transfer_failed/2.
:- dynamic code_lookup_failed/1.
:- dynamic causality_error/1.
:- dynamic integrity_error/1.
:- dynamic commit/3.
:- dynamic trace_mode/1.
:- dynamic rewind_point/1.

qhdc_memory_model(infinite_simulated).
carrier(simulated_16k_br).
trace_mode(summary).
rewind_point(time(0,create)).

qhdc_trace(Mode) :-
    memberchk(Mode, [off,summary,full]),
    retractall(trace_mode(_)),
    assertz(trace_mode(Mode)).

qhdc_reset :-
    retractall(qhdc_instance(_,_,_,_,_,_,_,_,_)),
    retractall(instance_goal(_,_)),
    retractall(instance_execution(_,_)),
    retractall(instance_code_ref(_,_,_)),
    retractall(instance_status(_,_)),
    retractall(execution_goal(_,_)),
    retractall(execution_instances(_,_)),
    retractall(execution_started(_,_)),
    retractall(execution_finished(_,_)),
    retractall(event(_,_,_,_)),
    retractall(depends(_,_,_)),
    retractall(parameter_packet(_,_,_,_,_,_,_)),
    retractall(carrier_queue(_,_)),
    retractall(received_packet(_)),
    retractall(instance_failed(_,_)),
    retractall(transfer_failed(_,_)),
    retractall(code_lookup_failed(_)),
    retractall(causality_error(_)),
    retractall(integrity_error(_)),
    retractall(commit(_,_,_)),
    retractall(rewind_point(_)),
    assertz(rewind_point(time(0,create))),
    reset_gensym(i),
    reset_gensym(exec),
    reset_gensym(pkt).

qhdc_compile(Goal, ExecutionId) :-
    strip_module(Goal, Module, PlainGoal),
    qhdc_compile_goal(Module, PlainGoal, ExecutionId).

qhdc_compile_goal(Module, PlainGoal, ExecutionId) :-
    gensym(exec_, ExecutionId),
    assertz(execution_goal(ExecutionId, Module:PlainGoal)),
    flatten_conjunction(PlainGoal, PlainGoals),
    maplist(qualify_goal(Module), PlainGoals, Goals),
    build_instances(ExecutionId, Goals, PlainGoal).

qualify_goal(Module, Goal, Module:Goal).

build_instances(ExecutionId, Goals, OriginalGoal) :-
    term_variables(OriginalGoal, Vars),
    build_instances_(Goals, none, ExecutionId, Vars, [], InstanceIds),
    assertz(execution_instances(ExecutionId, InstanceIds)),
    build_dependencies(Goals, InstanceIds, Vars),
    maplist(assert_template_ref, InstanceIds).

build_instances_([], _, _, _, Acc, Acc).
build_instances_([Goal|Rest], Parent, ExecutionId, Vars, Acc0, Acc) :-
    qhdc_create_instance(Parent, Goal, Vars, InstanceId),
    assertz(instance_goal(InstanceId, Goal)),
    assertz(instance_execution(InstanceId, ExecutionId)),
    append(Acc0, [InstanceId], Acc1),
    build_instances_(Rest, InstanceId, ExecutionId, Vars, Acc1, Acc).

assert_template_ref(InstanceId) :-
    instance_goal(InstanceId, Goal),
    functor(Goal, Name, Arity),
    Template =.. [Name,Arity],
    (instance_code_ref(InstanceId, Template, latest) -> true ; assertz(instance_code_ref(InstanceId, Template, latest))).

flatten_conjunction((A,B), Goals) :-
    !,
    flatten_conjunction(A, GA),
    flatten_conjunction(B, GB),
    append(GA, GB, Goals).
flatten_conjunction(true, []) :- !.
flatten_conjunction(Goal, [Goal]).

qhdc_create_instance(ParentId, Goal, Vars, InstanceId) :-
    gensym(i_, InstanceId),
    ( Goal = Module:PlainGoal -> true ; Module = user, PlainGoal = Goal ),
    PlainGoal =.. [PredicateName|Arguments],
    Predicate = Module:PredicateName,
    split_bindings(Arguments, Vars, InputBindings, OutputInfo),
    State = created,
    LogicalTime = time(0,create),
    assertz(qhdc_instance(InstanceId, ParentId, Predicate, Arguments, InputBindings, [], State, LogicalTime, metadata{outputs:OutputInfo})),
    assertz(instance_status(InstanceId, created)),
    record_event(LogicalTime, InstanceId, created, Goal).

split_bindings(Arguments, Vars, Inputs, OutputInfo) :-
    split_bindings_(Arguments, Vars, 1, Inputs, OutputInfo).

split_bindings_([], _, _, [], []).
split_bindings_([Arg|Rest], Vars, Pos, Inputs, Outputs) :-
    Pos1 is Pos + 1,
    split_bindings_(Rest, Vars, Pos1, Inputs0, Outputs0),
    ( var(Arg) ->
        var_id(Arg, Vars, Id),
        Outputs = [out(Pos,Id)|Outputs0],
        Inputs = Inputs0
    ; Inputs = [Arg|Inputs0],
      Outputs = Outputs0
    ).

var_id(Var, Vars, Id) :-
    nth1(Id, Vars, Candidate),
    Candidate == Var,
    !.

build_dependencies(Goals, InstanceIds, Vars) :-
    findall(dep(Consumer,Producer,Param),
            ( nth1(I, Goals, GI),
              nth1(I, InstanceIds, Consumer),
              nth1(J, Goals, GJ),
              nth1(J, InstanceIds, Producer),
              J < I,
              shared_variable(GI, GJ, Vars, Param)
            ),
            Deps),
    maplist(assert_dependency, Deps).

assert_dependency(dep(C,P,Param)) :-
    (depends(C,P,Param) -> true ; assertz(depends(C,P,Param))).

shared_variable(G1, G2, Vars, v(Id)) :-
    term_variables(G1, V1),
    term_variables(G2, V2),
    member(Var, V1),
    member(Other, V2),
    Var == Other,
    var_id(Var, Vars, Id),
    !.

qhdc_run(Goal, Result) :-
    strip_module(Goal, Module, PlainGoal),
    statistics(walltime, [Start,_]),
    qhdc_compile_goal(Module, PlainGoal, ExecutionId),
    get_time_seconds(time(0,execute), T0),
    assertz(execution_started(ExecutionId, T0)),
    run_execution_instances(ExecutionId),
    get_time_seconds(time(0,complete), T1),
    assertz(execution_finished(ExecutionId, T1)),
    qhdc_collect_result(ExecutionId, Result),
    statistics(walltime, [End,_]),
    Wall is End-Start,
    record_event(time(0,complete), ExecutionId, simulation_wall_time, Wall).

run_execution_instances(ExecutionId) :-
    execution_instances(ExecutionId, InstanceIds),
    maplist(qhdc_load_instance, InstanceIds),
    maplist(run_checked_instance, InstanceIds),
    maplist(qhdc_complete_instance, InstanceIds),
    maplist(transfer_from_instance, InstanceIds).

run_checked_instance(InstanceId) :-
    ( correct_code(InstanceId),
      correct_parameters(InstanceId),
      correct_time(InstanceId),
      correct_parent(InstanceId),
      correct_continuation(InstanceId)
    -> qhdc_run_instance(InstanceId)
    ;  assertz(instance_failed(InstanceId, invariant_failed)),
       fail
    ).

qhdc_load_instance(InstanceId) :-
    set_instance_state(InstanceId, loaded, time(0,create)),
    set_instance_state(InstanceId, waiting, time(0,continue)),
    set_instance_state(InstanceId, runnable, time(0,continue)).

qhdc_run_instance(InstanceId) :-
    set_instance_state(InstanceId, running, time(0,execute)),
    instance_goal(InstanceId, Goal),
    ( call(Goal) ->
        update_output_bindings(InstanceId, Goal),
        set_instance_state(InstanceId, running, time(0,produce)),
        record_event(time(0,produce), InstanceId, produced, Goal)
    ; assertz(instance_failed(InstanceId, goal_failed)),
      record_event(time(0,execute), InstanceId, failed, Goal),
      fail
    ).

qhdc_complete_instance(InstanceId) :-
    set_instance_state(InstanceId, completed, time(0,complete)).

qhdc_delete_instance(InstanceId) :-
    set_instance_state(InstanceId, deleted, time(0,cleanup)),
    retractall(instance_goal(InstanceId,_)),
    retractall(instance_execution(InstanceId,_)),
    retractall(instance_status(InstanceId,_)).

update_output_bindings(InstanceId, Goal) :-
    qhdc_instance(InstanceId, Parent, Predicate, Arguments, Inputs, Outputs0, State0, Time0, Metadata),
    goal_arguments(Goal, CurrentArgs),
    Metadata = metadata{outputs:OutputInfo},
    findall(v(VarId)-Value,
            ( member(out(Pos,VarId), OutputInfo),
              nth1(Pos, CurrentArgs, Value)
            ),
            Outputs),
    retract(qhdc_instance(InstanceId, Parent, Predicate, Arguments, Inputs, Outputs0, State0, Time0, Metadata)),
    assertz(qhdc_instance(InstanceId, Parent, Predicate, Arguments, Inputs, Outputs, running, time(0,produce), Metadata)).

goal_arguments(_Module:PlainGoal, Args) :-
    !,
    PlainGoal =.. [_|Args].
goal_arguments(Goal, Args) :-
    Goal =.. [_|Args].

set_instance_state(InstanceId, NewState, LogicalTime) :-
    qhdc_instance(InstanceId, Parent, Predicate, Arguments, Inputs, Outputs, OldState0, OldTime0, Metadata),
    retract(qhdc_instance(InstanceId, Parent, Predicate, Arguments, Inputs, Outputs, OldState0, OldTime0, Metadata)),
    assertz(qhdc_instance(InstanceId, Parent, Predicate, Arguments, Inputs, Outputs, NewState, LogicalTime, Metadata)),
    retractall(instance_status(InstanceId,_)),
    assertz(instance_status(InstanceId, NewState)),
    record_event(LogicalTime, InstanceId, NewState, Predicate).

transfer_from_instance(ProducerId) :-
    forall(depends(ConsumerId, ProducerId, Parameter),
           transfer_parameter(ProducerId, ConsumerId, Parameter)).

transfer_parameter(Source, Destination, Parameter) :-
    qhdc_instance(Source, _Parent, _Predicate, _Args, _Inputs, Outputs, _State, _Time, _Meta),
    member(Parameter-Value, Outputs),
    qhdc_transfer(Source, Destination, Parameter, Value, time(0,transfer), _).

qhdc_transfer(Source, Destination, ParameterId, Value, LogicalTime, PacketId) :-
    qhdc_make_packet(Source, Destination, ParameterId, Value, LogicalTime, PacketId, Packet),
    carrier_send(simulated_16k_br, Packet),
    record_event(LogicalTime, Source, parameter_sent, Packet),
    qhdc_receive_packet(simulated_16k_br, Packet),
    record_event(time(0,receive), Destination, parameter_received, Packet).

qhdc_make_packet(Source, Destination, Parameter, Value, LogicalTime, PacketId, Packet) :-
    gensym(pkt_, PacketId),
    packet_checksum(Source, Destination, Parameter, Value, LogicalTime, Checksum),
    Packet = parameter_packet(PacketId, Source, Destination, Parameter, Value, Checksum, LogicalTime),
    assertz(parameter_packet(PacketId, Source, Destination, Parameter, Value, Checksum, LogicalTime)).

qhdc_receive_packet(Channel, Packet) :-
    carrier_receive(Channel, Packet),
    ( carrier_verify(Packet) ->
        Packet = parameter_packet(PacketId, _Source, _Destination, _Parameter, _Value, _Checksum, _LogicalTime),
        ( received_packet(PacketId) ->
            assertz(integrity_error(Packet)),
            assertz(transfer_failed(PacketId, duplicate_packet)),
            fail
        ; assertz(received_packet(PacketId))
        )
    ; Packet = parameter_packet(PacketId, _, _, _, _, _, _),
      assertz(integrity_error(Packet)),
      assertz(transfer_failed(PacketId, checksum_failed)),
      fail
    ).

packet_checksum(Source, Destination, Parameter, Value, LogicalTime, Checksum) :-
    with_output_to(string(S), write_term([Source,Destination,Parameter,Value,LogicalTime], [quoted(true),numbervars(true)])),
    crypto_data_hash(S, Checksum, [algorithm(sha256)]).

carrier_send(Channel, Packet) :-
    assertz(carrier_queue(Channel, Packet)).

carrier_receive(Channel, Packet) :-
    retract(carrier_queue(Channel, Packet)).

carrier_verify(parameter_packet(_PacketId, Source, Destination, Parameter, Value, Checksum, LogicalTime)) :-
    packet_checksum(Source, Destination, Parameter, Value, LogicalTime, Expected),
    Checksum == Expected.

bag_project(Parameters, CarrierRepresentation) :-
    copy_term(Parameters, CarrierRepresentation).

bag_read(CarrierRepresentation, Parameters) :-
    copy_term(CarrierRepresentation, Parameters).

mind_project(_InstanceId, Parameters, Signal) :-
    bag_project(Parameters, Signal).

mind_read(Signal, Parameters) :-
    bag_read(Signal, Parameters).

aether_register(CodeId, Code) :-
    next_code_version(CodeId, Version),
    hash_code(Code, Hash),
    assertz(registered_code(CodeId, Version, Hash, Code)).

aether_unregister(CodeId) :-
    retractall(registered_code(CodeId,_,_,_)).

aether_lookup(CodeId, Code) :-
    registered_code(CodeId, _Version, _Hash, Code),
    !.
aether_lookup(CodeId, _) :-
    assertz(code_lookup_failed(CodeId)),
    fail.

aether_run(CodeId, Predicate, Parameters, Result) :-
    registered_code(CodeId, Version, Hash, _Code),
    Goal =.. [Predicate|Parameters],
    call(Goal),
    Result = execution_result(CodeId, Version, Hash, Goal).

next_code_version(CodeId, Version) :-
    findall(V, registered_code(CodeId, V, _, _), Versions),
    ( Versions = [] -> Version = 1 ; max_list(Versions, Max), Version is Max + 1 ).

hash_code(Code, Hash) :-
    with_output_to(string(S), write_term(Code, [quoted(true),numbervars(true)])),
    crypto_data_hash(S, Hash, [algorithm(sha256)]).

qhdc_serialize_instance(InstanceId, Serialized) :-
    qhdc_instance(InstanceId, Parent, Predicate, Arguments, Inputs, Outputs, State, LogicalTime, Metadata),
    Serialized = qhdc_instance(InstanceId, Parent, Predicate, Arguments, Inputs, Outputs, State, LogicalTime, Metadata).

qhdc_restore_instance(Serialized) :-
    Serialized = qhdc_instance(InstanceId, Parent, Predicate, Arguments, Inputs, Outputs, State, LogicalTime, Metadata),
    ( qhdc_instance(InstanceId,_,_,_,_,_,_,_,_) -> true
    ; assertz(qhdc_instance(InstanceId, Parent, Predicate, Arguments, Inputs, Outputs, State, LogicalTime, Metadata)),
      assertz(instance_status(InstanceId, State))
    ).

state_at(LogicalTime, state(Instances, Events)) :-
    findall(I, (qhdc_instance(I,_,_,_,_,_,_,T,_), logical_time_leq(T, LogicalTime)), Instances),
    findall(E, (event(T2, Inst, Type, Data), logical_time_leq(T2, LogicalTime), E = event(T2,Inst,Type,Data)), Events).

run_from(_LogicalTime, InstanceId, Result) :-
    qhdc_run_instance(InstanceId),
    qhdc_complete_instance(InstanceId),
    qhdc_instance(InstanceId, _, _, _, _, Outputs, _, _, _),
    Result = Outputs.

rewind_to(LogicalTime) :-
    retractall(rewind_point(_)),
    assertz(rewind_point(LogicalTime)).

replay_from(LogicalTime) :-
    forall((event(T, Inst, Type, Data), logical_time_leq(LogicalTime, T)),
           maybe_trace(event(T,Inst,Type,Data))).

qhdc_replay(File) :-
    open(File, write, Stream),
    forall(event(T, Inst, Type, Data),
           format(Stream, '~q.~n', [event(T,Inst,Type,Data)])),
    close(Stream).

qhdc_gc :-
    findall(InstanceId,
            ( qhdc_instance(InstanceId, _, _, _, _, _, State, _, _),
              memberchk(State, [completed,failed])
            ),
            Dead),
    maplist(qhdc_delete_instance, Dead).

qhdc_logical_duration(ExecutionId, Duration) :-
    execution_started(ExecutionId, _),
    execution_finished(ExecutionId, _),
    Duration = 0.

simulation_wall_time(ExecutionId, Wall) :-
    execution_started(ExecutionId, Start),
    execution_finished(ExecutionId, End),
    Wall is End - Start.

compare_ssi_qhdc(_Program, Query, report{success_match:Match, ssi:SSI, qhdc:QHDC}) :-
    strip_module(Query, Module, PlainQuery),
    copy_term(PlainQuery, SSIPlain),
    term_variables(SSIPlain, SSIVars),
    SSIQuery = Module:SSIPlain,
    ( call(SSIQuery) ->
        maplist(copy_term, SSIVars, SSIValues),
        SSI = success(SSIValues)
    ; SSI = failed
    ),
    copy_term(PlainQuery, QHDCPlain),
    QHDCQuery = Module:QHDCPlain,
    ( qhdc_run(QHDCQuery, QResult) ->
        get_dict(bindings, QResult, Bindings),
        binding_values(Bindings, QHDCValues),
        QHDC = success(QHDCValues)
    ; QHDC = failed
    ),
    ( SSI == QHDC -> Match = true ; Match = false ).

binding_values(Bindings, Values) :-
    findall(Param-Value, member(Param-Value, Bindings), Pairs),
    keysort(Pairs, Sorted),
    findall(V, member(_-V, Sorted), Values).

correct_code(InstanceId) :-
    instance_code_ref(InstanceId, _Template, _Version).

correct_parameters(InstanceId) :-
    qhdc_instance(InstanceId, _, _, _, Inputs, Outputs, _, _, _),
    is_list(Inputs),
    is_list(Outputs).

correct_time(InstanceId) :-
    qhdc_instance(InstanceId, _, _, _, _, _, _, time(_,Phase), _),
    memberchk(Phase, [create,execute,produce,transfer,receive,continue,complete,cleanup]).

correct_parent(InstanceId) :-
    qhdc_instance(InstanceId, Parent, _, _, _, _, _, _, _),
    ( Parent == none
    ; qhdc_instance(Parent, _, _, _, _, _, _, _, _)
    ).

correct_continuation(InstanceId) :-
    instance_execution(InstanceId, _ExecutionId).

qhdc_collect_result(ExecutionId, result{execution:ExecutionId, bindings:Bindings}) :-
    execution_instances(ExecutionId, InstanceIds),
    findall(Param-Value,
            ( member(I, InstanceIds),
              qhdc_instance(I, _, _, _, _, Outputs, _, _, _),
              member(Param-Value, Outputs)
            ),
            BindingList),
    sort(BindingList, Bindings).

logical_time_leq(time(T1,P1), time(T2,P2)) :-
    phase_order(P1, O1),
    phase_order(P2, O2),
    ( T1 < T2 ; (T1 =:= T2, O1 =< O2) ).

phase_order(create, 1).
phase_order(execute, 2).
phase_order(produce, 3).
phase_order(transfer, 4).
phase_order(receive, 5).
phase_order(continue, 6).
phase_order(complete, 7).
phase_order(cleanup, 8).

get_time_seconds(time(T,_), T).

record_event(LogicalTime, Instance, EventType, Data) :-
    assertz(event(LogicalTime, Instance, EventType, Data)),
    maybe_trace(event(LogicalTime, Instance, EventType, Data)).

maybe_trace(_Event) :-
    trace_mode(off),
    !.
maybe_trace(event(T, Inst, Type, _)) :-
    trace_mode(summary),
    !,
    format('T=~w ~w ~w~n', [T, Type, Inst]).
maybe_trace(Event) :-
    trace_mode(full),
    format('~q~n', [Event]).
