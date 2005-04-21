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

	my %CookieJars  = ();
}
our @EXPORT_OK;

our %CookieJars;

sub new {
	my ( $proto, %args ) = @_;
	my $class = ref $proto || $proto;
	my $self  = { };

	$self->{_cookiefile} = exists $args{cookie_jar} ? $args{cookie_jar} : "$ENV{HOME}/.anura.cookies";
	$self->{_username}   = $args{username};
	$self->{_password}   = $args{password};
	$self->wiki( $args{wiki} ) if  exists $args{wiki};

	$CookieJars{ $self->{_cookiefile} } = HTTP::Cookies->new( file => $self->{_cookiefile}, autosave => 1 ) unless exists $CookieJars{ $self->{_cookiefile} };
	$self->{_cookie_jar} = $CookieJars{ $self->{_cookiefile} };
	$self->{_ua}         = LWP::UserAgent->new( agent => 'Anura', cookie_jar => $self->{_cookie_jar} );
	$self->{_host}       = URI->new( $self->{_wiki} )->host;
	$self->{_headers}    = [ Host => $self->{_host} ];
	$self->{_logged_in}  = 0;

	bless ($self, $class);
	return $self;
}

##
## Public methods
##

sub login {
	my $self = shift;
	{
		my ( $u, $p ) = @_;
		$self->username( $u ) if defined $u;
		$self->password( $p ) if defined $p;
	}

	return 1 if $self->{_logged_in};
	if ( $self->_scancookies ) {
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

sub get {
	my ( $self, @reqs ) = @_;
	return $self->_get( undef, @reqs );
}

sub getAllRevisions {
	my ( $self, @reqs ) = @_;
	return $self->_get( 1, @reqs );
}

sub put {
	my ( $self, $page, $contents, $summary, %args ) = @_;
	return 0 unless defined $page and defined $contents;

	$self->login( ) unless $self->{_logged_in};
	return 0        unless $self->{_logged_in};

	my $minor = $args{minor};
	my $watch = $args{watch};

	my $res = $self->{_ua}->get(
		$self->{_wiki} . "?title=$page&action=edit",
		$self->{_headers}
	);
	return 0 unless 200 == $res->code;

	my ( $Edittime, $EditToken );
	my @forms = HTML::Form->parse( $res );
	for my $f ( @forms ) {
		next unless $f->attr( 'name' ) eq 'editform';
		$EditToken = $f->value( 'wpEditToken' ) if defined $f->find_input( 'wpEditToken' );
		$Edittime  = $f->value( 'wpEdittime'  ) if defined $f->find_input( 'wpEdittime' );
		$minor     = $f->value( 'wpMinoredit' ) if defined $f->find_input( 'wpMinoredit' ) and not defined $minor;
		$watch     = $f->value( 'wpWatchthis' ) if defined $f->find_input( 'wpWatchthis' ) and not defined $watch;
	}
	return 0 unless defined $EditToken;

	my %post = (
		wpTextbox1  => $contents,
		wpSummary   => $summary,
		wpEdittime  => $Edittime,
		wpEditToken => $EditToken
	);
	$post{wpMinoredit} = 1 if $minor;
	$post{wpWatchthis} = 1 if $watch;

	$res = $self->{_ua}->post(
		$self->{_wiki} . "?title=$page&action=submit",
		$self->{_headers},
		Content => [ %post ]
	);

	return ( 302 == $res->code );
}

## TODO
sub download {
	my $self = shift;
	return undef;
}

## TODO
sub downloadAllRevisions {
	my $self = shift;
	return undef;
}

sub upload {
	my ($self, $file, $summary) = @_;
	return 0 unless defined $file;

	my $res = $self->{_ua}->post(
		$self->{_wiki} . '?title=Special:Upload',
		$self->{_headers},
		Content => [
			wpUploadFile => [ $file ],
			wpUploadDescription => $summary,
			wpUpload => 1,
			wpUploadAffirm => 1
			# Note: wpUploadCopyStatus and wpUploadSource should be sent if $wgUseCopyrightUpload is true
		]
	);
	return 1 if 302 == $res;

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

sub protect {
	my ( $self, $page, $reason, $onlyMoves ) = @_;

	$self->login( ) unless $self->{_logged_in};
	return 0        unless $self->{_logged_in};

	my $res = $self->{_ua}->get(
		$self->{_wiki} . "?title=$page&action=protect",
		$self->{_headers}
	);
	return 0 unless 200 == $res->code;

	my $EditToken;
	my @forms = HTML::Form->parse( $res );
	for my $f ( @forms ) {
		next unless $f->attr( 'id' ) eq 'protectconfirm';
		$EditToken = $f->value( 'wpEditToken' ) if defined $f->find_input( 'wpEditToken' );
	}
	return 0 unless defined $EditToken;

	my %post = (
		wpReasonProtect => $reason,
		wpConfirmProtect => 1,
		wpConfirmProtectB => 1,
		wpEditToken => $EditToken
	);
	$post{wpMoveOnly} = 1 if $onlyMoves;

	$res = $self->{_ua}->post(
		$self->{_wiki} . "?title=$page&action=protect",
		$self->{_headers},
		Content => [ %post ]
	);

	return ( 302 == $res->code );
}

sub unprotect {
	my ( $self, $page, $reason ) = @_;

	$self->login( ) unless $self->{_logged_in};
	return 0        unless $self->{_logged_in};

	my $res = $self->{_ua}->get(
		$self->{_wiki} . "?title=$page&action=unprotect",
		$self->{_headers}
	);
	return 0 unless 200 == $res->code;

	my ( $EditToken );
	my @forms = HTML::Form->parse( $res );
	for my $f ( @forms ) {
		next unless $f->attr( 'id' ) eq 'protectconfirm';
		$EditToken = $f->value( 'wpEditToken' ) if defined $f->find_input( 'wpEditToken' );
	}
	return 0 unless defined $EditToken;

	$res = $self->{_ua}->post(
		$self->{_wiki} . "?title=$page&action=unprotect",
		$self->{_headers},
		Content => [
			wpReasonProtect => $reason,
			wpConfirmProtect => 1,
			wpConfirmProtectB => 1,
			wpEditToken => $EditToken
		]
	);

	return ( 302 == $res->code );
}

sub watch {
	my ( $self, $page ) = @_;

	$self->login( ) unless $self->{_logged_in};
	return 0        unless $self->{_logged_in};

	my $res = $self->{_ua}->get(
		$self->{_wiki} . "?title=$page&action=watch",
		$self->{_headers}
	);

	return ( 200 == $res->code );
}

sub unwatch {
	my ( $self, $page ) = @_;

	$self->login( ) unless $self->{_logged_in};
	return 0        unless $self->{_logged_in};

	my $res = $self->{_ua}->get(
		$self->{_wiki} . "?title=$page&action=unwatch",
		$self->{_headers}
	);

	return ( 200 == $res->code );
}

sub delete {
	my ( $self, $page, $reason ) = @_;
	return 0 unless defined $page;

	$self->login( ) unless $self->{_logged_in};
	return 0        unless $self->{_logged_in};

	my $res = $self->{_ua}->get(
		$self->{_wiki} . "?title=$page&action=delete",
		$self->{_headers}
	);
	return 0 unless 200 == $res->code;

	my $EditToken;
	my @forms = HTML::Form->parse( $res );
	for my $f ( @forms ) {
		next unless $f->attr( 'id' ) eq 'deleteconfirm';
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

	return ( 200 == $res->code );
}

sub move {
	my ( $self, $page, $newname, $moveTalkToo ) = @_;
	return 0 unless defined $newname;

	$self->login( ) unless $self->{_logged_in};
	return 0        unless $self->{_logged_in};

	my $res = $self->{_ua}->get(
		$self->{_wiki} . "?title=Special:Movepage&target=$page",
		$self->{_headers}
	);
	return 0 unless 200 == $res->code;

	my ( $EditToken, $Movetalk );
	my @forms = HTML::Form->parse( $res );
	for my $f ( @forms ) {
		next unless $f->attr( 'id' ) eq 'movepage';
		$EditToken = $f->value( 'wpEditToken' ) if defined $f->find_input( 'wpEditToken' );
		$Movetalk  = $f->value( 'wpMovetalk'  ) if defined $f->find_input( 'wpMovetalk' );
	}
	return 0 unless defined $EditToken;

	my %post = (
		wpNewTitle => $newname,
		wpOldTitle => $page,
		wpMove => 1,
		wpEditToken => $EditToken
	);
	if ( defined( $moveTalkToo ) ) {
		$post{wpMovetalk} = $moveTalkToo ? 1 : 0;
	} elsif ( defined( $Movetalk ) ) {
		$post{wpMovetalk} = $Movetalk;
	}

	$res = $self->{_ua}->post(
		$self->{_wiki} . "?title=Special:Movepage&action=submit",
		$self->{_headers},
		Content => [ %post ]
	);

	return ( 302 == $res->code );
}

## TODO
sub isProtected {
	my ( $self ) = shift;
	return undef;
}

sub isWatched {
	my ( $self, $page ) = @_;
	return 0 unless defined $page;

	$self->login( ) unless $self->{_logged_in};
	return 0        unless $self->{_logged_in};

	my $res = $self->{_ua}->get(
		$self->{_wiki} . "?title=$page&action=edit",
		$self->{_headers}
	);
	return 0 unless 200 == $res->code;

	my $Watchthis;
	my @forms = HTML::Form->parse( $res );
	my $i;
	for my $f ( @forms ) {
		next unless $f->attr( 'name' ) eq 'editform';
		$i = $f->find_input( 'wpWatchthis' );
		return ( $i->value eq ($i->possible_values)[1] ) if defined $i and defined $i->value;
	}
	return 0;
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
		my $uri = URI->new( shift );
		my $path = $uri->path;
		$uri->path( $path . 'index.php' );
		$self->{_wiki}      = $uri->as_string;
		$self->{_logged_in} = 0;
	}
	return $self->{_wiki};
}

sub logged_in {
	my $self = shift;
	return $self->{_logged_in};
}

##
## Internal functions
##

sub _get {
	my ( $self, $curonly, @reqs ) = @_;
	my %results = ();

	my %post = (
		action => 'submit',
		pages => join( "\r\n", @reqs )
	);
	$post{curonly} = 1 if $curonly;
	my $res = $self->{_ua}->post(
		$self->{_wiki} . '?title=Special:Export',
		$self->{_headers},
		Content => [ %post ]
	);
	return undef unless $res->content_type eq 'text/xml' or $res->content_type eq 'application/xml';

	my $page = Net::Anura::ExportParser::parse( $res->content );
	my @pages;

	foreach my $k ( keys %$page ) {
		push @pages, Net::Anura::Page->new( $k, %{ $$page{$k} } );
	}

	return @pages;
}

sub _scancookies {
	my ( $self, ) = @_;
	my %cookie;
	my %prefixes;

	$self->{_cookie_jar}->scan(
		sub {
#			my ( $version, $key, $val, $path, $domain, $port, $pathspec, $secure, $expires, $discard, $hash ) = @_;
			my ( undef,    $key, $val, undef, $domain, undef, undef,     undef,   $expires, undef,    undef ) = @_;
			return if ( $expires <= time || $self->{_host} ne $domain );
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
