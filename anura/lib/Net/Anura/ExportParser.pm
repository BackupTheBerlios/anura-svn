package Net::Anura::ExportParser;

use strict;
use warnings;
use XML::Parser;

BEGIN {
	use Exporter   ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

	$VERSION     = sprintf("%d.%02d", 0.1 =~ /(\d+)\.(\d+)/);

	@ISA         = qw(Exporter);
	@EXPORT      = qw(&process);
	%EXPORT_TAGS = ();     # e.g.: TAG => [ qw!name1 name2! ],

	# your exported package globals go here,
	# as well as any optionally exported functions
	@EXPORT_OK   = ();     # e.g.: qw($Var1 %Hashit &func3)
}

our @EXPORT_OK;

sub emit($$) {
	my $name = shift;
	my $ref = shift;

	print "$name = " . ref( $ref ) . " [\n";
	my $q = 0;
	foreach my $a ( @$ref ) {
		if ( '' eq ref( $a ) ) {
			print "$q\t'$a'\n";
		} else {
			print "$q\t=> ".ref($a)."\n";
		}
		$q++;
	}
	print "]\n";
}

sub processText($) {
	my $ref = shift;

	my $attr = shift @$ref;
	my $text;
	while ( scalar( @$ref ) ) {
		my $tag = shift @$ref;
		my $cnt = shift @$ref;

		$text .= $cnt if '0' eq $tag;
	}
	return $text;
}

sub processContributor($) {
	my $ref = shift;

	my $attr = shift @$ref;
	my @res;
	while ( scalar( @$ref ) ) {
		my $tag = shift @$ref;
		my $cnt = shift @$ref;

		push @res, ( 'username', processText($cnt) ) if 'username' eq $tag;
	}
	return \@res;
}

sub processRevision($) {
	my $ref = shift;

	my $attr = shift @$ref;
	my %res = ();
	while ( scalar( @$ref ) ) {
		my $tag = shift @$ref;
		my $cnt = shift @$ref;

		$res{timestamp}   = processText       ( $cnt ) if 'timestamp'   eq $tag;
		$res{contributor} = processContributor( $cnt ) if 'contributor' eq $tag;
		$res{comment}     = processText       ( $cnt ) if 'comment'     eq $tag;
		$res{text}        = processText       ( $cnt ) if 'text'        eq $tag;
	}
	return \%res;
}

sub processPage($$) {
	my $res = shift;
	my $ref = shift;

	my $attr = shift @$ref;
	my ( $title, $revision );
	while ( scalar( @$ref ) ) {
		my $tag = shift @$ref;
		my $cnt = shift @$ref;

		$title    = processText    ( $cnt ) if 'title'    eq $tag;
		$revision = processRevision( $cnt ) if 'revision' eq $tag;
	}
	$$res{ $title } = $revision if defined $title and defined $revision;
}

sub processMediawiki($$) {
	my $res = shift;
	my $ref = shift;

	my $attr = shift @$ref;
	while ( scalar( @$ref ) ) {
		my $tag = shift @$ref;
		my $cnt = shift @$ref;
		processPage( $res, $cnt ) if 'page' eq $tag;
	}
}

sub processDocument($) {
	my %res = ();
	my $ref = shift;

	while ( scalar( @$ref ) ) {
		my $tag = shift @$ref;
		my $cnt = shift @$ref;
		if ( $tag eq 'mediawiki' ) {
			processMediawiki( \%res, $cnt );
			return \%res;
		}
	}
	return undef;
}

sub process( $ ) {
	my $p = XML::Parser->new( Style => 'Tree' );
	my $tree = $p->parse( shift );
	return processDocument( $tree );
}

1;

__END__
