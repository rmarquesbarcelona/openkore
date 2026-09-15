# Unit tests for the Globals-independent core world model.
package WorldModelTest;

use strict;
use warnings;
use Test::More;
use World::Model;

sub start {
	print "### Starting WorldModelTest\n";
	testRuntimeState();
	testActorRegistry();
	testSnapshotOrderingAndLimits();
	testLiveActorReferences();
}

sub actor {
	my (%args) = @_;
	my $id = pack('V', $args{id});
	return bless {
		ID        => $id,
		actorType => $args{type} || 'Monster',
		name      => $args{name},
		pos_to    => { x => $args{x} || 0, y => $args{y} || 0 },
		hp        => defined($args{hp}) ? $args{hp} : 100,
		hp_max    => defined($args{hp_max}) ? $args{hp_max} : 100,
	}, 'WorldModelTest::Actor';
}

sub testRuntimeState {
	World::Model::reset();
	my $self = actor(id => 1, type => 'You', name => 'Self', x => 10, y => 20);
	World::Model::setSelf($self);
	World::Model::setMap('prontera');
	World::Model::setConnection(state => 5, server_alive => 1);
	World::Model::setTasks({ active => 'A', inactive => '-', mutexes => 'movement (<- A)' });

	my $snapshot = World::Model::snapshot();
	is($snapshot->{map}{name}, 'prontera', 'map is stored outside Globals');
	is($snapshot->{self}{name}, 'Self', 'self actor is exposed through the model');
	is($snapshot->{connection}{state}, 5, 'connection state is represented');
	is($snapshot->{connection}{server_alive}, 1, 'server liveness is represented');
	is($snapshot->{tasks}{active}, 'A', 'task summary is represented');
	ok($snapshot->{generation} > 0, 'model generation advances on structural changes');
}

sub testActorRegistry {
	World::Model::reset();
	my $poring = actor(id => 100, name => 'Poring', x => 5, y => 5);
	my $lunatic = actor(id => 101, name => 'Lunatic', x => 8, y => 8);

	ok(World::Model::upsertActor('monsters', $poring), 'actor can be registered');
	ok(World::Model::upsertActor('monsters', $lunatic), 'second actor can be registered');
	is(scalar @{World::Model::actorRefs('monsters')}, 2, 'registry contains both actors');
	is(World::Model::findActorByName('poring', 'monsters'), $poring, 'lookup by name is case-insensitive');

	ok(World::Model::removeActor('monsters', $poring), 'actor can be removed');
	is(scalar @{World::Model::actorRefs('monsters')}, 1, 'removal updates registry');
	World::Model::clearActors('monsters');
	is(scalar @{World::Model::actorRefs('monsters')}, 0, 'category can be cleared');
}

sub testSnapshotOrderingAndLimits {
	World::Model::reset();
	my $self = actor(id => 1, type => 'You', name => 'Self', x => 0, y => 0);
	my $far = actor(id => 11, name => 'Far', x => 20, y => 20);
	my $near = actor(id => 12, name => 'Near', x => 1, y => 1);
	my $middle = actor(id => 13, name => 'Middle', x => 5, y => 5);
	World::Model::setSelf($self);
	World::Model::upsertActor('monsters', $far);
	World::Model::upsertActor('monsters', $near);
	World::Model::upsertActor('monsters', $middle);

	my $snapshot = World::Model::snapshot(actor_limit => 2);
	is($snapshot->{actors}{monsters}{total_count}, 3, 'snapshot reports total actor count');
	ok($snapshot->{actors}{monsters}{truncated}, 'snapshot marks a limited collection as truncated');
	is(scalar @{$snapshot->{actors}{monsters}{items}}, 2, 'actor limit is applied');
	is($snapshot->{actors}{monsters}{items}[0]{name}, 'Near', 'nearest actor is returned first');
}

sub testLiveActorReferences {
	World::Model::reset();
	my $monster = actor(id => 99, name => 'Mutable', x => 2, y => 3, hp => 100);
	World::Model::upsertActor('monsters', $monster);
	my $generation = World::Model::generation();

	$monster->{hp} = 42;
	$monster->{pos_to}{x} = 9;
	my $snapshot = World::Model::snapshot();
	is($snapshot->{actors}{monsters}{items}[0]{hp}, 42, 'field mutations are visible without copying every packet');
	is($snapshot->{actors}{monsters}{items}[0]{position}{x}, 9, 'position mutations are visible through live actor reference');
	is(World::Model::generation(), $generation, 'structural generation intentionally ignores live actor field churn');
}

1;