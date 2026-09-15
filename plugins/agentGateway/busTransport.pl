#########################################################################
# OpenKore agent gateway Bus transport
#
# Optional transport adapter. Agent::Gateway remains independent from Bus.
# Complex request/decision payloads are encoded as JSON inside the Bus' scalar
# key/value message format.
#########################################################################
package agentGatewayBusTransport;

use strict;
use warnings;
use Plugins;
use Globals qw($bus);
use Log qw(message warning);
use Agent::Gateway;

my $json_available = eval {
	require JSON::PP;
	1;
};

Plugins::register(
	'agentGatewayBusTransport',
	'Bus transport adapter for Agent::Gateway',
	\&onUnload,
	\&onReload,
);

my $bus_callback_id;
my $hooks = Plugins::addHooks(
	['initialized',     \&onInitialized, undef],
	['agent/request',   \&onAgentRequest, undef],
	['agent/notify',    \&onAgentNotify, undef],
	['agent/cancelled', \&onAgentCancelled, undef],
	['agent/timeout',   \&onAgentTimeout, undef],
);

sub _encode {
	my ($value) = @_;
	return undef if !$json_available;
	my $json;
	my $ok = eval {
		$json = JSON::PP::encode_json($value);
		1;
	};
	if (!$ok) {
		warning "Agent Bus transport could not encode JSON payload: $@\n";
		return undef;
	}
	return $json;
}

sub _decode {
	my ($json) = @_;
	return undef if !$json_available || !defined $json;
	my $value;
	my $ok = eval {
		$value = JSON::PP::decode_json($json);
		1;
	};
	if (!$ok) {
		warning "Agent Bus transport received invalid JSON payload: $@\n";
		return undef;
	}
	return $value;
}

sub _send {
	my ($message_id, $value) = @_;
	return if !$bus;
	my $payload = _encode($value);
	return if !defined $payload;
	$bus->send($message_id, {
		protocol => 'openkore-agent-v1',
		payload  => $payload,
	});
}

sub onInitialized {
	if (!$json_available) {
		warning "Agent Bus transport disabled: JSON::PP is unavailable.\n";
		return;
	}
	return if !$bus;
	return if $bus_callback_id;
	$bus_callback_id = $bus->onMessageReceived()->add(undef, \&onBusMessage);
	message "Agent Gateway Bus transport enabled.\n", 'system';
}

sub onAgentRequest {
	my (undef, $args) = @_;
	_send('AGENT_REQUEST', $args->{request}) if $args && $args->{request};
}

sub onAgentNotify {
	my (undef, $args) = @_;
	_send('AGENT_NOTIFY', $args->{event}) if $args && $args->{event};
}

sub onAgentCancelled {
	my (undef, $args) = @_;
	_send('AGENT_CANCELLED', {
		request => $args->{request},
		reason  => $args->{reason},
	}) if $args && $args->{request};
}

sub onAgentTimeout {
	my (undef, $args) = @_;
	_send('AGENT_TIMEOUT', $args->{request}) if $args && $args->{request};
}

sub onBusMessage {
	my (undef, undef, $event) = @_;
	return if !$event || $event->{messageID} ne 'AGENT_RESOLVE';

	my $args = $event->{args} || {};
	return if ($args->{protocol} || '') ne 'openkore-agent-v1';

	my $envelope = _decode($args->{payload});
	return if ref($envelope) ne 'HASH';
	my $request_id = $envelope->{request_id};
	if (!defined($request_id) || $request_id eq '') {
		warning "Agent Bus transport received AGENT_RESOLVE without request_id.\n";
		return;
	}

	if (!Agent::Gateway::resolve($request_id, $envelope->{decision})) {
		warning "Agent Bus transport received resolution for unknown request '$request_id'.\n";
	}
}

sub onUnload {
	Plugins::delHooks($hooks) if $hooks;
	if ($bus && $bus_callback_id) {
		$bus->onMessageReceived()->remove($bus_callback_id);
	}
	undef $bus_callback_id;
}

sub onReload {
	onUnload();
}

1;
