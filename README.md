# qhdc

Quantum HDC.

## Repository entry points

- `/home/runner/work/qhdc/qhdc/qhdc.pl` — QHDC runtime and exported predicates
- `/home/runner/work/qhdc/qhdc/qhdc_tests.pl` — plunit test suite and sample predicates used in examples

## Quick start

### Run the test suite

```bash
swipl -q -g "['/home/runner/work/qhdc/qhdc/qhdc_tests.pl'], run_tests, halt"
```

This loads the test file, which in turn loads the QHDC module, runs every plunit test, and exits cleanly.

### Start an interactive SWI-Prolog session

```bash
swipl
```

Then load both the runtime and the sample predicates:

```prolog
?- ['/home/runner/work/qhdc/qhdc/qhdc.pl',
    '/home/runner/work/qhdc/qhdc/qhdc_tests.pl'].
```

This gives you the `qhdc` module plus the example predicates from the test file, such as `pipeline/2`, `double/2`, `factorial/2`, and `nested_term/1`.

## Complete showcase of commands

The sections below are meant to be copied into a SWI-Prolog REPL exactly as written.

### 1. Reset the simulator state

```prolog
?- qhdc:qhdc_reset.
```

Use this before each fresh experiment. It clears instances, events, packets, failures, commits, and replay state.

### 2. Control trace verbosity

```prolog
?- qhdc:qhdc_trace(off).
?- qhdc:qhdc_trace(summary).
?- qhdc:qhdc_trace(full).
```

- `off` disables tracing
- `summary` prints compact lifecycle events
- `full` prints the entire stored event term

### 3. Compile a goal into QHDC instances without running it

```prolog
?- qhdc:qhdc_reset,
   qhdc:qhdc_compile(plunit_qhdc:pipeline(5, Result), ExecutionId).
```

This turns the Prolog goal into an execution identifier plus a chain of instance records. It is useful when you want to inspect planned work before execution.

Inspect the generated instances:

```prolog
?- qhdc:qhdc_instance(InstanceId, ParentId, Predicate, Arguments,
                      Inputs, Outputs, State, LogicalTime, Metadata).
```

This exposes each compiled node, including its parent, current state, known inputs, produced outputs, and metadata about output variables.

Inspect dependency edges between instances:

```prolog
?- qhdc:depends(ConsumerId, ProducerId, Parameter).
```

This shows which instance depends on which earlier instance, and which logical parameter is transferred between them.

### 4. Run a goal end to end

```prolog
?- qhdc:qhdc_reset,
   qhdc:qhdc_trace(off),
   qhdc:qhdc_run(plunit_qhdc:pipeline(5, Result), RunResult).
```

This compiles the goal, loads every instance, executes each goal, transfers parameter packets, completes the execution, and returns a result dict.

Inspect the bound Prolog result:

```prolog
?- Result.
```

For `pipeline(5, Result)`, the final value is expected to be `121`.

Inspect the QHDC result dict:

```prolog
?- RunResult.
```

The dict contains:

- `execution` — the generated execution id
- `bindings` — the sorted output bindings collected from all completed instances

### 5. Walk through the instance lifecycle manually

Create one instance directly:

```prolog
?- qhdc:qhdc_reset,
   qhdc:qhdc_create_instance(none, plunit_qhdc:double(5, X), [X], InstanceId).
```

This allocates a single instance without using the compiler.

Load it into a runnable state:

```prolog
?- qhdc:qhdc_load_instance(InstanceId).
```

Run the instance goal:

```prolog
?- qhdc:qhdc_run_instance(InstanceId).
```

Mark the instance complete:

```prolog
?- qhdc:qhdc_complete_instance(InstanceId).
```

Delete the finished instance:

```prolog
?- qhdc:qhdc_delete_instance(InstanceId).
```

These commands are useful when testing lifecycle transitions in isolation.

### 6. Serialize and restore an instance

Serialize:

```prolog
?- qhdc:qhdc_serialize_instance(InstanceId, Serialized).
```

Restore later:

```prolog
?- qhdc:qhdc_restore_instance(Serialized).
```

This is the simplest way to checkpoint one compiled instance and recreate it later.

### 7. Inspect event history and time-sliced state

List recorded events:

```prolog
?- qhdc:event(LogicalTime, InstanceId, EventType, Data).
```

This shows every state change and transfer-related event captured during the simulation.

Ask for the state visible at a logical time:

```prolog
?- qhdc:state_at(time(0, produce), State).
```

This returns the instances and events that existed up to that logical point.

Replay events from a chosen logical time:

```prolog
?- qhdc:rewind_to(time(0, execute)).
?- qhdc:replay_from(time(0, execute)).
```

Use this when you want a readable replay of what happened after a specific phase.

Write a replay log to disk:

```prolog
?- qhdc:qhdc_replay('/tmp/qhdc_replay.pl').
```

This writes every event as a Prolog fact that can be inspected later.

### 8. Run from a saved logical point

```prolog
?- qhdc:run_from(time(0, execute), InstanceId, Outputs).
```

This accepts a logical time argument, re-runs one instance, and returns the produced output bindings.

### 9. Garbage collect completed instances

```prolog
?- qhdc:qhdc_gc.
```

This removes instances whose state is `completed` or `failed`.

### 10. Measure logical and wall-clock execution duration

```prolog
?- qhdc:qhdc_logical_duration(ExecutionId, LogicalDuration).
?- qhdc:simulation_wall_time(ExecutionId, WallSeconds).
```

- `qhdc_logical_duration/2` reports the logical duration model used by the simulator
- `simulation_wall_time/2` reports the measured wall-clock runtime between execution start and finish

### 11. Work with parameter packets and the simulated carrier

Build a packet explicitly:

```prolog
?- qhdc:qhdc_make_packet(i_src, i_dst, p1, hello(world),
                         time(0, transfer), PacketId, Packet).
```

This packages one logical parameter transfer and attaches its checksum.

Send the packet through the carrier:

```prolog
?- qhdc:carrier_send(simulated_16k_br, Packet).
```

Receive the packet from the carrier:

```prolog
?- qhdc:carrier_receive(simulated_16k_br, Packet).
```

Verify the checksum:

```prolog
?- qhdc:carrier_verify(Packet).
```

Send and receive in one higher-level step:

```prolog
?- qhdc:qhdc_transfer(i_src, i_dst, p1, hello(world),
                      time(0, transfer), PacketId).
```

Or receive via the QHDC helper that records integrity failures:

```prolog
?- qhdc:qhdc_receive_packet(simulated_16k_br, Packet).
```

The exported fact

```prolog
?- qhdc:parameter_packet(PacketId, Source, Destination,
                         Parameter, Value, Checksum, LogicalTime).
```

lets you inspect every packet that has been constructed.

### 12. Project values into and out of simple carriers

```prolog
?- qhdc:bag_project([v(1)-10, v(2)-20], CarrierRepresentation).
?- qhdc:bag_read(CarrierRepresentation, Parameters).
```

These commands copy parameter lists into and out of a carrier representation.

```prolog
?- qhdc:mind_project(i_demo, [v(1)-10], Signal).
?- qhdc:mind_read(Signal, Parameters).
```

These are the matching mind-level wrappers built on top of the bag helpers.

### 13. Register, look up, run, and remove code in the aether registry

Register versioned code payloads:

```prolog
?- qhdc:aether_register(code_math, [double/2]).
?- qhdc:aether_register(code_math, [double/2, add_one/2]).
```

Each registration creates a new versioned `registered_code/4` fact.

Inspect the registry:

```prolog
?- qhdc:registered_code(CodeId, Version, Hash, Code).
```

Look up the newest code payload:

```prolog
?- qhdc:aether_lookup(code_math, Code).
```

To execute through `aether_run/4`, use a predicate that is callable in the current Prolog environment:

```prolog
?- qhdc:aether_register(code_member, [member/2]).
?- qhdc:aether_run(code_member, member, [a, [a,b,c]], Result).
```

This executes the predicate and returns an `execution_result(...)` term containing the code id, version, hash, and resolved goal.

Unregister all versions:

```prolog
?- qhdc:aether_unregister(code_math).
```

### 14. Compare normal Prolog execution with QHDC execution

```prolog
?- qhdc:compare_ssi_qhdc([], plunit_qhdc:pipeline(5, X), Report).
```

This runs the same query both ways and returns a report dict describing whether the success behavior matches.

### 15. Check exported invariants and failure facts

Invariant checks:

```prolog
?- qhdc:correct_code(InstanceId).
?- qhdc:correct_parameters(InstanceId).
?- qhdc:correct_time(InstanceId).
?- qhdc:correct_parent(InstanceId).
?- qhdc:correct_continuation(InstanceId).
```

These predicates validate internal assumptions about compiled instances.

Failure and audit facts:

```prolog
?- qhdc:instance_failed(InstanceId, Reason).
?- qhdc:transfer_failed(PacketId, Reason).
?- qhdc:code_lookup_failed(CodeId).
?- qhdc:causality_error(Event).
?- qhdc:integrity_error(Packet).
?- qhdc:commit(Id, Data, Metadata).
```

These facts let you inspect recorded failure conditions and audit-style state after experiments.

### 16. Query exported constants

```prolog
?- qhdc:qhdc_memory_model(Model).
?- qhdc:carrier(CarrierName).
```

These expose the simulator's currently declared memory model and carrier name.

## Exported predicate reference

### Execution and lifecycle

| Predicate | What it does |
| --- | --- |
| `qhdc_memory_model/1` | Returns the declared QHDC memory model |
| `qhdc_trace/1` | Sets the trace mode |
| `qhdc_reset/0` | Clears all runtime state |
| `qhdc_compile/2` | Compiles a goal into an execution id |
| `qhdc_run/2` | Compiles and runs a goal |
| `qhdc_create_instance/4` | Creates one instance manually |
| `qhdc_load_instance/1` | Moves an instance into a runnable state |
| `qhdc_run_instance/1` | Executes one instance |
| `qhdc_complete_instance/1` | Marks one instance completed |
| `qhdc_delete_instance/1` | Deletes one instance's runtime records |
| `qhdc_serialize_instance/2` | Serializes one instance term |
| `qhdc_restore_instance/1` | Restores one serialized instance |
| `qhdc_gc/0` | Deletes completed or failed instances |

### Transfers and carriers

| Predicate | What it does |
| --- | --- |
| `qhdc_transfer/6` | Performs a complete parameter transfer |
| `qhdc_make_packet/7` | Creates a packet and checksum |
| `qhdc_receive_packet/2` | Receives and validates a packet |
| `parameter_packet/7` | Stores created packet facts |
| `carrier/1` | Returns the carrier identifier |
| `carrier_send/2` | Enqueues a packet on the carrier |
| `carrier_receive/2` | Dequeues a packet from the carrier |
| `carrier_verify/1` | Verifies a packet checksum |
| `bag_project/2` | Projects parameters into a carrier representation |
| `bag_read/2` | Reads parameters from a carrier representation |
| `mind_project/3` | Mind-level projection wrapper |
| `mind_read/2` | Mind-level read wrapper |

### Aether code registry

| Predicate | What it does |
| --- | --- |
| `aether_register/2` | Adds a versioned code payload |
| `aether_unregister/1` | Removes all versions for a code id |
| `aether_lookup/2` | Returns the latest code payload |
| `aether_run/4` | Executes a registered predicate |
| `registered_code/4` | Exposes registry facts |

### Time, replay, and inspection

| Predicate | What it does |
| --- | --- |
| `event/4` | Exposes recorded events |
| `state_at/2` | Returns the visible state at a logical time |
| `run_from/3` | Runs an instance from a chosen time anchor |
| `rewind_to/1` | Sets the replay rewind point |
| `replay_from/1` | Replays events from a logical time |
| `qhdc_replay/1` | Writes replay facts to a file |
| `qhdc_logical_duration/2` | Returns logical duration |
| `simulation_wall_time/2` | Returns wall-clock runtime |
| `depends/3` | Exposes inter-instance dependencies |
| `compare_ssi_qhdc/3` | Compares plain Prolog and QHDC execution |

### Validation, state, and audit facts

| Predicate | What it does |
| --- | --- |
| `correct_code/1` | Checks code reference presence |
| `correct_parameters/1` | Checks input and output list structure |
| `correct_time/1` | Checks logical time shape |
| `correct_parent/1` | Checks parent consistency |
| `correct_continuation/1` | Checks execution membership |
| `qhdc_instance/9` | Exposes full instance state |
| `instance_failed/2` | Records instance failures |
| `transfer_failed/2` | Records transfer failures |
| `code_lookup_failed/1` | Records failed code lookups |
| `causality_error/1` | Exposes causality errors |
| `integrity_error/1` | Exposes integrity errors |
| `commit/3` | Exposes commit facts |
