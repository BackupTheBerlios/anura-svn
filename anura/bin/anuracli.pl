#!/usr/bin/perl

use strict;
use warnings;

use Net::Anura;

my $anura = Net::Anura->new(
	baseurl => 'http://en.wikipedia.org/wiki',
	username => 'User',
	password => 'password'
);
if ( ! $anura->login( ) ) {
	die "unable to log into wiki\n";
}

my $art = $anura->getPage( 'Color vision' );
die if ( ! defined( $art ) );

my $a2 = Net::Anura->new(
	baseurl => 'http://wiki.zive.ca/wiki',
	username => 'User',
	password => 'password'
);
if ( ! $a2->login( ) ) {
	die "unable to log into zive\n";
}
print $a2->putPage( 'Color vision', $art, 'Article transfer' ), "\n";
