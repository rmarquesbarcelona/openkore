# Unit tests for the isolated Globals -> World::Model compatibility bridge.
package WorldLegacyBridgeTest;

use strict;
use warnings;
use Test::More;
use Globals qw(
	$char $field $net $taskManager
	$monstersList $playersList $npcsList $itemsList $portalsList
	$petsList $slavesList $elementalsList
);
use ActorList;
use Actor::Monster;
use World::Model;
use World::LegacyBridge;

sub start {
	print "### Starting WorldLegacyBridgeTest\n";
	testActorListEventsFeedModel();
}

sub testActorListEventsFeedModel {
	World::LegacyBridge::shutdown() if World::LegacyBridge::isInitialized();

	local $char = undef;
	local $field = undef;
	local $net = undef;
	local $taskManager = undef;
	local $monstersList = ActorList->new('Actor::Monster');
	local $playersList = undef;
	local $npcsList = undef;
	local $itemsList = undef;
	local $portalsList = undef;
	local $petsList = undef;
	local $slavesList = undef;
	local $elementalsList = undef;

	ok(World::LegacyBridge::initialize(), 'legacy bridge initializes');
	is(scalar @{World::Model::actorRefs('monsters')}, 0, 'model starts with empty monster registry');

	my $monster = Actor::Monster->new();
	$monster->{ID} = pack('V', 1234);
	$monster->{name} = 'Bridge Poring';
	$monster->{pos_to} = { x => 4, y => 7 };
	$monstersList->add($monster);

	is(scalar @{World::Model::actorRefs('monsters')}, 1, 'ActorList add event feeds world model');
	is(World::Model::findActorByName('Bridge Poring', 'monsters'), $monster, 'bridge keeps the live actor object');

	$monstersList->remove($monster);
	is(scalar @{World::Model::actorRefs('monsters')}, 0, 'ActorList remove event feeds world model');

	$monstersList->add($monster);
	$monstersList->clear();
	is(scalar @{World::Model::actorRefs('monsters')}, 0, 'ActorList clear event clears world-model category');

	ok(World::LegacyBridge::shutdown(), 'legacy bridge shuts down cleanly');
}

1;
