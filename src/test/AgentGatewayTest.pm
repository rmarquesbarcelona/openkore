package AgentGatewayTest;

use strict;
use warnings;
use Test::More;
use Plugins;
use Agent::Gateway;

sub start {
	print "### Starting AgentGatewayTest\n";
	testRequestAndResolve();
	testCancel();
	testTimeoutAndFallback();
	testContextProvider();
	Agent::Gateway::reset();
}

sub testRequestAndResolve {
	Agent::Gateway::reset();
	my $seen;
	my $resolved;
	my $hook = Plugins::addHook('agent/request', sub {
		my ($name, $args) = @_;
		$seen = $args->{request};
	});

	my $id = Agent::Gateway::request(
		id      => 'test-request',
		type    => 'task_blocked',
		reason  => 'npc_missing',
		context => { map => 'geffen' },
		on_resolve => sub {
			my ($decision, $request) = @_;
			$resolved = [$decision, $request];
		},
	);

	is($id, 'test-request', 'request returns its ID');
	ok(Agent::Gateway::hasPending($id), 'request is pending');
	is($seen->{type}, 'task_blocked', 'request hook receives request type');
	is($seen->{context}{map}, 'geffen', 'request hook receives explicit context');

	ok(Agent::Gateway::resolve($id, { action => 'search_map' }), 'resolve accepts pending request');
	ok(!Agent::Gateway::hasPending($id), 'resolved request is removed');
	is($resolved->[0]{action}, 'search_map', 'resolve callback receives decision');
	is($resolved->[1]{reason}, 'npc_missing', 'resolve callback receives original request');
	ok(!Agent::Gateway::resolve($id, {}), 'cannot resolve the same request twice');

	Plugins::delHook($hook);
}

sub testCancel {
	Agent::Gateway::reset();
	my $cancel_reason;
	my $hook = Plugins::addHook('agent/cancelled', sub {
		my ($name, $args) = @_;
		$cancel_reason = $args->{reason};
	});

	my $id = Agent::Gateway::request(
		id      => 'cancel-me',
		context => {},
	);
	ok(Agent::Gateway::cancel($id, 'situation_resolved'), 'pending request can be cancelled');
	is($cancel_reason, 'situation_resolved', 'cancel hook carries reason');
	ok(!Agent::Gateway::hasPending($id), 'cancelled request is removed');

	Plugins::delHook($hook);
}

sub testTimeoutAndFallback {
	Agent::Gateway::reset();
	my ($timed_out, $fallback, $timeout_hook) = (0, 0, 0);
	my $hook = Plugins::addHook('agent/timeout', sub {
		$timeout_hook++;
	});

	my $id = Agent::Gateway::request(
		id      => 'timeout-now',
		context => {},
		timeout => 0,
		on_timeout => sub { $timed_out++ },
		fallback   => sub { $fallback++ },
	);
	Agent::Gateway::iterate();

	ok(!Agent::Gateway::hasPending($id), 'timed-out request is removed');
	is($timed_out, 1, 'timeout callback runs once');
	is($fallback, 1, 'fallback runs once');
	is($timeout_hook, 1, 'timeout hook fires once');

	Plugins::delHook($hook);
}

sub testContextProvider {
	Agent::Gateway::reset();
	my $calls = 0;
	Agent::Gateway::setContextProvider(sub {
		my ($request) = @_;
		$calls++;
		return {
			provided_for => $request->{reason},
		};
	});

	my $id = Agent::Gateway::request(
		id     => 'provider-test',
		reason => 'needs_context',
	);
	my $request = Agent::Gateway::getRequest($id);
	is($calls, 1, 'context provider called once');
	is($request->{context}{provided_for}, 'needs_context', 'provider receives request metadata');

	my $pending = Agent::Gateway::pendingRequests();
	is(scalar(@{$pending}), 1, 'pendingRequests returns pending requests');
	is($pending->[0]{id}, $id, 'pendingRequests contains request');

	Agent::Gateway::reset();
}

1;
