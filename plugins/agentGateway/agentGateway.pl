#########################################################################
# OpenKore agent gateway lifecycle plugin
#
# Keeps Agent::Gateway transport-agnostic while giving it a main-loop tick.
# World::Model lifecycle is owned separately by the worldModel plugin.
#########################################################################
package agentGateway;

use strict;
use warnings;
use Plugins;
use Agent::Gateway;

Plugins::register(
	'agentGateway',
	'Event-driven escalation boundary for external deliberative agents',
	\&onUnload,
	\&onReload,
);

# Deadline processing stays in mainLoop_post, after Bus input, so a queued
# agent response wins over a same-tick timeout.
my $hooks = Plugins::addHooks(
	['mainLoop_post', \&onMainLoopPost, undef],
);

sub onMainLoopPost {
	Agent::Gateway::iterate();
}

sub onUnload {
	Plugins::delHooks($hooks) if $hooks;
	Agent::Gateway::reset();
}

sub onReload {
	onUnload();
}

1;
