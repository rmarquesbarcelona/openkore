#########################################################################
# OpenKore agent gateway lifecycle plugin
#
# Keeps Agent::Gateway transport-agnostic while giving it a main-loop tick.
# Agent transports should subscribe to agent/request, agent/notify,
# agent/cancelled, agent/timeout and call Agent::Gateway::resolve().
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

my $hooks = Plugins::addHooks(
	['mainLoop_pre', \&onMainLoop, undef],
);

sub onMainLoop {
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
