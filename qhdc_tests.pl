:- begin_tests(qhdc).

:- use_module('/home/runner/work/qhdc/qhdc/qhdc').

:- dynamic code_v1/2.
:- dynamic code_v2/2.

double(A,B) :- B is A*2.
add_one(A,B) :- B is A+1.
square(A,B) :- B is A*A.

pipeline(A,R) :-
    double(A,B),
    add_one(B,C),
    square(C,R).

repeat_double(A,C) :-
    double(A,B),
    double(B,C).

factorial(0,1).
factorial(N,F) :-
    N > 0,
    N1 is N-1,
    factorial(N1,F1),
    F is N*F1.

even(0).
even(N) :- N > 0, N1 is N-1, odd(N1).
odd(N) :- N > 0, N1 is N-1, even(N1).

choose(X) :- member(X, [a,b,c]).

with_cut(X,Y) :- (X > 0 -> !, Y = positive ; Y = non_positive).

nested_term(T) :- T = data(user{name:"qhdc",tags:[a,b]}, [1,2,3], "ok").

setup_qhdc :-
    qhdc_reset,
    qhdc_trace(off).

has_binding_value(Result, Value) :-
    get_dict(bindings, Result, Bindings),
    member(_-Value, Bindings).

test(sequential_pipeline, [setup(setup_qhdc)]) :-
    qhdc_run(plunit_qhdc:pipeline(5,_), Result),
    has_binding_value(Result, 121).

test(repeated_predicate_calls, [setup(setup_qhdc)]) :-
    qhdc_run(plunit_qhdc:repeat_double(5,_), Result),
    has_binding_value(Result, 20).

test(recursion_factorial, [setup(setup_qhdc)]) :-
    qhdc_run(plunit_qhdc:factorial(5,_), Result),
    has_binding_value(Result, 120).

test(mutual_recursion, [setup(setup_qhdc)]) :-
    qhdc_run(plunit_qhdc:even(6), _).

test(cut_semantics, [setup(setup_qhdc)]) :-
    qhdc_run(plunit_qhdc:with_cut(2,_), Result),
    has_binding_value(Result, positive).

test(structured_terms, [setup(setup_qhdc)]) :-
    qhdc_run(plunit_qhdc:nested_term(_), Result),
    has_binding_value(Result, data(user{name:"qhdc",tags:[a,b]}, [1,2,3], "ok")).

test(transfer_integrity_ok, [setup(setup_qhdc)]) :-
    qhdc_transfer(i_src, i_dst, p1, hello(world), time(0,transfer), _).

test(transfer_integrity_corrupted, [setup(setup_qhdc), fail]) :-
    qhdc_make_packet(i1, i2, p1, value, time(0,transfer), _PacketId, Packet),
    Packet = parameter_packet(PId,S,D,P,V,_Checksum,T),
    Bad = parameter_packet(PId,S,D,P,V,'bad-checksum',T),
    carrier_send(simulated_16k_br, Bad),
    qhdc_receive_packet(simulated_16k_br, _).

test(code_registry_versioning, [setup(setup_qhdc)]) :-
    aether_register(code_math, [member/2]),
    aether_register(code_math, [member/2,append/3]),
    findall(V, registered_code(code_math, V, _, _), Versions),
    Versions == [1,2],
    aether_lookup(code_math, [member/2,append/3]),
    aether_run(code_math, member, [a,[a,b]],
               execution_result(code_math, 2, _, member(a,[a,b]))).

test(aether_rejects_unregistered_predicate, [setup(setup_qhdc), fail]) :-
    aether_register(code_math, [double/2]),
    aether_run(code_math, member, [a,[a,b]], _).

test(code_lookup_failure_recorded, [setup(setup_qhdc), fail]) :-
    aether_lookup(missing_code, _).

test(serialize_restore_instance, [setup(setup_qhdc)]) :-
    qhdc_compile(plunit_qhdc:double(2,_), Exec),
    qhdc:execution_instances(Exec, [First]),
    qhdc_serialize_instance(First, S),
    qhdc_delete_instance(First),
    qhdc_restore_instance(S),
    qhdc_instance(First,_,_,_,_,_,_,_,_),
    run_from(time(0,execute), First, [v(1)-4]).

test(run_from_later_anchor, [setup(setup_qhdc)]) :-
    qhdc_compile(plunit_qhdc:double(2,_), Exec),
    qhdc:execution_instances(Exec, [InstanceId]),
    run_from(time(0,produce), InstanceId, [v(1)-4]),
    qhdc_instance(InstanceId, _, _, _, _, _, completed, time(1,complete), _).

test(logical_and_wall_duration, [setup(setup_qhdc)]) :-
    qhdc_run(plunit_qhdc:double(2,_), Result),
    get_dict(execution, Result, ExecutionId),
    qhdc_logical_duration(ExecutionId, 6),
    simulation_wall_time(ExecutionId, Wall),
    Wall >= 0.

test(completion_commits, [setup(setup_qhdc)]) :-
    qhdc_run(plunit_qhdc:double(3,_), _),
    commit(_, [v(1)-6], metadata{logical_time:time(0,complete)}).

test(out_of_order_transfer_causality_fact, [setup(setup_qhdc)]) :-
    qhdc_compile(plunit_qhdc:(double(2,Intermediate),add_one(Intermediate,_)), Exec),
    qhdc:execution_instances(Exec, [Producer,_]),
    qhdc:depends(Consumer, Producer, Parameter),
    \+ qhdc:transfer_parameter(Producer, Consumer, Parameter),
    causality_error(causality_violation(Producer, Consumer, Parameter)).

test(time_state_and_replay, [setup(setup_qhdc)]) :-
    qhdc_run(plunit_qhdc:pipeline(2,_), _),
    state_at(time(0,produce), state(_Instances, Events)),
    Events \= [],
    rewind_to(time(0,execute)),
    replay_from(time(0,execute)).

test(replay_file, [setup(setup_qhdc)]) :-
    qhdc_run(plunit_qhdc:pipeline(2,_), _),
    qhdc_replay('/tmp/qhdc_replay.pl').

test(gc_cleanup, [setup(setup_qhdc)]) :-
    qhdc_run(plunit_qhdc:pipeline(2,_), _),
    qhdc_gc,
    \+ qhdc_instance(_,_,_,_,_,_,completed,_,_).

test(compare_mode, [setup(setup_qhdc), true(Match == true)]) :-
    compare_ssi_qhdc([], plunit_qhdc:pipeline(5,_), report{success_match:Match,ssi:_,qhdc:_}).

:- end_tests(qhdc).
