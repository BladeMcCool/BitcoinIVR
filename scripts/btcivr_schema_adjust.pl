#!/usr/bin/perl
use strict;
use lib '/home/ubuntu/spapp_dev/lib_spapp';
$| = 1;
BEGIN {
	use Carp;
	$SIG{__WARN__} = \&carp;
	$SIG{__DIE__} = \&confess;
}
my $helper = BTCSys::SchemaAdjuster->new(PARAMS => { '_app_name' => 'btcsys', config_path => '/etc/asterisk/phoneapp/conf/phoneapp.conf' });
$helper->run();
	
1;

################
package BTCSys::SchemaAdjuster;
use strict;
use base ("SpApp::StandaloneUtil");
use CaptchaQuest::BTCDataObjects;

sub _start_mode {
	#return 'logged_in_redirect';
	return 'adjust_tables';
}
sub _runmode_map {
	my $self = shift;
	return {
		#'restricted_example' => {rm_sub=>'subname_can_differ', level=>20, auth_subref=>\&_some_bool_returning_subref, rsf=>['has_passed_test1','has_passed_test2']}, #rm_sub is different from rm name, not public (no pub=>1 present), min userlevel 20, and even then still has to pass credential check in a user function called (in this case) _check_restricted_mode_credentials, and also has to have two (in this case) specific session flags set.
		'adjust_tables'  => {pub=>1}, 
	};
}

sub adjust_tables {
	my $self = shift;
	
	#note: this should create them if they dont exist, or alter them if you added new fields to the dataobject and want to add them to the schema too.
	
	CaptchaQuest::BTCDataObj::BTCSysUser->new($self)->create_table({alter=>1});
	CaptchaQuest::BTCDataObj::BTCSysAddressbook->new($self)->create_table({alter=>1});
	CaptchaQuest::BTCDataObj::BTCSysSMSJunk->new($self)->create_table({alter=>1});
	
	return "Tables Altered or Created";
}