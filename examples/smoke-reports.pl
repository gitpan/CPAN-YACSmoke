#!/usr/bin/perl -w
use strict;

use lib qw(lib);

use CPAN::YACSmoke;

my %conf  = (
	list_from	=> 'SmokeDB',		# use SmokeDB plugin

#	list_from	=> 'Recent',		# use Recent plugin

#	list_from	=> 'Outlook',		# use Outlook plugin
#	mailbox		=> 'CPAN Testers',

#	list_from	=> 'NNTP',			# use NNTP plugin
#	list_from	=> 'NNTPWeb',		# use NNTPWeb plugin
#	nntp_id		=> '180500',

#	list_from	=> 'WebList',		# use WebList plugin

	audit_log	=> 'audit.log',
	config_file	=> 'cpansmoke.ini',
);

mark(\%conf);
#excluded(\%conf);
