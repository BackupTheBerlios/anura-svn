package Net::Anura;

use strict;
use warnings;

use HTML::Form;
use HTTP::Cookies;
use LWP::UserAgent;
use URI::URL;

BEGIN {
	use Exporter   ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

	$VERSION     = "1.00";

	@ISA         = qw(Exporter);
	@EXPORT      = ( );     # e.g.: qw(&func1 &func2 &func4)
	%EXPORT_TAGS = ( );     # e.g.: TAG => [ qw!name1 name2! ],

	# your exported package globals go here,
	# as well as any optionally exported functions
	@EXPORT_OK   = ( );     # e.g.: qw($Var1 %Hashit &func3)
}
our @EXPORT_OK;

my @headers = (
   'Accept'          => 'image/gif, image/x-xbitmap, image/jpeg, image/pjpeg, image/png, */*',
   'Accept-Charset'  => 'iso-8859-1,*,utf-8',
   'Accept-Language' => 'en-US',
);

sub _scancookies {
	my ( $self, $domain ) = @_;
	my %WikiCookie = ( );

	$self->{_cookie_jar}->scan(
		sub {
			my ( $version, $key, $val, $path, $cookiedomain, $port, $pathspec, $secure, $expires, $discard, $hash ) = @_;
			return if ( $expires <= time( ) || $domain ne $cookiedomain );
			$WikiCookie{$1} = $val if ( $key =~ /(Token|UserID|UserName)$/i );
		}
	);
	if ( exists( $WikiCookie{'Token'} ) && exists( $WikiCookie{'UserID'} ) && exists( $WikiCookie{'UserName'} ) && $WikiCookie{'UserName'} eq $self->{_username} ) {
		return 1;
	}
	return 0;
}

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self  = { };

	my %args = ( @_ );
	$self->{_username}   = exists( $args{username}   ) ? $args{username}   : undef;
	$self->{_password}   = exists( $args{password}   ) ? $args{password}   : undef;
	$self->{_baseurl}    = exists( $args{baseurl}    ) ? $args{baseurl}    : undef;
	$self->{_cookiefile} = exists( $args{cookie_jar} ) ? $args{cookie_jar} : "$ENV{HOME}/.anura.cookies";

	$self->{_cookie_jar} = HTTP::Cookies->new( file => $self->{_cookiefile}, autosave => 1 );
	$self->{_ua}         = LWP::UserAgent->new( agent => "Anura/0.1", cookie_jar => $self->{_cookie_jar} );

	$self->{_logged_in}  = 0;

	bless ($self, $class);
	return $self;
}

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

sub baseurl {
	my $self = shift;
	if ( @_ ) {
		$self->{_baseurl}   = shift;
		$self->{_logged_in} = 0;
	}
	return $self->{_baseurl};
}

sub login {
	my $self = shift;
	return 1 if ( $self->{_logged_in} );

	my $url = URI::URL->new( $self->{_baseurl} );
	my $domain = $url->host( );
	if ( $self->_scancookies( $url->host ) ) {
		$self->{_logged_in} = 1;
		return 1;
	}

	my $res = $self->{_ua}->post(
		$self->{_baseurl} . "/Special:Userlogin?action=submitlogin",
		@headers,
		Content => [
			wpName         => $self->{_username},
			wpPassword     => $self->{_password},
			wpRemember     => 1,
			wpLoginAttempt => "Log in"
		]
	);

	$self->{_logged_in} = ( 302 == $res->code( ) );
	return  $self->{_logged_in};
}

sub logout {
	my $self = shift;
	return 1 if ( ! $self->{_logged_in} );

	my $res = $self->{_ua}->post(
		$self->{_baseurl} . "/Special:Userlogout",
		@headers
	);

	$self->{_logged_in} = 0;
	return  1;
}

sub getPage {
	my ( $self, $page ) = @_;
	return undef if ( ! defined( $page ) );

	my $res = $self->{_ua}->get(
		$self->{_baseurl} . "/$page?action=raw",
		@headers
	);

	return $res->content( ) if ( 200 == $res->code( ) );
	return undef;
}

sub putPage {
	my ( $self, $page, $contents, $summary, %args ) = @_;
	return 0 if ( ! defined( $page ) || ! defined( $contents ) );

	my $minor = $args{minor};
	my $watch = $args{watch};

	my $link = $self->{_baseurl} . "/$page";
	my $res = $self->{_ua}->get(
		"$link?action=edit",
		@headers
	);

	return 0 if ( 200 != $res->code( ) );

	my @forms = HTML::Form->parse( $res->content( ), "$link?action=edit" );
	my ( $Edittime, $EditToken );
	for my $f ( @forms ) {
		next if ( $f->attr( 'name' ) ne 'editform' );

		$EditToken = $f->value( 'wpEditToken' ) if ( defined( $f->find_input( 'wpEditToken' ) ) );
		$Edittime  = $f->value( 'wpEdittime'  ) if ( defined( $f->find_input( 'wpEdittime'  ) ) );
	}

	return 0 if ( ! defined( $EditToken ) );

	my %post = (
		wpSave      => 'Save page',
		wpTextbox1  => $contents,
		wpSummary   => $summary,
		wpEdittime  => $Edittime,
		wpEditToken => $EditToken
	);
	$post{wpMinoredit} = 1    if ( $minor );
	$post{wpWatchthis} = "on" if ( $watch );

	$res = $self->{_ua}->post(
		"$link?action=submit",
		@headers,
		Content => [ %post ]
	);

	return ( 302 == $res->code( ) );
}

1;

__END__
