# Agent Gateway

The Agent Gateway adds an event-driven escalation boundary between OpenKore's deterministic runtime and a slower deliberative agent.

The core design rule is: **OpenKore keeps acting; the external agent is only asked when OpenKore reaches a decision boundary or an exception it cannot resolve deterministically.**

## Architecture

```text
External agent
     ^   |
     |   | decision
     |   v
Agent::Gateway
     ^   |
     |   | callbacks / intents
     |   v
OpenKore tasks, AI and plugins
     |
     v
Ragnarok environment
```

`Agent::Gateway` does not depend on `Globals`, Bus, JSON, HTTP, WebSocket, or a specific model. It emits OpenKore plugin hooks. `Agent::WorldState` is the only compatibility adapter that reads legacy global state and turns it into plain agent-facing data.

This intentionally isolates the old global-state architecture instead of spreading it into new agent code.

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

## World-state boundary

By default a request gets a snapshot from `Agent::WorldState`. The snapshot contains plain Perl hashes/arrays/scalars with connection state, map, self, TaskManager summary and nearby actors.

Agent-facing code should **not** import `Globals`. If more world information is required, add it to `Agent::WorldState` instead. That preserves one explicit compatibility boundary around the legacy global-state architecture.

A caller may also provide a purpose-built context directly:

```perl
Agent::Gateway::request(
    reason  => 'ambiguous_dialog',
    context => { dialog => \@options },
);
```

## Execution model

The gateway never blocks the OpenKore main loop. A pending request is simply state. Reflexes, network processing, combat safety logic and unrelated tasks continue normally while the external agent deliberates.

Timeouts are checked from `mainLoop_pre` by this plugin. A request can therefore wait asynchronously without polling the complete OpenKore state from the agent side.

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
