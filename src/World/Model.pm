#########################################################################
#  OpenKore - World::Model
#
#  Canonical read model for runtime world state. This module deliberately
#  has no dependency on Globals, networking, AI, plugins or agent code.
#  Legacy state is fed into it by World::LegacyBridge; new subsystems can
#  consume this model directly and migrate away from Globals incrementally.
#########################################################################
package World::Model;

use strict;
use warnings;
use Time::HiRes qw(time);
use Scalar::Util qw(weaken blessed refaddr);

my @ACTOR_CATEGORIES = qw(monsters players npcs items portals pets slaves elementals);

my %state;

sub _empty_actor_sets {
	return map { $_ => {} } @ACTOR_CATEGORIES;
}

sub reset {
	%state = (
		schema_version => 1,
		generation     => 0,
		updated_at     => time(),
		self           => undef,
		map            => undef,
		connection     => {},
		tasks          => undef,
		actors         => { _empty_actor_sets() },
	);
	return 1;
}

reset();

sub _touch {
	$state{generation}++;
	$state{updated_at} = time();
}

sub generation {
	return $state{generation};
}

sub updatedAt {
	return $state{updated_at};
}

sub actorCategories {
	return [@ACTOR_CATEGORIES];
}

sub _valid_category {
	my ($category) = @_;
	return 0 if !defined $category;
	for my $known (@ACTOR_CATEGORIES) {
		return 1 if $known eq $category;
	}
	return 0;
}

sub _actor_key {
	my ($actor_or_id) = @_;
	return undef if !defined $actor_or_id;
	if (ref($actor_or_id)) {
		return undef if !exists $actor_or_id->{ID} || !defined $actor_or_id->{ID};
		return $actor_or_id->{ID};
	}
	return $actor_or_id;
}

sub upsertActor {
	my ($category, $actor) = @_;
	die "Unknown world-model actor category '$category'\n" if !_valid_category($category);
	return 0 if !$actor || !ref($actor);

	my $key = _actor_key($actor);
	return 0 if !defined $key;

	my $old = $state{actors}{$category}{$key};
	$state{actors}{$category}{$key} = $actor;
	weaken($state{actors}{$category}{$key}) if ref($state{actors}{$category}{$key});

	# Replacing the exact same actor reference does not constitute a structural
	# world-model change. The object itself is live, so field mutations remain
	# visible to readers without copying data on every packet.
	if (!$old || !defined($old) || refaddr($old) != refaddr($actor)) {
		_touch();
	}
	return 1;
}

sub removeActor {
	my ($category, $actor_or_id) = @_;
	die "Unknown world-model actor category '$category'\n" if !_valid_category($category);
	my $key = _actor_key($actor_or_id);
	return 0 if !defined $key || !exists $state{actors}{$category}{$key};
	delete $state{actors}{$category}{$key};
	_touch();
	return 1;
}

sub clearActors {
	my ($category) = @_;
	if (defined $category) {
		die "Unknown world-model actor category '$category'\n" if !_valid_category($category);
		my $had = scalar keys %{$state{actors}{$category}};
		$state{actors}{$category} = {};
		_touch() if $had;
		return 1;
	}

	my $had = 0;
	for my $known (@ACTOR_CATEGORIES) {
		$had ||= scalar keys %{$state{actors}{$known}};
		$state{actors}{$known} = {};
	}
	_touch() if $had;
	return 1;
}

sub setSelf {
	my ($actor) = @_;
	my $old = $state{self};

	if (!$actor) {
		if ($old) {
			$state{self} = undef;
			_touch();
		}
		return 1;
	}

	my $changed = !$old || !defined($old) || refaddr($old) != refaddr($actor);
	$state{self} = $actor;
	weaken($state{self}) if ref($state{self});
	_touch() if $changed;
	return 1;
}

sub selfActor {
	return $state{self};
}

sub setMap {
	my ($name) = @_;
	$name = undef if defined($name) && $name eq '';
	my $old = $state{map};
	my $same = (!defined($old) && !defined($name))
		|| (defined($old) && defined($name) && $old eq $name);
	if (!$same) {
		$state{map} = $name;
		_touch();
	}
	return 1;
}

sub mapName {
	return $state{map};
}

sub setConnection {
	my (%connection) = @_;
	my $old = $state{connection} || {};
	my $changed = 0;
	my %next;
	for my $key (qw(state server_alive)) {
		next if !exists $connection{$key};
		$next{$key} = $connection{$key};
		$changed = 1 if !exists($old->{$key})
			|| (!defined($old->{$key}) xor !defined($next{$key}))
			|| (defined($old->{$key}) && defined($next{$key}) && $old->{$key} ne $next{$key});
	}
	for my $key (keys %{$old}) {
		$changed = 1 if !exists $next{$key};
	}
	$state{connection} = \%next;
	_touch() if $changed;
	return 1;
}

sub setTasks {
	my ($tasks) = @_;
	$tasks = undef if defined($tasks) && ref($tasks) ne 'HASH';
	my $old = $state{tasks};
	my $signature = defined($tasks)
		? join("\x1e", map { defined($tasks->{$_}) ? $tasks->{$_} : '' } qw(active inactive mutexes))
		: '';
	my $old_signature = defined($old)
		? join("\x1e", map { defined($old->{$_}) ? $old->{$_} : '' } qw(active inactive mutexes))
		: '';
	if ($signature ne $old_signature || (defined($tasks) xor defined($old))) {
		$state{tasks} = $tasks ? { %{$tasks} } : undef;
		_touch();
	}
	return 1;
}

sub actorRef {
	my ($category, $id) = @_;
	return undef if !_valid_category($category) || !defined $id;
	return $state{actors}{$category}{$id};
}

sub actorRefs {
	my ($category) = @_;
	die "Unknown world-model actor category '$category'\n" if !_valid_category($category);
	my @actors;
	for my $key (keys %{$state{actors}{$category}}) {
		my $actor = $state{actors}{$category}{$key};
		if ($actor) {
			push @actors, $actor;
		} else {
			delete $state{actors}{$category}{$key};
		}
	}
	return \@actors;
}

sub findActorByName {
	my ($name, @categories) = @_;
	return undef if !defined $name;
	@categories = @ACTOR_CATEGORIES if !@categories;
	for my $category (@categories) {
		next if !_valid_category($category);
		for my $actor (@{actorRefs($category)}) {
			next if !defined $actor->{name};
			return $actor if lc($actor->{name}) eq lc($name);
		}
	}
	return undef;
}

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
	return undef if !$hash || !exists $hash->{$key};
	my $value = $hash->{$key};
	return undef if ref($value);
	return $value;
}

sub actorSnapshot {
	my ($actor) = @_;
	return undef if !$actor;

	my %result;
	if (defined $actor->{ID} && !ref($actor->{ID})) {
		$result{id} = unpack('H*', $actor->{ID});
	}
	for my $key (qw(actorType name nameID type lv lv_job hp hp_max sp sp_max ap ap_max zeny weight weight_max)) {
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

sub _category_snapshot {
	my ($category, $limit, $origin) = @_;
	my @entries;
	for my $actor (@{actorRefs($category)}) {
		my $entry = actorSnapshot($actor);
		push @entries, $entry if $entry;
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
	my $self = actorSnapshot($state{self});
	my $origin = $self ? $self->{position} : undef;

	my %actors;
	for my $category (@ACTOR_CATEGORIES) {
		$actors{$category} = _category_snapshot($category, $limit, $origin);
	}

	return {
		schema_version => $state{schema_version},
		generation     => $state{generation},
		updated_at     => $state{updated_at},
		captured_at    => time(),
		connection     => { %{$state{connection} || {}} },
		map            => defined($state{map}) ? { name => $state{map} } : undef,
		self           => $self,
		tasks          => $state{tasks} ? { %{$state{tasks}} } : undef,
		actors         => \%actors,
	};
}

1;
