package Net::Anura;

use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Cookies;
use HTML::Form;
use URI;

use Net::Anura::ExportParser;
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

sub new {
	my ( $proto, %args ) = @_;
	my $class = ref $proto || $proto;
	my $self  = { };

	$self->{_wiki}       = $args{wiki};
	$self->{_cookiefile} = exists $args{cookie_jar} ? $args{cookie_jar} : "$ENV{HOME}/.anura.cookies";
	$self->{_username}   = $args{username};
	$self->{_password}   = $args{password};

	$self->{_host}       = URI->new( $self->{_wiki} )->host;
	$self->{_cookie_jar} = HTTP::Cookies->new( file => $self->{_cookiefile}, autosave => 1 );
	$self->{_ua}         = LWP::UserAgent->new( agent => "Anura", cookie_jar => $self->{_cookie_jar} );
	$self->{_headers}    = [ Host => $self->{_host} ];
	$self->{_logged_in}  = 0;

	bless ($self, $class);
	return $self;
}

##
## Login and logout
##

sub login {
	my $self = shift;
	{
		my ( $u, $p ) = @_;
		$self->username( $u ) if defined $u;
		$self->password( $p ) if defined $p;
	}

	return 1 if $self->{_logged_in};
	if ( $self->_scancookies( $self->{_host} ) ) {
		$self->{_logged_in} = 1;
		return 1;
	}

	my $res = $self->{_ua}->post(
		$self->{_wiki} . "?title=Special:Userlogin&action=submitlogin",
		$self->{_headers},
		Content => [
			wpName         => $self->{_username},
			wpPassword     => $self->{_password},
			wpRemember     => 1,
			wpLoginAttempt => 1
		]
	);

	$self->{_logged_in} = ( 302 == $res->code );
	return $self->{_logged_in};
}

sub logout {
	my $self = shift;
	return 1 unless $self->{_logged_in};

	my $res = $self->{_ua}->post(
		$self->{_wiki} . "?title=Special:Userlogout",
		$self->{_headers}
	);

	$self->{_logged_in} = 0;
	return 1;
}

##
## Page manipulation
##

##
## Editing
##

## TODO: Rewrite this to take @reqs or %reqs, with %reqs allowing curonly=>0/1.
##       Perhaps default to curonly, and call opt 'allrevs'?
##       Either way, will have to create 1 or 2 separate POSTs,
##       one for curonly=0, one for curonly=1
sub get {
	my ( $self, @reqs ) = @_;
	return undef unless @reqs;
	my %results = ();

	my $res = $self->{_ua}->post(
		$self->{_wiki} . '/Special:Export',
		$self->{_headers},
		Content => [
			action => 'submit',
			curonly => 'true',
			pages => join( "\r\n", @reqs )
		]
	);

	return undef unless $res->content_type eq 'text/xml' or $res->content_type eq 'application/xml';

	my $page = Net::Anura::ExportParser::parse( $res->content );
	my @pages;

	foreach my $k ( keys %$page ) {
		push @pages, Net::Anura::Page->new( $k, %{ $$page{$k} } );
	}

	return @pages;
}

## TODO: Rewrite this to accept Net::Anura::Page objects
sub put {
	my ( $self, $page, $contents, $summary, %args ) = @_;
	return 0 unless defined $page and defined $contents;

	my $minor = $args{minor};
	my $watch = $args{watch};

	$self->login( ) unless $self->{_logged_in};
	return 0        unless $self->{_logged_in};

	my $res = $self->{_ua}->get(
		$self->{_wiki} . "/$page?action=edit",
		$self->{_headers}
	);

	return 0 if ( 200 != $res->code );

	my ( $Edittime, $EditToken );
	my @forms = HTML::Form->parse( $res );
	for my $f ( @forms ) {
		next unless $f->attr( 'name' ) eq 'editform';
		$EditToken = $f->value( 'wpEditToken' ) if defined $f->find_input( 'wpEditToken' );
		$Edittime  = $f->value( 'wpEdittime'  ) if defined $f->find_input( 'wpEdittime' );
	}
	return 0 unless defined $EditToken;

	my %post = (
		#wpSave     => 1, # Not used in HEAD or REL1_4 -�var
		wpTextbox1  => $contents,
		wpSummary   => $summary,
		wpEdittime  => $Edittime,
		wpEditToken => $EditToken
	);
	$post{wpMinoredit} = 1 if $minor;
	$post{wpWatchthis} = 1 if $watch;

	$res = $self->{_ua}->post(
		$self->{_wiki} . "/$page?action=submit",
		$self->{_headers},
		Content => [ %post ]
	);

	return ( 302 == $res->code );
}

##
## Deleting
##

sub delete {
	my ($self, $page, $reason) = @_;
	return 0 unless defined $page;

	my $res = $self->{_ua}->get(
		$self->{_wiki} . "?title=$page&action=delete",
		$self->{_headers}
	);

	return 0 if ( 200 != $res->code );

	my $EditToken;
	my @forms = HTML::Form->parse( $res );
	for my $f ( @forms ) {
		next if ( $f->attr( 'id' ) ne 'deleteconfirm' );
		$EditToken = $f->value( 'wpEditToken' ) if defined $f->find_input( 'wpEditToken' );
	}
	return 0 unless defined $EditToken;

	$res = $self->{_ua}->post(
		$self->{_wiki} . "?title=$page&action=delete",
		$self->{_headers},
		Content => [
			wpReason => $reason,
			wpConfirm => 1, # Needed for REL1_4, no longer exists in REL1_5
			wpConfirmB => 1,
			wpEditToken => $EditToken
		]
	);

	return ( 302 == $res->code );
}

##
## Uploading
##

sub upload {
	my ($self, $file, $summary) = @_;
	return 0 unless defined $file;

	my $res = $self->{_ua}->post(
		$self->{_wiki} . '/Special:Upload',
		$self->{_headers},
		Content => [
			wpUploadFile => [ $file ],
			wpUploadDescription => $summary,
			wpUpload => 1,
			wpUploadAffirm => 1
			# Note: wpUploadCopyStatus and wpUploadSource should be sent if $wgUseCopyrightUpload is true
		]
	);
	return 1 if ( 302 == $res );

	if ($res->content =~ /<h4 class='error'>(.*)(?=<\/h4>)/) {
		#(my $error = $1) =~ s/<[^>]*>//g; # TODO: Do something smart with this.
	} elsif ($res->content =~ m#<ul class='warning'>(.*?)(?=</ul>)#s) {
		#(my $error = $1) =~ s/<[^>]*>//g;
		my $SessionKey;
		my @forms = HTML::Form->parse( $res );
		for my $f ( @forms ) {
			next if ( $f->attr( 'id' ) ne 'uploadwarning' );
			$SessionKey = $f->value( 'wpSessionKey' ) if defined $f->find_input( 'wpSessionKey' );
		}
		return 0 unless defined $SessionKey;

		my $affirm = $self->{_ua}->post(
			$self->{_wiki} . '?title=Special:Upload&action=submit',
			$self->{_headers},
			Content => [
				wpUploadDescription => $summary,
				wpUpload => 1,
				wpUploadAffirm => 1,
				wpIgnoreWarning => 1,
				wpSessionKey => $SessionKey
			]
		);
	}

	return ( 302 == $res->code );
}

##
## Accessors/Mutators
##

sub username {
	my $self = shift;
	if ( @_ ) {
		$self->{_username}  = shift;
		$self->{_logged_in} = 0;
	}
	return $self->{_username};
}

sub password {
	my $self = shift;
	if ( @_ ) {
		$self->{_password}  = shift;
		$self->{_logged_in} = 0;
	}
	return $self->{_password};
}

sub wiki {
	my $self = shift;
	if ( @_ ) {
		$self->{_wiki}      = shift;
		$self->{_logged_in} = 0;
	}
	return $self->{_wiki};
}

##
## Internal functions
##

sub _scancookies {
	my ( $self, $host ) = @_;
	my %cookie;
	my %prefixes;

	$self->{_cookie_jar}->scan(
		sub {
#			my ( $version, $key, $val, $path, $domain, $port, $pathspec, $secure, $expires, $discard, $hash ) = @_;
			my ( undef,    $key, $val, undef, $domain, undef, undef,     undef,   $expires, undef,    undef ) = @_;
			return if ( $expires <= time || $host ne $domain );
			if ( $key =~ /^(.*?)(Token|UserID|UserName)$/i ) {
				$cookie{"$1$2"} = $val;
				$prefixes{$2} = 1;
			}
		}
	);

	return
		1 == scalar( keys( %prefixes ) )          and
		$cookie{'UserName'} eq $self->{_username} and
		exists $cookie{'Token'}                   and
		exists $cookie{'UserID'}                  and
		exists $cookie{'UserName'};
}

1;

__END__
