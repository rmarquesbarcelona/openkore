#########################################################################
# OpenKore world model lifecycle plugin
#
# Installs the strangler compatibility bridge from legacy Globals/ActorLists
# into the Globals-independent World::Model. This lifecycle is deliberately
# separate from agentGateway: World::Model is infrastructure for all new
# OpenKore code, not an agent-specific feature.
#########################################################################
package worldModel;

use strict;
use warnings;
use Plugins;
use World::LegacyBridge;

Plugins::register(
	'worldModel',
	'Globals-independent runtime world model and legacy compatibility bridge',
	\&onUnload,
	\&onReload,
);

# Actor collections are synchronized by ActorList callbacks registered by the
# bridge. Runtime scalars are cheap to synchronize once per loop and again at
# the beginning of AI deliberation, so consumers see a fresh map/self/network
# view before strategic decisions are made.
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
}

sub onUnload {
	Plugins::delHooks($hooks) if $hooks;
	World::LegacyBridge::shutdown() if World::LegacyBridge::isInitialized();
}

sub onReload {
	onUnload();
}

1;
