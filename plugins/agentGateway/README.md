# Agent Gateway

The Agent Gateway adds an event-driven escalation boundary between OpenKore's deterministic runtime and a slower deliberative agent.

The core design rule is: **OpenKore keeps acting; the external agent is only asked when OpenKore reaches a decision boundary or an exception it cannot resolve deterministically.**

## Architecture

```text
                          External agent
                               ^   |
                       request |   | decision
                               |   v
                        Agent::Gateway
                               ^
                               |
                        Agent::WorldState
                               |
                               v
                         World::Model
                         ^           ^
                         |           |
             legacy compatibility   | new code reads here
                         |
                  World::LegacyBridge
                         ^
                         |
                      Globals
                         ^
                         |
              existing OpenKore core
```

`Agent::Gateway` does not depend on `Globals`, Bus, JSON, HTTP, WebSocket, or a particular model provider.

More importantly, agent work is no longer the only reason for the new world-state layer. `World::Model` is a **core read model** with no dependency on `Globals`, networking, AI, plugins or agent code. It is intended to become the common state-query surface for new OpenKore code as legacy consumers are migrated.

`World::LegacyBridge` is the compatibility edge. It is deliberately the only new world-model module that imports `Globals`.

The dependency rule is therefore:

```text
GOOD
legacy state -> World::LegacyBridge -> World::Model -> consumers

BAD
consumer -> Globals
```

The bridge subscribes directly to the existing `ActorList` add/remove/clear events. `World::Model` keeps weak references to the live Actor objects, so ordinary actor mutations such as movement, HP and names remain visible without copying the entire world on every packet. Runtime scalars such as current map, connection state and TaskManager summary are synchronized at decision-relevant lifecycle boundaries.

This turns the old global-state architecture into a compatibility source instead of a dependency that new code must inherit.

## World-model migration rule

New code that needs world information should use `World::Model`, not `Globals`.

Examples:

```perl
use World::Model;

my $snapshot = World::Model::snapshot(actor_limit => 32);
my $poring = World::Model::findActorByName('Poring', 'monsters');
my $monsters = World::Model::actorRefs('monsters');
```

If a piece of legacy state is not yet represented in the model, extend `World::Model` and feed it through `World::LegacyBridge`. Do not add another direct `Globals` dependency to agent/new architecture code.

`World::Model::generation()` is a structural/runtime generation counter. Actor objects are intentionally live references, so high-frequency field changes do not increment that counter; a fresh `snapshot()` always reads the current actor fields.

## Escalating a decision

```perl
use Agent::Gateway;

my $request_id = Agent::Gateway::request(
    type    => 'task_blocked',
    urgency => 'normal',
    reason  => 'expected_npc_not_found',
    timeout => 10,
    goal => {
        action   => 'buy_item',
        item     => 'Blue Gemstone',
        quantity => 50,
    },
    current_task => {
        action => 'interact_npc',
        npc    => 'Magical Item Seller',
    },
    history => [
        'navigated to expected location',
        'searched nearby area',
    ],
    allowed_actions => [
        'search_map',
        'change_goal',
        'abort_task',
    ],
    on_resolve => sub {
        my ($decision, $request) = @_;
        # Translate the agent decision into deterministic OpenKore actions.
    },
    fallback => sub {
        my ($request) = @_;
        # Safe deterministic behavior if the agent does not answer in time.
    },
);
```

If the situation resolves itself before the agent answers:

```perl
Agent::Gateway::cancel($request_id, 'npc_appeared');
```

A transport or agent adapter answers with:

```perl
Agent::Gateway::resolve($request_id, {
    action => 'search_map',
    radius => 40,
});
```

## TaskManager integration

`Task::AgentDecision` wraps the same request lifecycle as a cooperative OpenKore task. It can hold only a strategic mutex while the agent thinks, leaving network handling, reflexes, combat safety and unrelated tasks free to continue.

```perl
use Task::AgentDecision;

my $decision_task = Task::AgentDecision->new(
    mutexes => ['strategy'],
    request => {
        type    => 'task_blocked',
        reason  => 'route_strategy_exhausted',
        timeout => 10,
    },
    fallback => sub {
        return { action => 'safe_abort' };
    },
);

$taskManager->add($decision_task);
```

When the external answer arrives, the task stores the decision and finishes on its next normal `TaskManager` iteration. If the deadline expires without a fallback, the task finishes with the explicit `agent_timeout` error. Stopping the task cancels its still-pending agent request.

This is the intended mechanism for suspending **strategic** work without freezing OpenKore itself.

## Hooks

A transport subscribes to these hooks:

- `agent/request` — a decision is required.
- `agent/notify` — informational event; no response required.
- `agent/resolved` — a request was resolved.
- `agent/cancelled` — the situation stopped being relevant.
- `agent/timeout` — deadline expired and fallback was invoked.
- `agent/context_error` — world-state snapshot generation failed.

A transport only needs to forward `agent/request` outward and call `Agent::Gateway::resolve()` when a decision comes back. This allows Bus, WebSocket, JSON-RPC, HTTP, local models, remote LLMs or test agents without changing the OpenKore core.

## Notifications

For decision boundaries that do not require an answer:

```perl
Agent::Gateway::notify(
    type => 'objective_completed',
    payload => { objective => 'reach_prontera' },
);
```

## Agent world-state facade

By default a request gets a snapshot from `Agent::WorldState`. That module no longer imports `Globals`; it delegates to the core `World::Model`.

A caller may also provide a purpose-built context directly:

```perl
Agent::Gateway::request(
    reason  => 'ambiguous_dialog',
    context => { dialog => \@options },
);
```

## Execution model

The gateway never blocks the OpenKore main loop. A pending request is simply state. Reflexes, network processing, combat safety logic and unrelated tasks continue normally while the external agent deliberates.

Timeouts are checked from `mainLoop_post` by this plugin. That ordering is deliberate: inbound Bus messages are processed first, so a response already waiting on the transport can resolve the request before its deadline is evaluated in the same loop iteration.

## Optional Bus transport

`busTransport.pl` adapts the gateway to OpenKore's existing Bus when Bus is enabled. The gateway itself remains unaware of Bus.

Because the legacy Bus only transports scalar key/value arguments, the adapter places the structured agent envelope in a JSON string named `payload` and adds:

```text
protocol = openkore-agent-v1
```

OpenKore broadcasts these Bus message IDs:

- `AGENT_REQUEST`
- `AGENT_NOTIFY`
- `AGENT_CANCELLED`
- `AGENT_TIMEOUT`

An external agent resolves a request by sending `AGENT_RESOLVE` with the same protocol field and a JSON payload shaped like:

```json
{
  "request_id": "agent-...",
  "decision": {
    "action": "search_map",
    "radius": 40
  }
}
```

`JSON::PP` is loaded optionally by the transport. If it is unavailable, only the Bus adapter is disabled; `Agent::Gateway` and in-process transports continue to work normally.

## Tests and CI

The branch contains focused tests for the pure world model, the legacy ActorList bridge, gateway request lifecycle and TaskManager decision integration. A small `Agent architecture` workflow also syntax-checks the Globals-independent boundary on Perl 5.12 and current Perl.

The existing repository-wide XSTools workflow remains unchanged.