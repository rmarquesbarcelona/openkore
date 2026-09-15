#########################################################################
# OpenKore agent gateway lifecycle plugin
#
# Keeps Agent::Gateway transport-agnostic while giving it a main-loop tick.
# World::LegacyBridge is the isolated compatibility edge from Globals into
# the new core World::Model.
#########################################################################
package agentGateway;

use strict;
use warnings;
use Plugins;
use Agent::Gateway;
use World::LegacyBridge;

Plugins::register(
	'agentGateway',
	'Event-driven escalation boundary for external deliberative agents',
	\&onUnload,
	\&onReload,
);

# Actor collections are synchronized by ActorList callbacks registered by the
# legacy bridge. Runtime scalars (self/map/connection/task summary) are synced
# at decision-relevant boundaries. Deadline processing stays in mainLoop_post,
# after Bus input, so a queued agent response wins over a same-tick timeout.
my $hooks = Plugins::addHooks(
	['initialized', \&onInitialized, undef],
	['AI_start', \&onDecisionBoundary, undef],
	['Network::Receive::map_changed', \&onDecisionBoundary, undef],
	['mainLoop_post', \&onMainLoopPost, undef],
);

sub onInitialized {
	World::LegacyBridge::initialize();
}

sub onDecisionBoundary {
	World::LegacyBridge::syncRuntime() if World::LegacyBridge::isInitialized();
}

sub onMainLoopPost {
	World::LegacyBridge::syncRuntime() if World::LegacyBridge::isInitialized();
	Agent::Gateway::iterate();
}

sub onUnload {
	Plugins::delHooks($hooks) if $hooks;
	World::LegacyBridge::shutdown() if World::LegacyBridge::isInitialized();
	Agent::Gateway::reset();
}

sub onReload {
	onUnload();
}

1;
