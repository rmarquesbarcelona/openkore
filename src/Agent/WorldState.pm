#########################################################################
#  OpenKore - Agent world-state facade
#
#  Agent-facing code consumes World::Model instead of legacy Globals.
#  World::LegacyBridge is responsible for compatibility with the old runtime.
#########################################################################
package Agent::WorldState;

use strict;
use warnings;
use World::Model;

sub snapshot {
	return World::Model::snapshot(@_);
}

sub generation {
	return World::Model::generation();
}

1;
