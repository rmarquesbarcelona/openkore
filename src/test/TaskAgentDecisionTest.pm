package TaskAgentDecisionTest;

use strict;
use warnings;
use Test::More;
use Plugins;
use Task;
use Task::AgentDecision;
use Agent::Gateway;

sub start {
	print "### Starting TaskAgentDecisionTest\n";
	testResolvedDecision();
	testTimeoutError();
	testFallbackDecision();
	testStopCancelsRequest();
	Agent::Gateway::reset();
}

sub testResolvedDecision {
	Agent::Gateway::reset();
	my $hook = Plugins::addHook('agent/request', sub {
		my ($name, $args) = @_;
		Agent::Gateway::resolve($args->{request}{id}, { action => 'continue' });
	});

	my $task = Task::AgentDecision->new(
		request => {
			id      => 'decision-resolved',
			reason  => 'ambiguous_state',
			context => {},
		},
	);
	$task->activate();
	$task->iterate();

	is($task->getStatus(), Task::DONE, 'resolved agent decision completes task');
	is($task->getDecision()->{action}, 'continue', 'task stores returned decision');
	Plugins::delHook($hook);
}

sub testTimeoutError {
	Agent::Gateway::reset();
	my $task = Task::AgentDecision->new(
		request => {
			id      => 'decision-timeout',
			reason  => 'needs_answer',
			context => {},
			timeout => 0,
		},
	);
	$task->activate();
	Agent::Gateway::iterate();
	$task->iterate();

	is($task->getStatus(), Task::DONE, 'timed-out decision finishes task');
	is($task->getError()->{code}, 'agent_timeout', 'timeout becomes explicit task error');
	ok($task->timedOut(), 'task records timeout state');
}

sub testFallbackDecision {
	Agent::Gateway::reset();
	my $task = Task::AgentDecision->new(
		request => {
			id      => 'decision-fallback',
			context => {},
			timeout => 0,
		},
		fallback => sub {
			return { action => 'safe_abort' };
		},
	);
	$task->activate();
	Agent::Gateway::iterate();
	$task->iterate();

	is($task->getStatus(), Task::DONE, 'fallback resolves timed-out task');
	ok(!defined($task->getError()), 'fallback completion is not an error');
	is($task->getDecision()->{action}, 'safe_abort', 'fallback result is stored as decision');
}

sub testStopCancelsRequest {
	Agent::Gateway::reset();
	my $task = Task::AgentDecision->new(
		request => {
			id      => 'decision-cancel',
			context => {},
		},
	);
	$task->activate();
	ok(Agent::Gateway::hasPending('decision-cancel'), 'decision is pending after activation');
	$task->stop();
	ok(!Agent::Gateway::hasPending('decision-cancel'), 'stopping task cancels pending request');
	is($task->getStatus(), Task::STOPPED, 'stopped decision task is stopped');
}

1;
