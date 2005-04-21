package Net::Anura::Page;

use strict;
use warnings;
use XML::Parser;

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

sub new {
	my ( $proto, $title, $inrevs ) = @_;
	my $class = ref $proto || $proto;
	my $self  = { };

	$self->{_title} = $title;
	my @revisions;
	foreach my $rev ( @$inrevs ) {
		push @revisions, Net::Anura::Page::Revision->new( %$rev );
	}
	@{ $self->{_revisions} } = @revisions;

	bless ($self, $class);
	return $self;
}

#
# Accessors/Mutators
#

sub title {
	my $self = shift;
	$self->{_title} = shift if @_ ;
	return $self->{_title};
}

sub revisions {
	my $self = shift;
	@{ $self->{_revisions} } = @_ if @_;
	return $self->{_revisions};
}

##
## Subpackage
##

package Net::Anura::Page::Revision;

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

sub new {
	my ( $proto, %revision ) = @_;
	my $class = ref $proto || $proto;
	my $self  = { };

	$self->{_timestamp}   = $revision{timestamp};
	$self->{_contributor} = $revision{contributor};
	$self->{_comment}     = $revision{comment};
	$self->{_text}        = $revision{text};

	bless ($self, $class);
	return $self;
}

#
# Accessors/Mutators
#

sub timestamp {
	my $self = shift;
	$self->{_timestamp} = shift if ( @_ );
	return $self->{_timestamp};
}

sub contributor {
	my $self = shift;
	$self->{_contributor} = shift if ( @_ );
	return $self->{_contributor};
}

sub comment {
	my $self = shift;
	$self->{_comment} = shift if ( @_ );
	return $self->{_comment};
}

sub text {
	my $self = shift;
	$self->{_text} = shift if ( @_ );
	return $self->{_text};
}

1;

__END__
