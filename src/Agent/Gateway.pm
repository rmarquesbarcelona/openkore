#########################################################################
#  OpenKore - Agent gateway
#
#  Provides an event-driven boundary between OpenKore's deterministic core
#  and external deliberative agents. The gateway intentionally does not
#  depend on Globals, networking transports, JSON, or a particular agent.
#########################################################################
package Agent::Gateway;

use strict;
use warnings;
use Time::HiRes qw(time);
use Plugins;

my %pending;
my $sequence = 0;
my $context_provider = \&_default_context_provider;

sub _default_context_provider {
	require Agent::WorldState;
	return Agent::WorldState::snapshot();
}

sub setContextProvider {
	my ($provider) = @_;
	die "Agent context provider must be a code reference\n"
		if defined($provider) && ref($provider) ne 'CODE';
	$context_provider = $provider || \&_default_context_provider;
}

sub resetContextProvider {
	$context_provider = \&_default_context_provider;
}

sub _next_id {
	$sequence = ($sequence + 1) % 1000000000;
	return sprintf('agent-%d-%09d', int(time() * 1000), $sequence);
}

sub _copy_optional_fields {
	my ($target, $source) = @_;
	for my $key (qw(goal current_task history allowed_actions metadata payload)) {
		$target->{$key} = $source->{$key} if exists $source->{$key};
	}
}

sub request {
	my %args = @_;
	my $created_at = time();
	my $id = defined($args{id}) ? $args{id} : _next_id();
	die "Agent request ID '$id' is already pending\n" if exists $pending{$id};

	my $caller = caller;
	my $request = {
		schema_version => 1,
		id             => $id,
		type           => $args{type} || 'decision_required',
		urgency        => $args{urgency} || 'normal',
		reason         => $args{reason} || 'unspecified',
		source         => $args{source} || $caller || 'unknown',
		created_at     => $created_at,
	};

	if (defined $args{timeout}) {
		my $timeout = 0 + $args{timeout};
		$timeout = 0 if $timeout < 0;
		$request->{deadline_at} = $created_at + $timeout;
	}

	_copy_optional_fields($request, \%args);

	if (exists $args{context}) {
		$request->{context} = $args{context};
	} elsif ($context_provider) {
		my $context;
		my $ok = eval {
			$context = $context_provider->($request);
			1;
		};
		if ($ok) {
			$request->{context} = $context;
		} else {
			my $error = $@ || 'unknown context provider error';
			$request->{context_error} = "$error";
			Plugins::callHook('agent/context_error', {
				request => $request,
				error   => "$error",
			});
		}
	}

	$pending{$id} = {
		request    => $request,
		on_resolve => $args{on_resolve},
		on_timeout => $args{on_timeout},
		fallback   => $args{fallback},
	};

	Plugins::callHook('agent/request', { request => $request });
	return $id;
}

sub notify {
	my %args = @_;
	my $event = {
		schema_version => 1,
		type           => $args{type} || 'notification',
		source         => $args{source} || scalar(caller) || 'unknown',
		created_at     => time(),
	};
	_copy_optional_fields($event, \%args);
	$event->{message} = $args{message} if exists $args{message};
	Plugins::callHook('agent/notify', { event => $event });
	return $event;
}

sub resolve {
	my ($id, $decision) = @_;
	return 0 if !defined($id) || !exists $pending{$id};

	my $entry = delete $pending{$id};
	my $request = $entry->{request};
	my $callback = $entry->{on_resolve};
	$callback->($decision, $request) if ref($callback) eq 'CODE';

	Plugins::callHook('agent/resolved', {
		request  => $request,
		decision => $decision,
	});
	return 1;
}

sub cancel {
	my ($id, $reason) = @_;
	return 0 if !defined($id) || !exists $pending{$id};

	my $entry = delete $pending{$id};
	Plugins::callHook('agent/cancelled', {
		request => $entry->{request},
		reason  => defined($reason) ? $reason : 'no_longer_relevant',
	});
	return 1;
}

sub iterate {
	my $now = time();
	for my $id (keys %pending) {
		my $entry = $pending{$id};
		my $request = $entry->{request};
		next if !defined $request->{deadline_at};
		next if $now < $request->{deadline_at};

		delete $pending{$id};

		my $timeout_callback = $entry->{on_timeout};
		$timeout_callback->($request) if ref($timeout_callback) eq 'CODE';

		my $fallback = $entry->{fallback};
		$fallback->($request) if ref($fallback) eq 'CODE';

		Plugins::callHook('agent/timeout', { request => $request });
	}
}

sub getRequest {
	my ($id) = @_;
	return undef if !defined($id) || !exists $pending{$id};
	return $pending{$id}{request};
}

sub hasPending {
	my ($id) = @_;
	return defined($id) && exists($pending{$id}) ? 1 : 0;
}

sub pendingRequests {
	return [map { $pending{$_}{request} }
		sort { $pending{$a}{request}{created_at} <=> $pending{$b}{request}{created_at} }
		keys %pending];
}

sub reset {
	%pending = ();
	$sequence = 0;
	resetContextProvider();
}

1;
