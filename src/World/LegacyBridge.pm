#########################################################################
#  OpenKore - World::LegacyBridge
#
#  Compatibility bridge from OpenKore's legacy Globals-based runtime into
#  World::Model. This is intentionally the ONLY world-model module that
#  imports Globals. As legacy consumers migrate, this bridge can shrink and
#  eventually disappear without changing World::Model's public contract.
#########################################################################
package World::LegacyBridge;

use strict;
use warnings;
use Globals qw(
	$char $field $net $taskManager
	$monstersList $playersList $npcsList $itemsList $portalsList
	$petsList $slavesList $elementalsList
);
use World::Model;

my $initialized = 0;
my @subscriptions;

sub _lists {
	return (
		['monsters',   $monstersList],
		['players',    $playersList],
		['npcs',       $npcsList],
		['items',      $itemsList],
		['portals',    $portalsList],
		['pets',       $petsList],
		['slaves',     $slavesList],
		['elementals', $elementalsList],
	);
}

sub _actor_added {
	my (undef, $source, $arg, $category) = @_;
	return if ref($arg) ne 'ARRAY';
	my ($actor) = @{$arg};
	World::Model::upsertActor($category, $actor) if $actor;
}

sub _actor_removed {
	my (undef, $source, $arg, $category) = @_;
	return if ref($arg) ne 'ARRAY';
	my ($actor) = @{$arg};
	World::Model::removeActor($category, $actor) if $actor;
}

sub _actors_clearing {
	my (undef, $source, $arg, $category) = @_;
	World::Model::clearActors($category);
}

sub _subscribe_list {
	my ($category, $list) = @_;
	return if !$list;

	# Seed the model in case the bridge is initialized after actors already exist.
	for my $actor (@{$list}) {
		World::Model::upsertActor($category, $actor) if $actor;
	}

	my $add_id = $list->onAdd()->add(undef, \&_actor_added, $category);
	my $remove_id = $list->onRemove()->add(undef, \&_actor_removed, $category);
	my $clear_id = $list->onClearBegin()->add(undef, \&_actors_clearing, $category);

	push @subscriptions, {
		list      => $list,
		add_id    => $add_id,
		remove_id => $remove_id,
		clear_id  => $clear_id,
	};
}

sub initialize {
	return 1 if $initialized;
	World::Model::reset();
	for my $entry (_lists()) {
		my ($category, $list) = @{$entry};
		_subscribe_list($category, $list);
	}
	$initialized = 1;
	syncRuntime();
	return 1;
}

sub isInitialized {
	return $initialized ? 1 : 0;
}

sub syncRuntime {
	return 0 if !$initialized;

	World::Model::setSelf($char);

	my $map_name;
	if ($field) {
		$map_name = eval { $field->name };
	}
	World::Model::setMap($map_name);

	my %connection;
	if ($net) {
		my $state = eval { $net->getState() };
		$connection{state} = $state if defined $state;
		my $alive = eval { $net->serverAlive() };
		$connection{server_alive} = $alive ? 1 : 0 if defined $alive;
	}
	World::Model::setConnection(%connection);

	my $tasks;
	if ($taskManager) {
		$tasks = {
			active   => eval { $taskManager->activeTasksString() } || '-',
			inactive => eval { $taskManager->inactiveTasksString() } || '-',
			mutexes  => eval { $taskManager->activeMutexesString() } || '',
		};
	}
	World::Model::setTasks($tasks);
	return 1;
}

sub shutdown {
	for my $subscription (@subscriptions) {
		my $list = $subscription->{list};
		next if !$list;
		eval { $list->onAdd()->remove($subscription->{add_id}) if $subscription->{add_id}; };
		eval { $list->onRemove()->remove($subscription->{remove_id}) if $subscription->{remove_id}; };
		eval { $list->onClearBegin()->remove($subscription->{clear_id}) if $subscription->{clear_id}; };
	}
	@subscriptions = ();
	$initialized = 0;
	World::Model::reset();
	return 1;
}

1;
