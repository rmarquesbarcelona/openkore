#########################################################################
#  OpenKore - Task::AgentDecision
#
#  A cooperative Task wrapper for a deliberative agent decision. Waiting for
#  the agent never blocks the OpenKore main loop. Only the task's configured
#  mutexes are held while the decision is pending.
#########################################################################
package Task::AgentDecision;

use strict;
use warnings;
use base qw(Task);
use Task;
use Agent::Gateway;

sub new {
	my $class = shift;
	my %args = @_;

	my $request = delete($args{request}) || {};
	die "Task::AgentDecision request must be a hash reference\n"
		if ref($request) ne 'HASH';

	my $fallback = delete $args{fallback};
	my $name = delete($args{name}) || 'AgentDecision';
	my $priority = exists($args{priority}) ? delete($args{priority}) : Task::HIGH_PRIORITY;
	my $mutexes = exists($args{mutexes}) ? delete($args{mutexes}) : ['agent_decision'];

	my $self = $class->SUPER::new(
		name     => $name,
		priority => $priority,
		mutexes  => $mutexes,
	);
	$self->{AG_request} = { %{$request} };
	$self->{AG_fallback} = $fallback;
	$self->{AG_request_id} = undef;
	$self->{AG_decision} = undef;
	$self->{AG_resolved} = 0;
	$self->{AG_timed_out} = 0;
	return $self;
}

sub activate {
	my ($self) = @_;
	$self->SUPER::activate();

	my %request = %{$self->{AG_request}};
	my $user_fallback = $self->{AG_fallback};

	$request{on_resolve} = sub {
		my ($decision) = @_;
		$self->{AG_decision} = $decision;
		$self->{AG_resolved} = 1;
	};

	$request{on_timeout} = sub {
		$self->{AG_timed_out} = 1;
	};

	if (ref($user_fallback) eq 'CODE') {
		$request{fallback} = sub {
			my ($agent_request) = @_;
			$self->{AG_decision} = $user_fallback->($agent_request);
			$self->{AG_resolved} = 1;
		};
	}

	$self->{AG_request_id} = Agent::Gateway::request(%request);
}

sub iterate {
	my ($self) = @_;
	$self->SUPER::iterate();

	if ($self->{AG_resolved}) {
		$self->setDone();
		return;
	}

	if ($self->{AG_timed_out}) {
		$self->setError('agent_timeout', 'External agent did not resolve the decision before its deadline.');
	}
}

sub stop {
	my ($self) = @_;
	my $id = $self->{AG_request_id};
	if (defined($id) && Agent::Gateway::hasPending($id)) {
		Agent::Gateway::cancel($id, 'task_stopped');
	}
	$self->SUPER::stop();
}

sub getRequestID {
	return $_[0]->{AG_request_id};
}

sub getDecision {
	return $_[0]->{AG_decision};
}

sub timedOut {
	return $_[0]->{AG_timed_out} ? 1 : 0;
}

1;
