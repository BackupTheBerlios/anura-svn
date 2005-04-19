package Net::Anura;

use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Cookies;
use HTML::Form;

BEGIN {
	use Exporter   ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

	$VERSION     = sprintf("%d.%02d", 0.1 =~ /(\d+)\.(\d+)/);

	@ISA         = qw(Exporter);
	@EXPORT      = ();     # e.g.: qw(&func1 &func2 &func4)
	%EXPORT_TAGS = ();     # e.g.: TAG => [ qw!name1 name2! ],

	# your exported package globals go here,
	# as well as any optionally exported functions
	@EXPORT_OK   = ();     # e.g.: qw($Var1 %Hashit &func3)
}

our @EXPORT_OK;

sub new {
	my $proto = shift;
	my $baseurl = shift;
	my $class = ref $proto || $proto;
	my $self  = { };

	my %args = @_;
	$self->{_baseurl}    = $baseurl                 ? $baseurl          : undef;
	$self->{_cookiefile} = exists $args{cookie_jar} ? $args{cookie_jar} : "$ENV{HOME}/.anura";

	($self->{_host})     = $self->{_baseurl} =~ m#^https?://([^/]+).*#i;
	$self->{_cookie_jar} = HTTP::Cookies->new( file => $self->{_cookiefile}, autosave => 1 );
	$self->{_ua}         = LWP::UserAgent->new( agent => "Anura", cookie_jar => $self->{_cookie_jar} );
	$self->{_headers}    = [ Host => $self->{_host} ];

	$self->{_logged_in}  = 0;

	bless ($self, $class);
	return $self;
}

#
# Login and logout
# 

sub login {
	my $self = shift;
	return 1 if $self->{_logged_in};

	if ( $self->_scancookies( $self->{_host} ) ) {
		$self->{_logged_in} = 1;
		return 1;
	}
	($self->{_user}, $self->{_password}) = @_;

	my $res = $self->{_ua}->post(
		$self->{_baseurl} . "?title=Special:Userlogin&action=submitlogin",
		$self->{_headers},
		Content => [
			wpName         => $self->{_user},
			wpPassword     => $self->{_password},
			wpRemember     => 1,
			wpLoginAttempt => 1
		]
	);

	$self->{_logged_in} = ( 302 == $res->code );
	return $self;
}

sub logout {
	my $self = shift;
	return 1 unless $self->{_logged_in};

	my $res = $self->{_ua}->post(
		$self->{_baseurl} . "?title=Special:Userlogout",
		$self->{_headers}
	);

	$self->{_logged_in} = 0;
	return 1;
}

#
# Page manipulation
#

#
# Editing
#

# TODO: Rewrite this to use Special:Export
sub get {
	my ( $self, $page ) = @_;
	return undef unless defined $page;

	my $res = $self->{_ua}->get(
		$self->{_baseurl} . "?title=$page&action=raw",
		$self->{_headers}
	);

	return $res->content if ( 200 == $res->code );
	return undef;
}

sub put {
	my ( $self, $page, $contents, $summary, %args ) = @_;
	return 0 unless defined $page and defined $contents;

	my $minor = $args{minor};
	my $watch = $args{watch};

	my $link = $self->{_baseurl} . "/$page";
	my $res = $self->{_ua}->get(
		"$link?action=edit",
		$self->{_headers}
	);

	return 0 if ( 200 != $res->code );

	my @forms = HTML::Form->parse( $res->content, "$link?action=edit" );
	my ( $Edittime, $EditToken );
	for my $f ( @forms ) {
		next if ( $f->attr( 'name' ) ne 'editform' );

		$EditToken = $f->value( 'wpEditToken' ) if defined $f->find_input( 'wpEditToken' );
		$Edittime  = $f->value( 'wpEdittime'  ) if defined $f->find_input( 'wpEdittime' );
	}

	return 0 unless defined $EditToken;

	my %post = (
		#wpSave      => 1, # Not used in HEAD or REL1_4 -ævar
		wpTextbox1  => $contents,
		wpSummary   => $summary,
		wpEdittime  => $Edittime,
		wpEditToken => $EditToken
	);
	$post{wpMinoredit} = 1 if $minor;
	$post{wpWatchthis} = 1 if $watch;

	$res = $self->{_ua}->post(
		"$link?action=submit",
		$self->{_headers},
		Content => [ %post ]
	);

	return ( 302 == $res->code );
}

#
# Deleting
#

sub delete {
	my ($self, $page, $reason) = @_;
	return 0 unless defined $page;

	my $res = $self->{_ua}->get(
		$self->{_baseurl} . "?title=$page&action=delete",
		$self->{_headers}
	);
	
	return 0 if ( 200 != $res->code );

	(my $wpEditToken) = $res->content =~ /name='wpEditToken' value="([a-z0-9]{32})"/;
	return 0 unless defined $wpEditToken;
	print $wpEditToken;
	my %post = (
		wpReason => $reason,
		wpConfirm => 1, # Needed for REL1_4, no longer exists in REL1_5
		wpConfirmB => 1,
		wpEditToken => $wpEditToken
	);

	$res = $self->{_ua}->post(
		$self->{_baseurl} . "?title=$page&action=delete",
		$self->{_headers},
		Content => [ %post ]
	);

	return ( 302 == $res->code );
}

#
# Uploading
#

sub upload {
	my ($self, $file, $summary) = @_;
	return 0 unless defined $file;

	my %post = (
		wpUploadFile => [ $file ],
		wpUploadDescription => $summary,
		wpUpload => 1,
		wpUploadAffirm => 1
		# Note: wpUploadCopyStatus and wpUploadSource should be sent if $wgUseCopyrightUpload is true
	);
	
	my $res = $self->{_ua}->post(
                $self->{_baseurl} . '/Special:Upload',
		$self->{_headers},
		Content_Type => 'multipart/form-data',
                Content => [ %post ]
	);

	if ($res->content =~ /<h4 class='error'>(.*)(?=<\/h4>)/) {
		#(my $error = $1) =~ s/<[^>]*>//g; # TODO: Do something smart with this.
	} elsif ($res->content =~ m#<ul class='warning'>(.*?)(?=</ul>)#s) {
		print "We got a warning\n";
		#(my $error = $1) =~ s/<[^>]*>//g;
		(my $wpSessionKey) = $res->content =~ m#name='wpSessionKey' value="(\d+)"#g;
		my $affirm = $self->{_ua}->post(
			$self->{_baseurl} . '?title=Special:Upload&action=submit',
			$self->{_headers},
			Content_Type => 'multipart/form-data',
			Content => [
				wpUploadDescription => $summary,
				wpUpload => 1,
				wpUploadAffirm => 1,
				wpIgnoreWarning => 1,
				wpSessionKey => $wpSessionKey
			]
		);
	}

	return ( 302 == $res->code );
}

#
# Functions to return values made in sub new
#

sub user {
	my $self = shift;
	if ( @_ ) {
		$self->{_user}  = shift;
		$self->{_logged_in} = 0;
	}
	return $self->{_user};
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

#
# Misc internal functions
#

sub _scancookies {
	my ( $self, $host ) = @_;
	my %cookie = ();
	
	$self->{_cookie_jar}->scan(
		sub {
			my ( $version, $key, $val, $path, $domain, $port, $pathspec, $secure, $expires, $discard, $hash ) = @_;
			return if ( $expires <= time || $host ne $domain );
			$cookie{$1} = $val if ( $key =~ /(Token|UserID|UserName)$/i );
		}
	);
	return 1 if $cookie{'User'} eq $self->{_user}
		and exists $cookie{'Token'}
		and exists $cookie{'UserID'}
		and exists $cookie{'UserName'};
	return 0;
}

1;

__END__
