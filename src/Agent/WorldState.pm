#########################################################################
#  OpenKore - Agent world-state adapter
#
#  This module is the deliberate compatibility boundary around Globals.
#  Agent-facing code should consume the plain-data snapshot returned here
#  instead of reading OpenKore global variables directly.
#########################################################################
package Agent::WorldState;

use strict;
use warnings;
use Time::HiRes qw(time);
use Globals qw(
	$char $field $net $taskManager
	$monstersList $playersList $npcsList $itemsList $portalsList
	$petsList $slavesList $elementalsList
);

sub _position {
	my ($actor) = @_;
	return undef if !$actor;
	my $pos = $actor->{pos_to} || $actor->{pos};
	return undef if ref($pos) ne 'HASH';
	return undef if !defined($pos->{x}) || !defined($pos->{y});
	return { x => 0 + $pos->{x}, y => 0 + $pos->{y} };
}

sub _safe_scalar {
	my ($hash, $key) = @_;
	return undef if !exists $hash->{$key};
	my $value = $hash->{$key};
	return undef if ref($value);
	return $value;
}

sub _actor_snapshot {
	my ($actor) = @_;
	return undef if !$actor;

	my %result;
	if (defined $actor->{ID} && !ref($actor->{ID})) {
		$result{id} = unpack('H*', $actor->{ID});
	}
	for my $key (qw(actorType name nameID type lv lv_job hp hp_max sp sp_max zeny weight weight_max)) {
		my $value = _safe_scalar($actor, $key);
		$result{$key} = $value if defined $value;
	}
	my $pos = _position($actor);
	$result{position} = $pos if $pos;
	return \%result;
}

sub _distance2 {
	my ($entry, $origin) = @_;
	return 9e18 if !$origin || !$entry->{position};
	my $dx = $entry->{position}{x} - $origin->{x};
	my $dy = $entry->{position}{y} - $origin->{y};
	return ($dx * $dx) + ($dy * $dy);
}

sub _list_snapshot {
	my ($list, $limit, $origin) = @_;
	$limit = 64 if !defined $limit;
	my @entries;

	if ($list) {
		for my $actor (@{$list}) {
			my $entry = _actor_snapshot($actor);
			push @entries, $entry if $entry;
		}
	}

	@entries = sort { _distance2($a, $origin) <=> _distance2($b, $origin) } @entries;
	my $total = scalar @entries;
	if ($limit >= 0 && @entries > $limit) {
		splice @entries, $limit;
	}

	return {
		total_count => $total,
		truncated   => $total > scalar(@entries) ? 1 : 0,
		items       => \@entries,
	};
}

sub snapshot {
	my %options = @_;
	my $limit = exists($options{actor_limit}) ? $options{actor_limit} : 64;
	my $self = _actor_snapshot($char);
	my $origin = $self ? $self->{position} : undef;

	my $map;
	if ($field) {
		my $name = eval { $field->name };
		$map = { name => $name } if defined $name;
	}

	my $connection = {};
	if ($net) {
		my $state = eval { $net->getState() };
		$connection->{state} = $state if defined $state;
		my $alive = eval { $net->serverAlive() };
		$connection->{server_alive} = $alive ? 1 : 0 if defined $alive;
	}

	my $tasks;
	if ($taskManager) {
		$tasks = {
			active   => eval { $taskManager->activeTasksString() } || '-',
			inactive => eval { $taskManager->inactiveTasksString() } || '-',
			mutexes  => eval { $taskManager->activeMutexesString() } || '',
		};
	}

	return {
		schema_version => 1,
		captured_at    => time(),
		connection     => $connection,
		map            => $map,
		self           => $self,
		tasks          => $tasks,
		actors         => {
			monsters   => _list_snapshot($monstersList, $limit, $origin),
			players    => _list_snapshot($playersList, $limit, $origin),
			npcs       => _list_snapshot($npcsList, $limit, $origin),
			items      => _list_snapshot($itemsList, $limit, $origin),
			portals    => _list_snapshot($portalsList, $limit, $origin),
			pets       => _list_snapshot($petsList, $limit, $origin),
			slaves     => _list_snapshot($slavesList, $limit, $origin),
			elementals => _list_snapshot($elementalsList, $limit, $origin),
		},
	};
}

1;
