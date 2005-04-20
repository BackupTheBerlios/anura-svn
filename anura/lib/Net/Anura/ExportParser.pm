package Net::Anura::ExportParser;

use strict;
use warnings;
use XML::Parser;

use Net::Anura::Page;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

	$VERSION     = sprintf("%d.%02d", 0.1 =~ /(\d+)\.(\d+)/);
	@ISA         = qw(Exporter);
	@EXPORT      = ();
	@EXPORT_OK   = ();
	%EXPORT_TAGS = ();
}
our @EXPORT_OK;

sub parse( $ ) {
	my $p    = XML::Parser->new( Style => 'Tree' );
	my $tree = $p->parse( shift );
	while ( scalar( @$tree ) ) {
		my $tag = shift @$tree;
		my $cnt = shift @$tree;

		return _parseMediawiki( $cnt ) if $tag eq 'mediawiki';
	}
	return undef;
}

# keep for debugging
#sub _emit( $$ ) {
#	my $name = shift;
#	my $ref = shift;
#
#	print "$name = " . ref( $ref ) . " [\n";
#	my $q = 0;
#	foreach my $a ( @$ref ) {
#		if ( '' eq ref( $a ) ) {
#			print "$q:\t'$a'\n";
#		} else {
#			print "$q:\t=> ".ref($a)."\n";
#		}
#		$q++;
#	}
#	print "]\n";
#}

##
## Internal functions
##

sub _parseText( $ ) {
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

sub _parseContributor( $ ) {
	my $ref = shift;

	my $attr = shift @$ref;
	my @res;
	while ( scalar( @$ref ) ) {
		my $tag = shift @$ref;
		my $cnt = shift @$ref;

		push @res, ( 'username', _parseText($cnt) ) if 'username' eq $tag;
	}
	return \@res;
}

sub _parseRevision( $ ) {
	my $ref = shift;

	my $attr = shift @$ref;
	my %res = ();
	while ( scalar( @$ref ) ) {
		my $tag = shift @$ref;
		my $cnt = shift @$ref;

		$res{timestamp}   = _parseText       ( $cnt ) if 'timestamp'   eq $tag;
		$res{contributor} = _parseContributor( $cnt ) if 'contributor' eq $tag;
		$res{comment}     = _parseText       ( $cnt ) if 'comment'     eq $tag;
		$res{text}        = _parseText       ( $cnt ) if 'text'        eq $tag;
	}
	return \%res;
}

sub _parsePage( $$ ) {
	my $res = shift;
	my $ref = shift;

	my $attr = shift @$ref;
	my ( $title, $revision );
	while ( scalar( @$ref ) ) {
		my $tag = shift @$ref;
		my $cnt = shift @$ref;

		$title    = _parseText    ( $cnt ) if 'title'    eq $tag;
		$revision = _parseRevision( $cnt ) if 'revision' eq $tag;
	}
	$$res{ $title } = $revision if defined $title and defined $revision;
}

sub _parseMediawiki( $ ) {
	my $ref = shift;

	my $attr = shift @$ref;
	my %res = ();
	while ( scalar( @$ref ) ) {
		my $tag = shift @$ref;
		my $cnt = shift @$ref;
		_parsePage( \%$res, $cnt ) if 'page' eq $tag;
	}
	return %res;
}

1;

__END__
