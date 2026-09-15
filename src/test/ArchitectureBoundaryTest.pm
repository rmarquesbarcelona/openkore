# Architectural boundary tests for the new world/agent layers.
package ArchitectureBoundaryTest;

use strict;
use warnings;
use Test::More;
use File::Find;
use File::Spec;
use FindBin qw($RealBin);

sub start {
	print "### Starting ArchitectureBoundaryTest\n";
	testGlobalsBoundary();
	testWorldModelPurity();
}

sub _src_root {
	return File::Spec->rel2abs(File::Spec->catdir($RealBin, '..'));
}

sub _read_file {
	my ($path) = @_;
	open my $fh, '<', $path or die "Unable to read $path: $!\n";
	local $/;
	my $content = <$fh>;
	close $fh;
	return $content;
}

sub _perl_files_under {
	my ($dir) = @_;
	my @files;
	find(
		sub {
			return if !-f $_;
			return if $_ !~ /\.pm$/;
			push @files, $File::Find::name;
		},
		$dir,
	);
	return sort @files;
}

sub testGlobalsBoundary {
	my $src = _src_root();
	my @files = (
		_perl_files_under(File::Spec->catdir($src, 'Agent')),
		_perl_files_under(File::Spec->catdir($src, 'World')),
	);

	my $legacy_bridge = File::Spec->canonpath(File::Spec->catfile($src, 'World', 'LegacyBridge.pm'));
	my $saw_bridge = 0;

	for my $file (@files) {
		my $canonical = File::Spec->canonpath($file);
		my $content = _read_file($file);
		my $imports_globals = $content =~ /^\s*use\s+Globals\b/m ? 1 : 0;

		if ($canonical eq $legacy_bridge) {
			$saw_bridge = 1;
			ok($imports_globals, 'World::LegacyBridge is the explicit Globals compatibility edge');
		} else {
			ok(!$imports_globals, "$canonical does not import Globals");
		}
	}

	ok($saw_bridge, 'legacy compatibility bridge is present in the world layer');
}

sub testWorldModelPurity {
	my $src = _src_root();
	my $model = File::Spec->catfile($src, 'World', 'Model.pm');
	my $content = _read_file($model);

	for my $forbidden (qw(Globals Plugins Network AI Agent::Gateway)) {
		unlike($content, qr/^\s*use\s+\Q$forbidden\E\b/m,
			"World::Model stays independent of $forbidden");
	}
}

1;
