use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
	NAME		=> 'Net::Anura',
	ABSTRACT	=> 'Anura, an interface to MediaWiki wikis',
	VERSION_FROM	=> 'lib/Net/Anura.pm', # finds $VERSION
);
