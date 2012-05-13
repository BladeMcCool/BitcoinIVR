package SpApp::Core;

use strict;
use base 'CGI::Application';
use FlatFile; #not oo ... doh. maybe I should do something about that. and then I could put it into the startup.pl or vhost.conf, couldnt I.
use CGI::Application::Plugin::Session; #this pretty much has to go here b/c it imports things into the namespace here. so I understand.
use CGI::Application::Plugin::FillInForm (qw/fill_form/); #see the docs. adding for the CMCreg redev custom form thing.
use Time::Piece;
use Text::Wrap;
use FreezeThaw qw(freeze thaw);
use Convert::ASCII::Armour;
use SpApp::Auth;
use SpApp::Strings;
use Encode;
use Number::Format;
use Net::SMTP;
use MIME::Lite;
use Clone;
use SpApp::DataObjects;

use utf8;

#this is causing warnings about namespace issuse or something and I already know I'm on mp2 so I will stop using this!
#use constant MP2 => ( exists $ENV{MOD_PERL_API_VERSION} and $ENV{MOD_PERL_API_VERSION} >= 2 ); #suggested by http://perl.apache.org/docs/2.0/user/coding/coding.html#Environment_Variables

#so I'm learning some stuff about mod_perl -- actuall probably learning more than I realize. Anyhow, I want to have a package variable for the SpApp::Core that will retain the config file info so it only needs to be read once for each multi-request-serving httpd process
my $_ALL_CONFIG = {}; #ok, stuff below for _CONFIG and _LOAD_STATE wasnt working right with mod_perl .. was getting app label from other app appearing and shit. no good. trying to make a universal var that has keys for each instance of each app so as to keep it all separated.
my $_ALL_LOAD_STATE = {}; #same purpose as all_config. see note above.

my $_CONFIG = undef; #now quite possibly I'll need to change this to be a global hash to store all app config's from all hosts and use a hostname_appname key to store the config hashref's but for now I'm gonna try this. The concern is that when other domains go to use this code then there will be conflicts because they'll all be trying to use the identical package.
my $_LOAD_STATE = undef; #toying with idea of how to keep track of checks for various things like paths existing, so that maybe we can only bother with them once.
my $_DB_PARAMS = undef;

sub cgiapp_init {
	my $self = shift;

	$self->_init_environment(); #now hoping to be able to set up and work in a mp handler or as a standalone registry dealo. ... yikes or not. But abstract env info is good anyway.
	
	#figure out where we live in the server filesystem.
	my $vhost_root = $self->env('document_root');
	$vhost_root =~ s|(.*)/.*|$1|; #strip last dir off (usually httpdocs) to get siteroot dir

	#and figure out what is the script file and the protocol we're using.
	#my $script_name = $ENV{REDIRECT_URL} ? $ENV{REDIRECT_URL} : $ENV{SCRIPT_NAME}; #if the script name part of the url is rewritten by mod_rewrite, make use of that name.
	#not sure why i wanted to use the above. can tell you its screwing up redirect_runmode with rewrite rules that already specify a runmode for html files. meaning that I can't then use a real runmode if that is the script that gets redirected to.
	my $script_name = $self->param('script_name_override') ? $self->param('script_name_override') : $self->env('script_name'); 
	#my $web_prot = ($ENV{SERVER_PORT} eq '443') ? 'https://' : 'http://'; #decide whether we are using http or https ... hint, if the doc root is httpsdocs and we got here on port 443, we're doing https.
	my $web_prot = ($self->env('https') eq 'on') ? 'https://' : 'http://'; #decide whether we are using http or https ... hint, if the doc root is httpsdocs and we got here on port 443, we're doing https.

	#config independent stuff:
	$self->param('_script_url_prefix', $web_prot . $self->env('http_host')); 
	$self->param('_http_script_url_prefix', 'http://' . $self->env('http_host')); 
	$self->param('_https_script_url_prefix', 'https://' . $self->env('http_host')); 
	$self->param('_script_name', $script_name); 
	$self->param('_vhost_root', $vhost_root);
	#$self->param('_tmpl_path', $vhost_root . '/tmpl_' . $self->param('_app_name'));
	#$self->param('_tmpl_cache_path', $vhost_root . '/tmpl_cache_' . $self->param('_app_name'));
	#note I am making the tmpl_parhs now config dependant and removing shared tmpl path concept entirely until such time as its needed and a sensible implementation could be pondered over.
	#$zipp->param('_shared_tmpl_path', $vhost_root . '/tmpl_shared'); #should be a symlink to the shared template path. assuming i implement it.
	#print $losp->sucks.

	
	#get config and load state set up.
	my $debug_loaded_config = 0;
	#app id should be unique across the whole system -- must accommodate multiple versions of multiple apps running on a single vhost. 
#	my $app_id = $self->env('http_host')  . '|' . $self->param('_app_name') . '|' . ($self->param('_conf_name') ? $self->param('_conf_name') : 'default');
#	$self->param('_app_id' => $app_id); #for easy access by all.
	my $app_id = $self->param('_app_id');
	#$self->debuglog(["cgiapp_init: $app_id for PID $$ is set to:", $app_id]);
	
	#idea for future - cache config at a param named by the vhost+conf_file_name, instead of the app name. that will be safer. Right now the conf file name is determined in read_conf though ... when that change is made, it should also become easier to implement config-cache-disabling via the conf file :)
	$_CONFIG = $_ALL_CONFIG->{$app_id}; #that key must be unique system-wide. mod_perlish stuff.
	$_LOAD_STATE = $_ALL_LOAD_STATE->{$app_id}; #that key must be unique system-wide. mod_perlish stuff.
	if (!defined($_LOAD_STATE)) {
		#btw doing this b/c we need to establish a hashref and stick it back into the all_load_state if we havent done so already. otherwise it never 'sticks'.
		$_LOAD_STATE = {};
		$_ALL_LOAD_STATE->{$app_id} = $_LOAD_STATE;
	}

	#2007 02 05 - I want to be able to force reloading of configuration without having to restart apache.
	if ($self->query()->param('reload_conf') || $self->query()->param('reload_config')) {
		$_CONFIG = undef;
	}
	
	my $cache_config = 0;
	if (!$_CONFIG || !$cache_config) {
		#maybe umm the key should be the conf file name on the vhost instead? i see myself potentially having a problem with it like below ... but whatever for now!
		$_ALL_CONFIG->{$app_id} = $_CONFIG = $self->read_config(); #coded like so b/c read_config will return a new hashref ... we gotta make sure it gets back into the all_config.
		$_LOAD_STATE->{read_config} = 1;
		$debug_loaded_config = 1; #b/c we just loaded it.
	}
	$self->param('_config', $_CONFIG); #would rather the config func refer to a self->param.
	#$self->debuglog(['in cgiapp_init with a config like:', $self->param('_config')]);
	#die "stop the broken";
	
	#config dependent stuff:
	my $session_dir = $self->config('session_dir'); #if not provided in config file then default 'sessions' will be used.
	if (!$session_dir) { $session_dir = $self->_session_dir(); } #another way to get something different for the session dir (adding for beemak, just want to define it in the subclass to use sessions_oms)
	#store the gathered info. yeah, this has to happen for every. single. request.
	$self->param('_session_path', $vhost_root . '/' . ($session_dir ? $session_dir : 'sessions'));
	$self->param('_app_label', $self->config('app_label'));	
	$self->param('_tmpl_path', $vhost_root . '/tmpl_' . $self->config('tmpldir_suffix'));
	$self->param('_tmpl_cache_path', $vhost_root . '/tmpl_cache_' . $self->config('tmpldir_suffix'));
	
	my $config_output_charset = $self->config('output_charset');
	my $charset = $config_output_charset ? $config_output_charset : 'utf-8'; #default to utf-8. makes it easier to go chinese.
	$self->header_props(-type => "text/html; charset=$charset"); 
	
	#really these are template specific .. moving them and a few new related things down there.
	#my $app_includes_suffix = $self->config('app_includes_suffix');
	#$self->param('_app_includes_dir', ($app_includes_suffix ? '/app_includes_' . $app_includes_suffix : '/app_includes')); #make it easy to set in the config file which app_includes dir to use -- adding this to have a dev version of the app_includes javascript stuff.
	
	#session and debug.
	$self->setup_session();
	$self->setup_debugmode();

	#note the below code is just for my debug / testing purposes and should eventually be removed or commented out.
	
	#check our config status and give some info.
	if ($debug_loaded_config) {
		#print STDERR "just loaded config file for an pid $$ with label " . $self->param('_app_label') . "\n";
	} else {
		#print STDERR "already loaded config file for an pid $$ with label " . $self->param('_app_label') . "\n";
	}

	#test the session out -- print to STDERR the contents of some session var, and update that var prior-to if it was supplied via the cgi.
#	my $tstr = $self->query->param('tstr');
#	my $addtl_debug = '';
#	if ($tstr) {
#		$self->session->param('test' => $tstr);
#		$addtl_debug = ' ... and we just saved the value from the cgi';
#	}
	#print STDERR "honoring request at " . time() . " for pid $$, session testvar is '" . $self->session->param('test') . "'" . $addtl_debug . "\n";

}

sub _init_environment {
	my $self = shift;
	my $args = shift;
	#this is an attempt to make my webapp run in a mp fixup handler, getting proper access to the environment.
		#set a bunch of vars insside param _env on self.
	
	my $r = $args->{_R}; #handlerUtil gives us this.
	my $standalone = $args->{standalone}; #standloneUtil gives us this.

	my $env = {};
	if ($r) {
		#mod_perl land. where I can't seem to find out if it is_https easily. have to install a bitch module Apache2::ModSSL that doesnt want to be installed. so fuck it. portlist defines https status.
		my $https_ports = { 443 => 1, 8443 => 1, 9443 => 1, 10443 => 1 }; #any others? hrmm ... how about changing this so its anything ending 443?
		my $port = $r->get_server_port();
		$env->{document_root} = $r->document_root();
		$env->{script_name}   = $r->uri(); #if we're a handler, then the uri that invoked the handler is probably the script name. 
		$env->{https}         = $https_ports->{$port} ? 'on' : 'off'; #have to install Apache2::ModSSL but the make for that blows up. figure out later. should be ok for now to fake this as 1 for now.
		#$env->{http_host}     = $r->hostname(); #i think theres actually another one called server_name that i might want to be using in both hanlder and registry modes
		#2007 07 24: in a mp handler, this hostname() method does not include the port, however the mp registry script env var HTTP_HOST does include it, and we've taken steps elsewhere to accommodate that. So for consistency (and to NOT break app_id's used to say, help store userinfo in the session) we must include the non-80 port on this.
		$env->{http_host}     = $r->hostname() . (($port == 80) ? '' : ":$port"); 
		$env->{remote_addr}   = $r->connection->remote_ip();

#		$self->debuglog(['_init_environment: stoppage ', $env->{http_host}, $r->hostname() ]);
#		die "stopping to see what the options are";
	} elsif ($standalone) {
		#not really sure what to use for this. I think I'll figure it out as I need it.
#		foreach (qw{DOCUMENT_ROOT SCRIPT_NAME HTTPS HTTP_HOST REMOTE_ADDR}) {
#			$env->{lc($_)} = '[env-nyi]';
#		}

		#cheese-it to figure out some host stuff - could be useful for sending emails from standalone scripts.
			#similar code here to figure out vhost as in StandaloneUtil.pm
		my $config_path = $self->query()->param('config');
		my $vhost_root = $config_path;
		$vhost_root =~ s|(.*)/(.*?)/.*|$1|; #if we had /home/httpd/vhosts/supersite.com/conf/cheeseit.conf we'd be keeping just the 'supersite.com' part.
		(my $host = $vhost_root) =~ s|.*/(.*)|$1|g; #the last dir of the vhost root would be the host.

		$env->{document_root} = $vhost_root . '/httpdocs';
		$env->{http_host}     = $host; 

		#and set the rest as NYI-able.
		foreach (qw{SCRIPT_NAME HTTPS REMOTE_ADDR}) {
			$env->{lc($_)} = '[env-nyi]';
		}

	} else {
		#Registry land (how come there an easy way to access https status here? and not in mod_perl land?!? argh.)
		foreach (qw{DOCUMENT_ROOT SCRIPT_NAME HTTPS HTTP_HOST REMOTE_ADDR}) {
			$env->{lc($_)} = $ENV{$_};
		}
	}

	#do a portless http_host, for convenience.
	($env->{http_host_portless} = $env->{http_host}) =~ s|:\d+$||;

	#do app id here now, one central place for it.
	my $app_id = $env->{'http_host'}  . '|' . $self->param('_app_name') . '|' . ($self->param('_conf_name') ? $self->param('_conf_name') : 'default');
	$self->param('_app_id' => $app_id);

	$self->param('_env' => $env);
}

#use this to access $ENV stuff now.
sub env {
	my $self = shift;
	my $get_param = shift;

	#get a particular _env var or get them all.
	my $env = $self->param('_env');
	return $get_param ? $env->{$get_param} : $env;
}

sub setup {
	my $self = shift;
	
	my $start_mode = $self->_start_mode();
	if ($self->param('force_start_mode')) {
		#need to be able to force a _different_ start mode based on an app param set via the instance script, implementing it for the wp_callback runmode which has to run without a rm being specified because the wp_callback is via a POST and we wont pick up a rm from the query line in that case (we also can't get wp to include it in their post vars)
		$start_mode = $self->param('force_start_mode');
	}
	
	$self->start_mode($start_mode);
	$self->mode_param('rm'); #would this _ever_ be different for us? if/when, start using a _mode_param method to obtain.
	$self->error_mode('error');

	my $std_runmodes = $self->_standard_modes();
	my $app_runmodes = $self->_runmode_map();
	
	#prep for cgiapp run_modes call.
	my %runmodes = map { $_ => $_ } @$std_runmodes; #always include all standard modes (thats why they are standard)
	foreach (keys(%$app_runmodes)) {
		$runmodes{$_} = $app_runmodes->{$_}->{rm_sub} ? $app_runmodes->{$_}->{rm_sub} : $_; #named by either rm_sub or just the key of the hash.
	}
	$self->run_modes(%runmodes); #to change runmodes, change things in _runmode_map, including overriding standard modes to make them non-public or whatever.

	#thinking about coding a hook for running a _spapp_setup() or something that the subclass could define.
		#yeeup. AbriaChart::Client will use it to set the corda server
		#and being used by Education::User to set up master template info (including the custom tmpl dir suffix) 
		#and being used by FormTool::Admin to set up names of databases to use for logically different actions. (formcontrol_db and data_db, as well as working db name.)
	$self->_spapp_setup();
}

sub error {
	my $self = shift;
	my $error_str = shift; #a copy of the $@ of the badness.

	#its been requested (by Jay at least) and I know myself it would be a nice thing to do, so here we have an error mode to output app errors in a pretty way, not a "OMG Server Belew UP!" kind of way.
		#along with error message, we can include particular client/request infos, and we can put a date on it.
		#should _probably_ be using a specific error handling sub-tmpl that could be overridden by each app, with a nice standardized one. do that when this stuff that was done for CMCReg is not good enough (hardcoded html attributes could make it ugly on another site, but this auto-scrolling div thing works nice on CMC)
	my $tp = localtime();
	my $tstr = $tp->ymd . ' ' . $tp->hms;
	my $userinfo = $self->get_userinfo();
	my $userid = $userinfo->{logged_in} ? $userinfo->{id} : '[Not Logged In]';
	my $app_id = $self->param('_app_id');
	my $support_email = 'support@shrinkingplanet.com';
	if ($self->config('support_email_address')) {
		$support_email = $self->config('support_email_address');
	}
	my $secure = $self->env('https') eq 'on' ? 'Yes' : 'No';
	my $info_str = qq{
		<div style="width: 555px; overflow-x: auto;">
			<p style="margin-bottom: 0px;">
				Date: $tstr<br/>
				PID: $$ <br/>
				Secure Connection: $secure <br/>
				App ID: $app_id<br/>
				User ID: $userid<br/>
				<br/>
				Error Details:<br/>
			</p>
			<pre style="margin-top: 0px; margin-bottom: 0px;">
				<p>$error_str</p>
			</pre>
			<h2 style="margin-bottom: 25px;">If this is an unexpected error, please forward the above information to <a href="mailto:$support_email?subject=Software Error">$support_email</a></h2>
		</div>
	};
	
	#update 2008 09 24 - just render the generic conf template directly here as opposed to calling generic_conf_controller which always wants to try to look strings up in the db --- this way we can see nice error screen without having to have db!
	my $error_tmpl = $self->_spapp_error_template();
	return $self->render_interface_tmpl($error_tmpl, {
		conf_heading => 'Software Error',
		conf_body    => $info_str,
	});
		
#	return $self->generic_conf_controller({ 
#		direct_strings => {
#			conf_heading => "Software Error",
#			conf_body => $info_str,
#		}, 
#	});
}
sub _spapp_error_template {
	return 'general/generic_conf.tmpl';
}


sub cgiapp_prerun {
	my $self = shift;
	my $rm = shift;

	my $std_runmodes = $self->_standard_modes();
	my $app_runmodes = $self->_runmode_map();
	my $orig_rm = $rm;
	
	my %public_runmodes = map { $_ => $_ } @$std_runmodes; #always include all standard modes (thats why they are standard). of course we could be UN-public-ificating them in a moment.
	foreach (keys(%$app_runmodes)) {
		if ($app_runmodes->{$_}->{pub}) { 
			$public_runmodes{$_} = 1;
		} else { 
			$public_runmodes{$_} = 0; #listing a standard runmode among the app runmode map without a pub=>1 will cause us here to un-publicify it.
		}
	}

#	#cookie debugging?
#	my $cookies_table = $self->query()->jar(); #scalar context
#	my @cookie_names  = $self->query()->jar(); #list context
#	my $sess_cookie_val  = $self->query()->jar('CGISESSID');
#	my $sniff_cookie_val = $self->query()->jar('cookies_support_sniff');
#	$self->debuglog(['cgiapp_prerun: before cookie test. sess id from session, cookie names, sess id pulled from receieved cookie. ., with a session cookie_support_verified status of:', $self->session()->id(), \@cookie_names, $sess_cookie_val, 'sniffed and thawed:', $sniff_cookie_val ]);
	###DEBUG: Forced 'already-set' state.
	#$self->session()->param('cookie_support_verified' => 1);
	#end cookie debugging.

	#$self->param('can_send_session_cookie' => 1); #experiment with ensuring to not send the cookie if its a redirect. cookie would be sent in postrun if it hasnt been and this is still true. could be a total red-herring as well.
	
	#cookie support check: probably here if we dont have a certain session var we should redirect into somewhere else that forcibly verifies the browser sends back the expected cookie. would need to have it remember the rm we were actually trying to go to before having to go off for that tedium.
	
	if ($self->_cookie_support_required($rm) && !$self->session()->param('cookie_support_verified')) {
		#havent verified ... so go into that. take note of the rm name they were trying to view. might also want to take note of cgi params, but not getting into that just yet. i think in reality if we dont pass this as the first thing then we'll never pass it and cgi params wont matter.
		my $cookietest_rm = $self->prerun_cookie_verification($rm);
		$self->debuglog(["cgiapp_prerun: for cookie test, rm was set from '$rm' to '$cookietest_rm', and the status of the cookie_support_verified session var is: ", $self->session()->param('cookie_support_verified'), 'and the session id is',  $self->session()->id() ]);
		$rm = $cookietest_rm;
		#return 1; #get out of here now - we have to go verify cookie (and thus session) support.
	}
	
	#is user accessing a non public rm without the required credentials (currently only the min userlevel thing, in future check_auth should be doing the auth_subref thing too)
	my $auth = 1;
	if (!$public_runmodes{$rm} && !$self->get_auth()->check_auth($rm)) {
		$auth = 0;
		
		$self->debuglog(["cgiapp_prerun: not authorized for non-public rm '$rm'."]);
		$self->ch_debug(["cgiapp_prerun: not authorized for non-public rm '$rm'.", 'public runmodes are:', \%public_runmodes ]);
	}

	#session flags check: if the requested mode has required session flags that havent been set, we should bail to an error screen. the situation should really only arise if user comes back to app after session has expired, or if user is lame and trying to break program flow.
		#just go over the list of required session flags (rsf) for the runmode, and bail if any of them are not true. this is pretty rudimentary.
	my $rsf = $app_runmodes->{$rm}->{rsf};
	if ($rsf) {
		if (ref($rsf) ne 'ARRAY') { $rsf = [ $rsf ]; }
		foreach (@$rsf) {
			if (!$self->session()->param($_)) { 
				$auth = 0;
				$self->debuglog(["cgiapp_prerun: insufficient session flags for rm '$rm'."]);
				$self->ch_debug(["cgiapp_prerun: insufficient session flags for rm '$rm'."]);
				last;
			}
		}
	}

	#if not auth'd for the rm, decide where to go instead.
	if (!$auth) {	
		my $unauth_rm = $self->_unauth_rm({ rm => $rm, orig_rm => $orig_rm}); #unless code above changes the two args will have the same value ... just trying to think ahead for if/when they dont.
		if (!$unauth_rm) { $unauth_rm = $self->_auth_params()->{show_login_rm}; }
		if (!$unauth_rm) { $unauth_rm = $self->_auth_params()->{bad_login_rm}; }
		if (!$unauth_rm) { $unauth_rm = 'show_login' } #hardcoded default that should do something. its this or the death commented out below.
		#if (!$rm) { die "Unauthorized. Unable to determine a rm to send you to for unauthorized status. Aborting." }

		$self->debuglog(["cgiapp_prerun: not authorized for rm '$rm'. sending to rm '$unauth_rm'"]);
		$self->ch_debug(["cgiapp_prerun: not authorized for rm '$rm'. sending to rm '$unauth_rm'"]);
		$rm = $unauth_rm;
	}


	$self->ch_debug(\%ENV);
	#no more having to check if a session var that is supposed to be a hashref actually is a hashref b/c now we can make a list of those and forcibly establish them!
	$self->setup_session_vars();
	
	#hook for running a _spapp_prerun() or something that the subclass could define, as sort of a last chance to change the runmode. (or do other stuff that depends on knowing the final rm)
	my $switch_rm = $self->_spapp_prerun($rm);
	#we expect to often get undef back from _spapp_prerun, so we'll only change the runmode if we get some true value.
	if ($switch_rm) { $rm = $switch_rm;}
	
	if ($rm ne $orig_rm) {
		$self->debuglog(["cgiapp_prerun: rm changed from originally requested '$orig_rm', to current '$rm'"]);
		$self->ch_debug(["cgiapp_prerun: rm changed from originally requested '$orig_rm', to current '$rm'"]);
		$self->prerun_mode($rm);
	} else {
		#$self->debuglog(["cgiapp_prerun: authorized for '$rm', proceeding with that"]);
		$self->ch_debug(["cgiapp_prerun: authorized for '$rm', proceeding with that"]);
	}

}

sub _runmode_map { #override in subclass.
	my $self = shift;
	
	die "Must define _runmode_map in the subclass";

	#must return an hashref of hashrefs. keys of main hashref must be runmode names. each runmode hashref can contain:
		#rm_sub      (mapping to function name) which is not the same as the runmode name. can be ommitted if the function is the same name as the rm.
		#pub         (boolean flag as to whether it is a publicly available runmode)
		#userlevel   (the minimum userlevel for the mode. *** only even considered if it is not flagged as pub. )
		#auth_subref (a function reference to determine a boolean of wheter the runmode can be executed. *** only even considered if it is not flagged as pub. )
		#rsf         (required session flag(s). If just one, value can be a scalar. if more than one, value can be an arrayref of session var names. totally experimental. just going with simple logic that all required flags must be true for it to pass. if not working out, use a auth_subref to determine run-ability.

	#return {
	#	'restricted_example' => {rm_sub=>'subname_can_differ', userlevel=>20, auth_subref=>\&_some_bool_returning_subref, rsf=>['has_passed_test1','has_passed_test2']}, #rm_sub is different from rm name, not public (no pub=>1 present), min userlevel 20, and even then still has to pass credential check in a user function called (in this case) _check_restricted_mode_credentials, and also has to have two (in this case) specific session flags set.
	#};	
}
sub _session_hashrefs { return []; } #override in subclass.
sub _start_mode { die "_start_mode MUST be overridden by the subclass. must return a simple scalar giving the start_mode name."; } #MUST override in subclass.
sub _spapp_setup { return undef; } #if implemented in the subclass, would do some shit at the very end of the setup() routine.
sub _spapp_prerun { return undef; } #if subclass implements, it should return a runmode name to switch to or undef to not switch it (like when it just does something in this execution phase but dont want to switch the runmode that will run)
sub _app_common_tmpl_vars { return undef; } #if subclass implements, it should return a hashref. will be used by load_tmpl everytime it is called, including during typical getting of master template.
sub _cookie_support_required { return 1; } #default definition will always return 1.
sub _unauth_rm  { return undef; } #if implemented in the subclasses, would return scalar name of runmode to prerun-to to in cgiapp_prerun for unauthorized. i think usually we can use _auth_params though, for the show_login_rm or logged_out_rm.
sub _session_name { return undef; } #override this if you want to use something other than the default CGISESSID (adding so some beemak modperl stuff can access oms session - hope it works out)
sub _session_dir { return undef; } #override this if you want to save session data in a directory other than 'sessions' (also can use a config option which would take precedence over this)

#ensure all session params that we later on just assume have hashrefs at them do, in fact, have hashrefs at them.
	#because this always comes and bites me in the ass and I never want to have to think about this shit.
sub setup_session_vars {
	my $self = shift;

	my $core_establish     = [ 'valuesearched_for_record_id', 'valuesearched_form_values', 'screen_search_params'];
	my $subclass_establish = $self->_session_hashrefs();
	my $combined_establish = [ @$core_establish, @$subclass_establish ];
	#if (!$establish) { return undef; }
	foreach (@$combined_establish) {
		if (!defined($self->session()->param($_))) {	$self->session()->param($_ => {}); }
	}
}

sub standard_modes { die "API change. s.b. calling _standard_modes. And you shouldnt be needing to call it anyway since it should be being called for you due to other more profound API changes."; }
sub auth_params    { die "API change. s.b. calling _auth_params."; }

sub _standard_modes {
	my $self = shift;
	my $args = shift;
	
	#all these runmodes should be implemented by the SpApp::Core, but I dont see why subclass could not override any/all.
	return [
		'show_login',
		'process_login',
		'logout',
		'show_session_id',
		'simple_mail_preview',

		#cookie check
		#'prerun_cookie_verification',
		'cookie_verification', #dummy runmode. shouldnt ever be used, but will appear in redirects to be trapped by cgiapp_prerun, and thus in browser history for some ppl who will undoubtedly click on it like retards. so dont break over it.
		'redirect_cookie_test',
		'redirect_passed_cookie_test',
		'show_cookie_error',
		'show_redirect_error',
		'show_session_error',
			
#			#the code for this one has been moved into SpApp::Core.
		'edit_ajax_field_validation',
	];

#	
#	return $modes;
}

#been having issues lately that seem to trace back to luser browsers with broken/disabled cookie support. since we do _NOT_ pass sess id around via post/get request, it must be done via cookie.
	#set a new cookie
	#set a session param
	#redirect with a cgi param
	#pick up the cgi param
	#check that the broswer sent the cookie back and that it matches the session param
	#if so, there is cookie support, if not redirect to the "you suck for not having cookies" page.
sub prerun_cookie_verification {
	my $self = shift;
	my $requested_runmode = shift;
	
	#could be tricky with this, or could be cheesy. lets try something easy cheesy: set a session var, redirect to self trying to look for session var, if found, all good, if not found, BAIL!
	my $cgi = $self->query();
	my $cookie_name = $self->param('_app_id') . '_cookies_support_sniff';

	my $ip = $self->env('remote_addr');
	my $cv_for_ip = SpApp::DataObjects::CookieVerification->new($self)->find_record_for_edit({ criteria => { ip_address => $ip }, or_new => 1 }); #trying out the "or_new" stuff ... if it doesnt find a matching record, it'll create one, and it'll also automatically set the value for ip_address since it knows we know thats what we want to see in this record that we couldnt find.;
	my $aa = Convert::ASCII::Armour->new();

	if (!$cgi->param('verify')) {
		#no 'verify' param, we are on the first part ... set the cookie/param and redirect.

		#take note of the requested runmode. (doing it here now since doing it in prerun wont work - when we redirect to the dummy mode that rm would be picked up as the requested one!)
		#and capture all cgi params that were submitted so they will be present when we get to our final destination (assuming we pass the test).
		my @param_names = $cgi->param();
		my $params = { map { $_ => $cgi->param($_) } @param_names };
		delete $params->{$self->mode_param()}; #we'll be recording the requested runmode specially, so dont allow this particular query param to be present.
		my $cookie_val = freeze({
			requested_rm => $requested_runmode,
			query_params => $params,
		});

#		my $cookie_val = freeze("-->chocolate pudding<--");

		#borrowed this little bit from HTTP::CryptoCookie, i just want a proper encoding/storage of the cookie.
		my $cooked = $aa->armour(
			Object	=> 'CookieSniffParams',
			Headers	=> {},
			Content	=> {data=>$cookie_val},
			Compress => 0,
		);

		$self->debuglog(['prerun_cookie_verification: going to send this encoded/cooked/ascii-armored value for the cookie.', $cooked, 'which before hand is', $cookie_val ]);

		#get the cookie and set up for sending
		my $cookie = $cgi->cookie(-name  => $cookie_name, -value => $cooked, -expires => '+1d', -path => '/', -domain => $self->env('http_host_portless')	);
		$self->header_add(-cookie => $cookie);

		#die "see the text we'll send";
		
		#also I think its important to keep track of how many redirects we do for this before we succeed, just in case somehow the cookie_test_redirect itself fails and we end up looping infinitely through the redirect. if its more than a few, something is broken and we should just send to an error screen (from here). we'll kepp track by IP address, and when we're successful we'll reset the count.
			#dont want to end up ever with someone trapped in an infinite redirect!
		my $redirects = $cv_for_ip->get_edit_values()->{redir_count};
		if ($redirects > 10) {
			#reset count to let them try it again later.
			$cv_for_ip->set_edit_values({ redir_count => 0 })->save_edited_record();
			$self->debuglog(['prerun_cookie_verification: hrm, redirect error? we think there is anyway. s.b. sending to show_redirect_error']);
			return 'show_redirect_error'; #this'll be about inability to do a simple redirect with some extra params tacked on .... since we DID redirect 10 times to this runmode from the same IP without receiving the fecking CGI param! (and as soon as we get it we'll reset the count). The only way this error should show by accident is if more than 10 people behind a NAT try to establish a session all at the same time. not likely.
		}

		#what we usually want to do is just to do the redirect to ourself with the 'verify' cgi param.
		$cv_for_ip->set_edit_values({ redir_count => $redirects + 1 })->save_edited_record(); #update the count if we're here.
		$self->debuglog(['prerun_cookie_verification: sending back a rm redirect_cookie_test, to engage the verification process and ensure we get back the cookie we just set.']);
		return 'redirect_cookie_test';
			
	} else {
		#got the 'verify' param

		$self->debuglog(['prerun_cookie_verification: got "verify" cgi param, we are going to check to see that the cookie was sent back']);
		
		#great redirects with cgi params must work .. so unset that count shit.
		$cv_for_ip->set_edit_values({ redir_count => 0 })->save_edited_record();
		
		#verify and bail if needed. for cookie and for borked session too!
		my $cookies_verified = 1; #optimism
		my $cookie_value = undef;
		my $cookie_received = $cgi->cookie($cookie_name);
		my $unarmoured = $aa->unarmour($cookie_received);
		if (!$unarmoured) {
			$cookies_verified = 0;
			$self->debuglog(['prerun_cookie_verification: could not unarmour the value:', $aa->errstr() ]);
		} else {
			$cookie_value = (thaw($unarmoured->{Content}{data}))[0];
			#cookie value should always be a hashref. if its not, we have a problem.
			if (ref($cookie_value) ne 'HASH' || !exists($cookie_value->{query_params}) || !exists($cookie_value->{requested_rm})) {
				$cookies_verified = 0;
				$self->debuglog(['prerun_cookie_verification: something wrong with cookie value. not a hashref, or doesnt have a query_params or requested_rm key. cookie_value is:', $cookie_value ]);
			}			
			$self->debuglog(['prerun_cookie_verification received a cookie with the right name, it is like: ', $cookie_received, 'then decoded into data:', $cookie_value ]);
			#die "just look at that cookie";
		}
		
		if (!$cookies_verified)	{
			$self->debuglog(['prerun_cookie_verification: did not receive the cookie. got this (raw):', $cgi->cookie($cookie_name), 'for cookie named', $cookie_name ]);
			return 'show_cookie_error'; #standard mode, but i guess doesnt need to be since there we're going to set this as the prerun_mode 
		} else {
			#ok we think we are good to go.
			
			$self->debuglog(['prerun_cookie_verification: DID receive and verify cookie support.']);
			$self->ch_debug(['sent back the cookie! cookie value received was (raw): ', $cgi->cookie($cookie_name)]);
			###Not doing this bit because we should not be relying on the session for anything right yet.
	#		#now we should never really ever get here. But somehow, in case we do, handle it. Basically to be here they have to have passed the cookie test but somehow the session is broken anyway. That could still be useful to help find a problem where a cookie-support question would be a red herring.
	#		my $session_verified	= 1;
	#		if ($self->session()->param($cookie_name) ne $cookie_value) { $session_verified = 0; } #doh. session doh (session is broken probably 'as well'
	#
	#		if (!$session_verified) {
	#			$self->ch_debug(['got this unexpected val from the session param: ', $self->session()->param($cookie_name), $self->session()->dataref()]);
	#			return 'show_session_error'; #standard mode, and specially excluded from the cookie check.
	#		}
	
	
			#well, being here means we can skip the test from now on! yay.
				#and that we should be able to safely start using the session. right.
	#		#die "Right before we would be setting the cookie_support_verified => 1 thing -- b/c we think we passed the test! .. and then we'd be going to rm:  " . $self->session()->param('prerun_requested_rm'); 
			$self->session()->param(
				'inital_query_params'     => $cookie_value->{query_params},
				'prerun_requested_rm'     => $cookie_value->{requested_rm},
				'cookie_support_verified' => 1,
			);
			#why am I setting the session cookie manually? it should set itself.
			
			#my $cookie = $cgi->cookie(-name  => $self->session()->name(), -value => $self->session()->id(), -expires => '+1d', -path => '/', -domain => $self->env('http_host')	);
			#session cookie this time. should work if we passed the first thing.
			#$self->header_add(-cookie => $cookie);
	
			#send the session cookie now manually just to make sure its been sent. we _should_ get it back and keep the same session, and then hopefully send it out again with proper options on the next non-redirecting runmode.
			$self->debuglog(['prerun_cookie_verification: set the session flag and will be sending to redirect_passed_cookie_test']);
			return 'redirect_passed_cookie_test';

		}
	

	}
}


#!!!!
#remember, they dont request this mode, this mode name is just to have one to be trapped by prerun when the cookie sniff hasnt finished. its supposed to be a pseudo mode used in a trapped redirect only
#somehow people are trying to call this runmode. Its not really a real runmode. you are only supposed to be made to ask for it if you are in the middle of the cookie sniff, and then it should be intercepted by cgiapp prerun. but (probably browser history, or other stupidity) people _ARE_ trying to get to this rm. sooo .. just fucking work.
	#in fact, I think we sooo "shouldnt be here" that if someone asks for this directly then they will be shunted back through the whole sniffer process
	#we'll just be real dicks here, remove the flag from the session that might have had them skipping the cookie sniffer, and redirect to the start mode
sub cookie_verification () {
	my $self = shift;
	$self->debuglog(['inside rm cookie_verification, should not really ever be here']);
	$self->session()->param('cookie_support_verified' => undef); #woops! since you so keen on asking for the cookie verification process directly, guess what ... thats what you gonna get!
	my $next_rm = $self->_start_mode();
	#die "before sending you to $next_rm";
	return $self->redirect_runmode($next_rm);
}

sub redirect_cookie_test {
	my $self = shift;
	#$self->send_nocache_headers();
	return $self->redirect_runmode('cookie_verification', { 'verify' => 1, 'random' => $self->random_string({len=>32, charset=>'licenseplate'}) } ); #the cgi parameter is the important thing. the runmode name shouldnt matter since the only time we will ever run this is inside the cookie verification trap.
#	return $self->redirect_runmode('cookie_verification' ); #broken redirect without verify param, just to ensure the error screen comes up in the broken situation.
}
sub redirect_passed_cookie_test {
	my $self = shift;
	#$self->send_nocache_headers();
	$self->debuglog(['redirect_passed_cookie_test with recalled query params like: ', $self->session()->param('inital_query_params'), 'should be sending you to:', $self->session()->param('prerun_requested_rm') ]);
	return $self->redirect_runmode($self->session()->param('prerun_requested_rm'), $self->session()->param('inital_query_params')); #and finally route them to what they originally asked for. doing it via redirect to conceal the whole cookie verification process.
}
sub show_redirect_error {
	my $self = shift;
	return $self->generic_conf_controller({ 
		direct_strings => {
			conf_body => "<p>Your system appears to be responding to redirects incorrectly. Please remedy or contact our support team for assistance. <a href=\"" . $self->env('script_name') . "\">Click here to try again.</a></p>",
			conf_heading => 'Error',
		}, 
	});
}	
sub show_cookie_error { 
	my $self = shift;
	my $try_again_uri = $self->env('script_name');
	
	return $self->generic_conf_controller({ 
		direct_strings => {
			#conf_body => "<p>Cookies Are Required By This Application. Please Ensure Cookie Support is Enabled in Your Browser. Thank You. <a href=\"" . $self->env('script_name') . "\">Click here to try again.</a></p>",
			conf_body => qq{ 
				<p>Cookies are required by this application and must be enabled on your browser to proceed with your request. If you know how to enable cookie handling on your browser, please do so now. If you need assistance or would like more information about "cookies" and how to handle them, please <a target="_blank" href="http://www.shrinkingplanet.com/cookie_issues.html">click here</a>.</p>
				<p>Once cookie support is enabled in your browser, <a href="$try_again_uri">click here</a> to try your request again.</p>
			},
			conf_heading => 'Login Error - Incorrect Browser Settings',
		}, 
	});
}
#sub show_session_error {
#	my $self = shift;
#	return $self->generic_conf_controller({ 
#		direct_strings => {
#			conf_body => "<p>The Session appears broken, although cookie support appears to be working. <a href=\"" . $self->env('script_name') . "\">Click here to try again.</a></p>",
#			conf_heading => 'Error',
#		}, 
#	});
#
#}

sub show_session_id {
	my $self = shift;
	my $session_id = $self->session()->id();
	return "ID: $session_id Name: " . $self->session()->name();
}

sub setup_session {
	my $self = shift;
		
	#check our load state before bothering with filesystem checks.
	if (!$_LOAD_STATE->{checked_session_path}) {
		if (!-e $self->param('_session_path')) { die "setup_session: fatal error, sessions path '" . $self->param('_session_path') . "' does not exist"; }
		if (!-w $self->param('_session_path')) { die "setup_session: fatal error, sessions path '" . $self->param('_session_path') . "' exists but is not writable for me";	}
		if (!-r $self->param('_session_path')) { die "setup_session: fatal error, sessions path '" . $self->param('_session_path') . "' exists but is not readable for me";	}
		$_LOAD_STATE->{checked_session_path} = 1; #under mod perl we should only have this once per process ... gonna print to stderr to be sure.
		print STDERR "setup_session: just successfully checked the session path " . $self->param('_session_path') . " for pid $$\n";
	} else {
		#print STDERR "setup_session: already checked the session path for pid $$ and it was fine (you're seeing this)\n";
	}

	####DEBUG SHIT - trying to make IE accept a cookie from domains on my dev server. not sure what is wrong.
	#session setup -- giving the well-thought-out CGI::Application::Plugin::Session a try.

	#2008 09 10, if a method called _session_name defines something, ensure the cgi session uses it. seems only one instance of cgi session can exist in this app framework or weird cookie shit happens. (hopefully this solves it by letting us tell cgi session to use a different name, the name of the session used in the legacy app that we want to access session information from for beemak)
	if ($self->_session_name()) {
		CGI::Session->name($self->_session_name());
		#die "well, here the session name should be: " . $self->_session_name();
	}

	#note, session_config function introduced into CGIapp namespace by using the plugin up above.
	#in the fs this works (chmod 770): drwxrwx---    2 appdev   psaserv      4096 Apr 12 11:10 sessions
	$self->session_config($self->_session_config_params());

	#once and for all, dont fuck ourselves up over non-cookie browser lameness, ever, ever again. Ensure that we've verified the sess_id cookie is being sent back.
#	if (!$self->session()->param('_cookie_support_verified') {}

	#$self->header_add(-connection => 'close');
}

#override in subclass if you want to do it differently.
sub _session_config_params {
	my $self = shift;

	#2008 03 06 - A Note about session cookies and sessions across a domain and its subdomains (blumontcapital.com and fr.blumontcapital.com in particular at this time):
		#A situation arose where fr.blumontcapital.com was receiving session cookies from both blumontcapital.com and fr.blumontcapital.com. This turns out to be expected cookie behaviour.
		#But, with 2 cookies being received on fr. and both being the same name, it was possible that the session_id pulled from the cookies was the session_id from the other domain. that session being unavailable here would result in us settinga new cookie which we would still end up not receiving back (or actually we were getting it but along with the other one from the other domain and pulling out the wrong one) and get stuck in the cookie verification trap.
		#Solution should be to force a particular domain to be used in the outgoing cookie for situations where they should share. Also probably means ensuring the session store is the same place (either same db, or same/symlinked session dirs)
			#also, if, after implementing this, users complain of still having the problem, ensure they've deleted their cookies for the other subdomains before they try again.
		#Another solution might be to simply change the name of the session id param to include the domain information such that there can be no confusion (but that would preclude possibility of sharing session across subdomains withoug falling right back into the multiple-cookies-with-same-name trap.)
	my $session_cookie_domain = $self->env('http_host_portless');
	if ($self->config('session_cookie_domain')) {
		$session_cookie_domain = $self->config('session_cookie_domain');
	}
	return (
		CGI_SESSION_OPTIONS => ["driver:File;serializer:Storable", $self->query(), {Directory=>$self->param('_session_path')}],
		DEFAULT_EXPIRY      => '+7d',
		COOKIE_PARAMS       => { -expires => '+7d', -path => '/', -domain => $session_cookie_domain },
		#SEND_COOKIE         => 0, #we will manage manually. want to figure out what this IE problem is. maybe has something to do with sending the cookie with a redirect. dunno.
	);	
}

sub setup_debugmode {
	my $self = shift;
	
	my $cgi = $self->query();
	#turn debug mode on/off if required. this will cause the param debug_mode to be set in the template on load_template.
		#now to do it on a per-app basis.
	my $debug_name = $self->param('_app_name');
	if ($self->param('_debug_name')) { $debug_name = $self->param('_debug_name'); } #allow override -- since I just coded this override idea into read_config, and am now deciding I want per-app debuggery, and remembering that 'oh yeah doofus, most apps share app name between admin and user shit', i can override this too with _debug_name in instance script. yay :) -- err, well, of course actually I've got separate app names for them in this case so I dont really need to use this yet.
		
	if (lc($cgi->param('debug_mode')) eq 'on') {
		$self->session->param($debug_name . '_debug_mode', 1);
	} elsif (lc($cgi->param('debug_mode')) eq 'off') {
		$self->session->param($debug_name . '_debug_mode', 0);
	}
	
	#$self->debuglog(['setup_debugmode: prior to typical first use of session']);
	$self->param('debug_mode', $self->session()->param($debug_name . '_debug_mode')); #and set an app param with whatever the debug mode status is (makes for easy mode detection without haveing to ref the session)
	#$self->debuglog(['setup_debugmode: after to typical first use of session']);
	return undef;

}

sub read_config {
	my $self = shift;
	
	#this is where we would load things from a config file
		# - database connection information for use by sub connect_dbh
		# - application settings like app name
	my $conf_name = $self->param('_app_name');
	if ($self->param('_conf_name')) { $conf_name = $self->param('_conf_name'); } #allow override -- basically adding this so that my admin instance script can use a different app_name (so that when I log out of admin, my user session still works) and yet tell the admin thing to use the same conf file as the user thing.
	my $config_file = $self->param('_vhost_root') . '/conf/' . $conf_name . '.conf';
	if (!-e $config_file) {	die ("config file: $config_file dies not exist");	 }
	if (!-r $config_file) {	die ("config file: $config_file can not be read"); }

	my %config = configAccessRead($config_file);
	return \%config;
}

sub config {
	#convenience method. -- $self->param('_config') must already be established from cgiapp_init.
	my $self = shift;
	my $lookup = shift;
	if ($lookup) {
		#send back the requested value
		return $self->param('_config')->{$lookup};
	} else {
		#or give back a list of lookup choices.
		my $config = $self->param('_config');
		return keys(%$config);
	}
}

sub load_tmpl {
	# grab arguments
	my $self	= shift;
	my $tmpl_file	= shift;
	my $args = shift; #2007 03 21 I want to do a scalarref maybe instead of a filename (CMCReg)
	
	#check our load state before bothering with filesystem checks.

	if (!$_LOAD_STATE->{checked_tmpl_path}) {
		#check tmpl path
		if (!-e $self->param('_tmpl_path')) {	die "load_tmpl: fatal error, main template path '" . $self->param('_tmpl_path') . "' does not exist";	}
		if (!-r $self->param('_tmpl_path')) {	die "load_tmpl: fatal error, main template path '" . $self->param('_tmpl_path') . "' exists but is not readable by me";	}

		#check tmpl_cache path -- this is for HTML::Template::Compiled -- and we should really be preloading but I dont understand how to do it right. contact the author of the module probably.
		if (!-e $self->param('_tmpl_cache_path')) {	die "load_tmpl: fatal error, main template cache path '" . $self->param('_tmpl_cache_path') . "' does not exist";	}
		if (!-w $self->param('_tmpl_cache_path')) {	die "load_tmpl: fatal error, main template cache path '" . $self->param('_tmpl_cache_path') . "' exists but is not writable by me";	}
		if (!-r $self->param('_tmpl_cache_path')) {	die "load_tmpl: fatal error, main template cache path '" . $self->param('_tmpl_cache_path') . "' exists but is not readable by me";	}
		$_LOAD_STATE->{checked_tmpl_path} = 1; #under mod perl we should only have this once per process ... gonna print to stderr to be sure.
		#print STDERR "load_tmpl: just successfully checked the main tmpl path '" . $self->param('_tmpl_path') . "' for pid $$\n";
	} else {
		#print STDERR "load_tmpl: already checked the main tmpl path '" . $self->param('_tmpl_path') . "' for pid $$ and it was fine (you're seeing this)\n";
	}

	#gonna try this with HTML::Teamplate::Compiled. Not sure if I'm doing it right so that a compiled template will survive more than 1 request. but its supposed to output faster anyway regardless so that might not even matter.
	# create html template object
	#$HTML::Template::Compiled::NEW_CHECK = 0; #setting in startup.pl
	$self->ch_debug(['load_tmpl with HTC version: ', $HTML::Template::Compiled::VERSION, 'and tmpl path:', $self->param('_tmpl_path'), 'and tmpl cache:', $self->param('_tmpl_cache_path') ]);
	
	my $tmpl_path = [
		$self->param('_tmpl_path'),
		#$self->param('_shared_tmpl_path'),
	];
	if ($self->config('sitepilot_page_templates')) { 
		push(@$tmpl_path, $self->env('document_root'));
	}
	if ($args->{tmpl_path}) {
		push(@$tmpl_path, $args->{tmpl_path}); #2009 03 04 this was something i thought i needed that i didnt rally b/c you can code a full path to tmpl file. but i guess this might be useful anyway.
	}
	
	#establish HTC args.
	my %htc_args = (
		cache_dir               => $self->param('_tmpl_cache_path'), #again, I dont really know if I'm using this right. Confused by the docs as to how to cache them properly. I have a feeling that what I'm doing is going to either not work to cache at all, or will cache a separate copy for each bloody httpd thread. hrm. well what I've done seems to work for the filesystem cache, but yeah I still think the memory cache is going to have one of everything for each httpd thread.
		global_vars             => 2, #with HTC this being 2 should allow the ... notation for going up one level. which I want to be able to do inside loops. to access main tmpl vars. --- of course I couldnt get that to work reliably. after clearing the cache I got it to work for the first iteration of the loop then it fails .. very queer. docs say global_vars = 1 is best for speed so gonna try that and that should fix the issue anyways. Yeah that didnt work either. something aint right. a small proof of concept program worked properly. i dont know what is the deal. Update: there was a bug in HTC. Fixed in version 0.67. I helped point it out and demonstrate it to Tina (HTC maintainer). w00t. 
		loop_context_vars	      => 1, #with this as 1, includes with HTC dont seem to be using it, so shit isnt working. going to use the <TMPL_LOOP_CONTEXT> HTC feature instead, and only when needed. that'll save CPU in any case, according to the docs. #of course then they dropped <TMPL_LOOP_CONTEXT> in 0.79 and my templates that have it are breaking in the current release. ugh. so I guess I have to turn it on.
		#case_sensitive          => 1, #docs say this is best option for speed.
		path			              => $tmpl_path,
		search_path_on_include	=> 1,
		max_includes 		        => 10000
	);
	
	#from a file (normal) or from a scalarref (new for CMCReg)?
	if ($tmpl_file) {
		$htc_args{filename} = $tmpl_file;
	} elsif ($args->{scalarref}) {
		$htc_args{scalarref} = $args->{scalarref};
	}

	my $t = HTML::Template::Compiled->new(%htc_args);
	$t->clear_params(); #cached tmpls -- must always clear params before use? Seems so as that fixed the "whoa I didnt even SET a sub_tmpl so where the F is this html coming from" problem.

	#any templating vars that should get defaulted and/or overridden here?
	my $common_tmpl_vars = $self->get_common_tmpl_vars();
	#$self->dbg_print(['load_tmpl: setting these common tmpl vars: ', $common_tmpl_vars ]);
	#(override common defaults here if needed ...)
	$t->param($common_tmpl_vars);
	
	#hacking in a hook here for all templates ... _app_common_tmpl_vars ... shouldnt have to be defined but if it is should return a hashref.
	my $app_common_tmpl_vars = $self->_app_common_tmpl_vars();
	if ($app_common_tmpl_vars) { 
		$t->param($app_common_tmpl_vars);
	}

	#die "gonna send this APP_IMAGES_DIR to tmpl: $app_images_dir";
	my $userlevel = $self->get_userinfo()->{userlevel};
	$t->param( 'userlevel_' . $userlevel => 1); #adding this for template menu item control, to show items based on userlevel as a general ability.

	#provide language option to tmpl if we have it.
		#so we'll likely end up passing a var like lang_en or lang_fr to the template.
	my $lang = $self->param('lang');
	if ($lang) {
		$t->param('lang_' . $lang => 1); 
	}

	#debug mode flag if we have it.
	$t->param('debug_mode' => $self->param('debug_mode'));

	return $t;
}

#breaking this stuff into its own sub b/c I want to call it from the Strings get_strings function as well for templatable strings.	
sub get_common_tmpl_vars {
	my $self = shift;
	my $args = shift;
	
	#app includes should be all js and stuff related to input controls that is generally the same on all applications. mostly for Admin interfaces stuff.  Config file just sets a potential suffix.
	my $app_includes_dir = '/app_includes'; #basic default
	if ($self->config('app_includes_suffix')) {
		#this will probably always be ok being relative to site root.
		$app_includes_dir = '/app_includes_' . $self->config('app_includes_suffix');
	}

	#app images should be where Admin related images are housed. Config file just sets a potential suffix.
	my $app_images_dir = '/app_images'; #basic default
	if ($self->config('app_images_suffix')) {
		#this will probably always be ok being relative to site root.
		$app_images_dir = '/app_images_' . $self->config('app_images_suffix');
	}
	
	#client images are graphics for the client designs of their pretty and/or shitty websites. app related graphical elements that are client specicic too i imagine!
	my $client_img_dir = '/images';
	if ($self->config('client_img_dir')) {
		#this should assume that full url can be specified
		$client_img_dir = $self->config('client_img_dir');
	}

	#client specific includes directories. for the clients custom js, other resources and/or whatever.
	my $client_inc_dir = '/includes';
	if ($self->config('client_inc_dir')) {
		#this should assume that full url can be specified
		$client_inc_dir = $self->config('client_inc_dir');
	}

	return {
		'APP_LABEL'	              => $self->param('_app_label'),
		'APP_NAME'	              => $self->param('_app_name'),
		'SCRIPT_NAME'             => $self->param('_script_url_prefix') . $self->param('_script_name'),
		'SCRIPT_URL_PREFIX'       => $self->param('_script_url_prefix'),
		'HTTP_SCRIPT_URL_PREFIX'  => $self->param('_http_script_url_prefix'),
		'HTTPS_SCRIPT_URL_PREFIX' => $self->param('_https_script_url_prefix'),
		'VHOST_ROOT'              => $self->param('_vhost_root'),
		'MAIL_RETURN_NAME'        => $self->param('_mail_return_name'),

		'APP_INCLUDES_DIR'        => $app_includes_dir, #defined in this func.
		'APP_IMAGES_DIR'          => $app_images_dir, #defined in this func.
		'CLIENT_IMG_DIR'          => $client_img_dir, #defined in this func.
		'CLIENT_INC_DIR'          => $client_inc_dir, #defined in this func.

		#to help in debugging might be useful to include in a comment in output.
		'PID'                     => $$,
	};
}

#2007 02 09, wanting a generalized get_master_tmpl which can work with the new params I'm adding for _app_subtmpldir_suffix etc to have custom tmpls for an app instance. this is for cmc education originally.
	###Documentation!
sub get_master_tmpl {
	my $self = shift;
	my $other_args = shift;

	#if we are in this version of the get_master_tmpl then we should bloody well have at least a master_tmpl_filename and a subtmpl_dir coded
		#woops ... why the F do I need a subtmpldir coded? oh, I only need it if I want it automatcially prepended. ok well then I probably shouldnt fucking DIE over not having it. bitch.
	my $master_tmpl = $self->param('_app_master_tmpl'); #this is the sitepilot page -- the template smarts are found in access_control.3 in sitepilots static page includes dir.
	my $subtmpldir  = $self->param('_app_subtmpldir');
	if (!$master_tmpl) { die "SpApp::Core->get_master_tmpl: in this generalized get_master_tmpl we failed to obtain from $self->param('_app_master_tmpl') a template filename. Maybe you want to define a custom get_master_tmpl in your module and not worry about this stuff?";	}
	#if (!$subtmpldir)  { die "SpApp::Core->get_master_tmpl: in this generalized get_master_tmpl we failed to obtain from $self->param('_app_subtmpldir') a subtmpl directory name. Maybe you want to define a custom get_master_tmpl in your module and not worry about this stuff?";	}
	
	#render_interface_tmpl might pass along an arg to prepend_subtmpldir, but really for this get_master_tmpl, I think we would always want to include the _app_subtmpldir_suffix if it was defined.
	my $master_tmpl_filename;
	my $app_subtmpldir_suffix = $self->param('_app_subtmpldir_suffix');
	my $use_suffixed_tmpl_name = 0;
	if ($app_subtmpldir_suffix && !$subtmpldir) {
		die "SpApp::Core->get_master_tmpl: in this generalized get_master_tmpl we failed to obtain from $self->param('_app_subtmpldir') a subtmpl directory name. Maybe you want to define a custom get_master_tmpl in your module and not worry about this stuff?";
	}
	if ($subtmpldir && $app_subtmpldir_suffix) {
		$master_tmpl_filename = $subtmpldir . '_' . $app_subtmpldir_suffix . '/' . $master_tmpl;
		my $full_suffixed_tmpl_path = $self->param('_tmpl_path') . '/' . $master_tmpl_filename;
		if (-e $full_suffixed_tmpl_path) {
			$use_suffixed_tmpl_name = 1; #we know we should be tryign to use an _app_subtmpldir_suffix, and it turns out such a beast exists. use it.
		}
	}
	
	#if we arent doing _app_subtmpldir_suffix, or we are but the expected file didnt exist, just go with the regular master_tmpl.
	if (!$use_suffixed_tmpl_name) {
		if ($subtmpldir) {
			$master_tmpl_filename = $subtmpldir . '/' . $master_tmpl;
		} else {
			$master_tmpl_filename = $master_tmpl;
		}			
	}

	my $t = $self->load_tmpl($master_tmpl_filename);

	#this seems a std thing to put on the tmpl? should this be in render_interface_tmpl instead?
	$t->param(logged_in => $self->get_auth()->is_logged_in());
	
	return $t;
}

sub render_interface_tmpl {
	my $self = shift;
	my $sub_tmpl = shift; #pass scalar or array ref of sub tmpl names ... each will get all tmpl_params and get rendered into the master tmpl.
	my $tmpl_params = shift; #this must be a hashref.
	my $other_args = shift; #mostly adding this just to give control to what get_master_tmpl will do.
	
	#2009 04 03 experiment for json_context, if arg is present assume its a perl data strucutre that needs to be encoded
	if ($other_args->{json_context}) {
		$tmpl_params->{json_context} = JSON::XS::encode_json($other_args->{json_context});
	}

	#we're going to load the master template, and a subtemplate. we're going to make all the tmpl_params avaialble to both templates, then we're going to put the output of the subtemplate into a param in the master template (the param will be named similar to the sub tempalte name)
	#2009 08 14 I'm to request just a piece of the screen in html in a "standalone" way (for use with ajaxy stuff). So I want to still use this function to render a template (mainly thinking of the json_context and utf-8-issue handling) and just treat that named template as the master and not do a sub_tmpl.
	#get the master
	my $use_sub_tmpl = 1;
	if ($sub_tmpl && (ref($sub_tmpl) ne 'ARRAY')) {
		$sub_tmpl = [ $sub_tmpl ]; #well it is now.
	}

	my $master = undef;
	if ($other_args->{standalone}) {
		$use_sub_tmpl = 0;
		$master = $self->load_tmpl($sub_tmpl->[0]);
	} else {
		$master = $self->get_master_tmpl($other_args);
	}

	#probably wont want this debug line all the time ... but sometimes.
	$self->ch_debug(['render_interface_tmpl: doing with these tmpl_params:', $tmpl_params]);

	#plug vars in
	$master->param($tmpl_params);
	
	if ($use_sub_tmpl) {

		foreach my $sub_tmpl_name (@$sub_tmpl) {
			#load the subtmpl
			my $sub_tmpl_filename = $sub_tmpl_name;
			
			#2007 02 09 - needing a way for cmc education to be able to have custom tmpls. adding a few params to allow that to be fairly automatic and somewhat sensible.
				#and want to simply fall back to non-suffix-dir template if the one being looked for is not one in the suffix'd dir.
			if ($other_args->{prepend_subtmpldir}) {
				my $prefix = $self->param('_app_subtmpldir');        #would have been set in setup();
				my $suffix = $self->param('_app_subtmpldir_suffix'); #would have been set in setup();
				my $use_suffixed_tmpl_name = 0;
				if ($suffix) {
					$sub_tmpl_filename = $prefix . '_' . $suffix . '/' . $sub_tmpl_filename;
					my $full_suffixed_tmpl_path = $self->param('_tmpl_path') . '/' . $sub_tmpl_filename;
					if (-e $full_suffixed_tmpl_path) {
						$use_suffixed_tmpl_name = 1; #we know we should be tryign to use an _app_subtmpldir_suffix, and it turns out such a beast exists. use it.
					}
				}
				if (!$use_suffixed_tmpl_name) {
					$sub_tmpl_filename = $prefix . '/' . $sub_tmpl_filename;
				}
			}

			my $sub_t = $self->load_tmpl($sub_tmpl_filename);
			$sub_t->param($tmpl_params);

			#comment this out as it adds overhead:
			#$self->ch_debug(['render_interface_tmpl: told to load this sub tmpl', $sub_tmpl_name, 'and its output is like', $sub_t->output()]);
			$self->ch_debug(['render_interface_tmpl: told to load this sub tmpl', $sub_tmpl_name]);
		
			#if only 1 sub tmpl and no other control option, just call it sub_tmpl, otherwise give it its own special little var name
			my $sub_t_var = undef;
			if (scalar(@$sub_tmpl) == 1) {
				#special allowance, if only one sub tmpl, for convenience make use of the sub_tmpl var. ... make it easy for the master template!
				$self->ch_debug('render_interface_tmpl: doing the single sub_tmpl rendering');
				$sub_t_var = 'sub_tmpl';
			} else {
				#get the var name to use for the subtmpl
				$sub_t_var = $sub_tmpl_name;
				$sub_t_var =~ s|\.|_|g; #foo.html becomes foo_html
				$self->ch_debug("render_interface_tmpl: doing the multi sub_tmpl rendering: currently rendering one for var named: $sub_t_var");
			}
			my $sub_t_output = $sub_t->output(); #outputting separately mainly to report utf8 flag status in debug.
			$self->ch_debug(['render_interface_tmpl: utf8 flag on the html for the sub template?', Encode::is_utf8($sub_t_output) ]);
			$master->param($sub_t_var => $sub_t_output);
			#remove line below when no longer needed (adds overhead duh)
		}
	}

	#there is a weird character problem first noticed on LBG, if the only utf characters in the output are like ® or © then for some reason its not the utf8 versions of those symbols (which I believe are preceded by an extra byte) it is the regular ascii version or something. This problem seems to go away immediately by including even a single "normal" multi-byte symbol like a chinese character or even the trademark symbol ™. I dont really understand this problem though I have come up with a few workarounds
	#workaround #1 seems to simply be including a commented-out utf-8 character in the html template
	#but something that seems to always work independant of silly template hacks is to encode the output into utf8 right here, thus removing perl utf8 flag from the variable and hopefully ending up right now with the correct sequence of bytes even when nothing but a ® is present.

	my $master_output = $master->output(); #outputting separately mainly to report utf8 flag status in debug.
	
	my $encode_utf8 = 1; #turn off to not encode from perls internal format into utf8. see note above abou issue discovered on LBG. I thik we always want to do this, but in case we want to turn it off i'm coding for that possibility right now.
	if ($other_args->{no_encode_utf8} || $self->config('no_encode_utf8')) {
		$encode_utf8 = 0;
	}
	if ($encode_utf8) {
		#not sure which one is best to use .. going with the one that "feels safest" from reading the Encode docs.
		$master_output = Encode::encode('utf8', $master_output); #this should at least do something useful with bad data and will unset the flag. probably safest one.
		#Encode::_utf8_off($master_output); #this will just turn off the flag ... can't fail but data might be junk
	}
	$self->ch_debug(['render_interface_tmpl: output immediately follows, utf8 flag on the html for the master template output?', Encode::is_utf8($master_output) ]);
	
	return $master_output;
}

### AJAX style edit field validation: ###
sub edit_ajax_field_validation {
	
	#does this belong here? should it go into a SpApp::Ajax package?
		#taken a step further, would SpApp::Ajax be its own little mini application with its own instance script whos name I should provide in standard outgoint tmpl params? I think that might be a good approach
	
	#note (haha lol) having debug mode on will totally break this
	
	my $self = shift;
	my $cgi = $self->query();
	
	my $form_name = $cgi->param('form_name');
	my $d_obj = $self->get_new_dataobj($form_name);
	my $ef_spec = $d_obj->editform_spec();
	$d_obj->_standard_editform_fields($ef_spec->{fields});
	$d_obj->_pickup_cgi_values($ef_spec->{fields}); #should return a 0 if it fails for some reason.
	my $fieldsauto_validation = $d_obj->_validate_field_values($ef_spec->{fields}, { inspect => 'cgi' });
	my $jsfields = [];
	foreach (@{$ef_spec->{fields}}) {
		push(@$jsfields, { parameter_name => $_->{parameter_name}, error => $_->{field_error} });
	}
	my $js = JSON::Syck::Dump($jsfields);
	#print STDERR "ajax_validation_test: sending $js\n";
	return $js
}


### Generic Searchform Controller: ###
sub generic_searchform_controller {
	my $self = shift;
	my $args = shift; #going to use a single args hashref now. just easier for me to deal with and expand things with.
	
	my $form_name = $args->{form_name};
	my $data_obj    = $args->{data_obj};

	if ($form_name && $data_obj) {	die "generic_searchform_controller: Sanity check: you passed a data obj AND a form_name? what should I be using??"; }

	my $save_params_for_screen = $args->{for_screen};
	my $search_params = $args->{search_params};
	my $forced_search_params = $args->{forced_search_params}; 

#	if (!$form_name) { die "generic_searchform_controller: Can't do anything without a form_name argument."; }
	if (!$save_params_for_screen) { die "generic_searchform_controller: for_screen argument is required."; }

	if ($form_name && !$data_obj) {
		$data_obj = $self->get_new_dataobj($form_name);
	}
	if (!$data_obj && $args->{data_obj_classname}) {
		$data_obj = ($args->{data_obj_classname})->new($self);
	}
	if (!$data_obj) {
		die "Failed to obtain a data object";
	}

	my $cgi = $self->query();
	#my $data_obj = $self->get_new_dataobj($form_name);
	my $form_spec = $data_obj->searchform_spec();
	my $session  = $self->session();

	$session->param('last_search_screen' => $save_params_for_screen); #$self->param('runmode');
	$session->param('last_search_mode'   => $self->get_current_runmode());

	#get the searchform result params from the session if it wasnt passed in (and just about the only time it will actually be passed in is when there is initial state info for the searchform hardcoded in the calling func).
	my $using_saved_search_params = 0;
	if (!$search_params) {
		my $session_screen_search_params = $session->param('screen_search_params')->{$self->param('_app_id')}; 
		if ($session_screen_search_params && $session_screen_search_params->{$save_params_for_screen}) {
			#so they're in the session, use them.
			$search_params = $session_screen_search_params->{$save_params_for_screen};
			$using_saved_search_params = 1;
			$self->ch_debug(["generic_searchform_controller: just loaded these search params from the session under screen name: '$save_params_for_screen'", $search_params]);
		}
	}
	
	#try to figure out the search_runmode. if we havent been told explicitly, assume it is the save_params_for_screen value. cause an error if we dont have it.
	my $search_rm = $args->{search_rm};
	if (!$search_rm) { $search_rm = $save_params_for_screen; } 
	if (!$search_rm) { die "generic_searchform_controller: must have a search_rm to give to tmpl_params -- or the form wont work at all. Maybe thats not fatal -- but it needs to be handled someway that isnt going to leave me scratching my head."; } #still not having it is an error.

	my $perform_search = 0; #if this turns true, we'll run the search with the searchform_result_params.
	my $new_search     = 0;
	my $save_result_params = 0; #if this turns true we'll need to store the result params in the session when we're done modifying them

	#2007 06 07 - (happy birthday to me woo 28 yrs young). I want to be able to just reset the search terms without neccessarily actually doing a search. look for cgi param 'reset'
		#2009 09 01 - wow more than 2 years later. anyway lets take an arg for this too.
	if ($cgi->param('reset') || $args->{'reset'}) {
		$search_params = {};
		#2009 05 11 - save those cleared search params imo.
		$save_result_params = 1;
	}

#not sure if this stuff will remain applicable in any way.
	#ch 2003 11 18 update: there will be instances where we want to initialize the multiselect items of a valuesearch form (or a regular search form, but this is being written and tested for valuesearch forms right now). In such cases we need to preserve the multiselect list 
#	my $cleared_result_params = {};
#	if ($searchform_result_params->{preserve_multiselect} && defined($searchform_result_params->{multiselect_list})) {
#		$cleared_result_params->{preserve_multiselect} = 1;
#		$cleared_result_params->{multiselect_list} = $searchform_result_params->{multiselect_list};
#	}
	
	##NEW SEARCH:
	if ($cgi->param('new_search') || $args->{new_search} ) {
		$new_search = 1;
		$self->ch_debug(["generic_searchform_controller: new_search ordered."]);
		
		$search_params = {}; #blow away the params for now.
		
		#pick up search params from the cgi.

		#keywords and their limit_to field
		$search_params->{keywords} = Encode::decode('utf8', $cgi->param('keywords'));
		$search_params->{limit_keywords_to_field} = $cgi->param('limit_keywords_to_field');

		#firstletter matching
		$search_params->{firstletter_search} = Encode::decode('utf8', $cgi->param('firstletter_search'));
		$search_params->{limit_firstletter_to_field} = $cgi->param('limit_firstletter_to_field');

		#get daterange (should be a text string like '20030519-20030624', basically yyyymmdd-yyyymmdd format.
			#but not anymore instead we'll just have daterange_start and daterange_end, already mysql formatted. as opposed to being petarded like before.
		$search_params->{daterange_start} = $cgi->param('daterange_start');
		$search_params->{daterange_end}   = $cgi->param('daterange_end');
		$search_params->{limit_daterange_to_field} = $cgi->param('limit_daterange_to_field');

		my $dropdown_searches = {}; #will be hash of paramname=>submitted_value.
		#get search_dropdown limiters/filter options
			#_search_field_query_options should have been called on the data object via the searchform_spec call above. so lets pull dropdown_searches out of the form directly.
		#foreach(@{$form_spec->{fields}}) {
		#$self->ch_debug(["generic_searchform_controller: new_search ordered, formspec right before dropdown_searhces pickup looks like:", $form_spec]);
		foreach(@{$form_spec->{form}->{dropdown_searches}}) {
			#next if (!$_->{search_dropdown}); #not flagged? then skip to the next. ## update: not neccessary with loop change.
			my $param_name = 'sd_' . $_->{parameter_name};
			#next if (!defined($cgi->param($param_name))); #flagged but no param submitted? skip to the next.
				#commented out the above since we kinda need to pick up and assign undef if user no longer wants to restrict with the dropdown search.
			#$dropdown_searches->{$_->{parameter_name}} = $cgi->param($param_name);
			
			#if we got a value other than emptystring for it, plug it in. (emptystring should be the 'no restriction' option).
			if ($cgi->param($param_name) ne '') {
				$dropdown_searches->{$_->{parameter_name}} = $cgi->param($param_name);
			}

		}
		$search_params->{dropdown_searches} = $dropdown_searches;

		#always show page 1 by default
		$search_params->{current_page} = 1;

		#STORE ALL SEARCH RESULTS PARAMS picked up from the cgi into the session. Everything needed to re-create the search results (all the parameters for the search) into the session.
		$save_result_params = 1;
		$perform_search = 1;
		$self->ch_debug(["generic_searchform_controller: new_search ordered, search params after cgi pickup:", $search_params]);
	}
	
	###UPDATE THE SORTING OVERRIDE
	if ($cgi->param('sort')) { #yeah wwell the rest of the program calls it parameter_name whatever. just one tmpl exception here. other is too long to show up in a url.
		$search_params->{user_sort} = { parameter_name => $cgi->param('sort') };
		if ($cgi->param('sort_dir')) { $search_params->{user_sort}->{dir} = $cgi->param('sort_dir'); }
		$self->ch_debug(['search params after picking up sorting from the cgi:', $search_params]);
		$save_result_params = 1;
		$perform_search = 1;
	}

	###UPDATE THE DISPLAY PAGE NUMBER
	if ($cgi->param('show_page')) {
		$search_params->{current_page} = $cgi->param('show_page');

		$save_result_params = 1;
		$perform_search = 1;
	}

	#changed the name of the record_id param in the data_obj process_form_submission ok action redirect to just 'record_id' as calling it 'preselect_record_id' was too specific to this thing here ... so this thing can deal with a general purpose name.
		#and actually, this thing should just be broken now I think until a better solution is found.
	if ($cgi->param('preselect_record_id')) {
		$search_params->{preselect_record_id} = $cgi->param('preselect_record_id');
	}
	#take a copy to save in session if we're gonng do that later.
	my $search_params_for_save = Clone::clone($search_params); #theres some internal data structs (for sort I think, maybe for other stuff) that i dont want shared references to. so we clone it.
	$self->ch_debug(['generic_searchform_controller: just cloned search params for save, heres the clone:', $search_params_for_save ]);

	#force some params
	if ($forced_search_params) {
		foreach (keys(%$forced_search_params)) {
			$search_params->{$_} = $forced_search_params->{$_};
		}
	}

	##FORM SUBMITTED BEFORE, MEANING WE SHOULD REDISPLAY THE RESULTS.
	if ($search_params->{search_performed} || $search_params->{search_initially}) {
		$perform_search = 1; #tried tested and true
		#is this needed?
		if (!$search_params->{current_page}) {
			$search_params->{current_page} = 1
		}
	}

#	###New Nov 2004: accept a default limit_to_field in the result_params_finished (rcm wants customers being valuesearched from the order form to be search-limited to postal code field by default)
#	if ($search_params->{use_default_limit_keyword_to_field} && $search_params->{limit_keyword_to_field}) {
#		#if both of these provided, use it. set the default field.
#		foreach(@{$form_spec->{fields}}) { #prepare last selected dropdown 
#			if ($search_params->{limit_keyword_to_field} eq $_->{parameter_name}) {
#				$_->{keyword_limit_to_selected} = 1;
#			}
#		}
#	}

	###DO THE ACTUAL QUERY, THE REAL MEATY PART.
	my $result_tmpl_params;
	if ($perform_search) {

		#get default page size from config if we're not doing no_pagintation and a page_size was not coded in the search_params.
		if (!$args->{no_pagination} && !$search_params->{page_size}) {
			$search_params->{page_size} = $self->config('search_results_pagerecords');
		}
		if ($args->{record_id_param}) {
			$search_params->{record_id_param} = $args->{record_id_param};
		}

		#always show chopped short text ?
			#no, because there are times when we DONT want to do it. so we'll just do it if its in the forced_search_params or if we got it as an arg.
		if ($args->{short_text}) {
			$search_params->{short_text} = 1;
		}
		$search_params->{plaintext_html} = 1; #Jay dont want to see the html tags, and we cant have the html itself rendered, so playing with plaintext version like the email plaintext via HTML::FormatText::WithLinks or some similar module.

		#get the search results
		$self->ch_debug(['generic_searchform_controller: about to do get_search_results() with these search_params:', $search_params ]);
		$result_tmpl_params = $data_obj->get_search_results($search_params);

		if (!$args->{no_pagination}) {
			#add pagination data to the hash
			$data_obj->paginate_search_results($result_tmpl_params);
		}
		#$self->ch_debug(['generic_searchform_controller: just got and paginated results, looking like:', $result_records]);

		#2007 07 04 experiment: take the num_records from the search results and save as a search param, so that subsequent runs of query will be told how many records there are. if we do a new_search then we should reset this - which we will since it will start with fresh search params if we do a new search.
			#2007 08 23 - so yeah this turned out to be pretty useful so far anyway, however for screens where the number of records needs to reflect changes that were just made, I want to be able to disable this.
		if (!$args->{dont_save_num_records}) {
			$search_params_for_save->{num_records} = $result_tmpl_params->{num_records};
		}

		#put search terms back into the output so they can be redisplayed, reselected.
		foreach (keys(%$search_params)) {
			$result_tmpl_params->{$_} = $search_params->{$_};
		}
		
		$search_params_for_save->{search_performed} = 1;
		#UPDATE STORED SEARCH RESULTS PARAMS of the session
		$save_result_params = 1;
	}# else {
	#	$result_tmpl_params = $form_spec->{form}; #that _should_ give whats needed to show the keyword limiter, etc.
	#	#the better way to do this would probably be to have the dataobj get_search_results just worry about results, forget about form attributes and we should add form attributes in.
	#}

	#add all attributes of the form ot the outgoing result tmpl params (yes this will overwrite anything inthe results with the same key but that is what was happening before in the data object before we moved this here)
	foreach (keys(%{$form_spec->{form}})) {
		#copy all form attribs into the result before sending back. this is mainly for the searchability stuff.
		$result_tmpl_params->{$_} = $form_spec->{form}->{$_};
	}
	
	#ensure needed javascripts are loaded by the tmpl:
	if ($form_spec->{form}->{daterange_searchable}) {
		$result_tmpl_params->{calendar_support_required} = 1;
	}

	#set valuesearching flag if passed. should force a hidden form param to be set.
	if ($args->{valuesearching}) {
		$result_tmpl_params->{valuesearching} = 1;
	}

	#set multiselect flags. also thinking that if any of the values shown in the current page are selected in the multiselect memory, then we should make sure they are checked. not just yet tho.
	if ($args->{multi_value_search}) {
		$result_tmpl_params->{multi_value_search} = 1;
		#meh, this is dumb. going forward, jquery is generally going to be required, because I'm not likely going to be writing js that doesnt use it very much.
		#$result_tmpl_params->{jquery_support_required} = 1; #planning to use some better js to do stuff.

		#also, it being a multi value search, we could have some multi-values json to pick up and carry forward.
		if ($cgi->param('selected_values')) {
			$result_tmpl_params->{selected_values_json} = $new_search ? undef : $cgi->param('selected_values');
		}

	}
	
	#add anything else that should go along with template params, buttons, form label, search rm, etc.
	$result_tmpl_params->{search_rm}    = $search_rm;
	$result_tmpl_params->{form_label}   = $args->{form_label};
	$result_tmpl_params->{form_buttons} = $self->form_button_vars($args->{buttons});
	$result_tmpl_params->{form_prompt}      = $args->{form_prompt};       #2007 08 16 I'm thinking two styles of prompts, plainjane and automatically wrapped in a <p> tag ...
	$result_tmpl_params->{form_prompt_html} = $args->{form_prompt_html};  # ... or full html slice with whatever.

	#2009 01 27 add in any tmpl_params that we were given directly. for now, they will override. but that might change.
		#2009 03 23 yeah ok reversed that to preserve essential form stuff since this shit is sloppy and dropdown_searches needs to come from form property of that name NOT search_params property of that name.
	if ($args->{tmpl_params}) {
		#$result_tmpl_params = { %$result_tmpl_params, %{$args->{tmpl_params}} };
		$result_tmpl_params = { %{$args->{tmpl_params}}, %$result_tmpl_params };
	}

	#save the result params if required to.
	if ($save_result_params) {
		
		#2009 04 03 commented out the lines below since I've just updated this module to use the setup_session_vars code to make sure this thing has a hashref in it.
			#as part of the app_id'ification of this variable too.
#		if (!defined($session->param('screen_search_params'))) { 
#			$session->param('screen_search_params' => {}); 
#		}
		$session->param('screen_search_params')->{$self->param('_app_id')}->{$save_params_for_screen} = $search_params_for_save;
		$self->ch_debug(["generic_searchform_controller: just saved these search params in the session under screen name: '$save_params_for_screen'", $search_params_for_save]);
	}
	
	#2009 08 16 ajax_mode stuff. the main thing to carry forward to templating is info about what div id to replace contents of.
	if ($args->{ajax_mode}) {
		#the results box div id should be a DIV that will contain at the very least the pagination controls AND the results rows.
		#ajax_mode => 1 
		# or 
		#ajax_mode => { results_div_id => 'custom_shit' }
		my $results_div_id    = 'results_div';
		my $addtl_params_func = undef;
		if (ref($args->{ajax_mode}) eq 'HASH') {
			my $ajax_params = $args->{ajax_mode};
			if ($ajax_params->{results_div_id})    { $results_div_id    = $ajax_params->{results_div_id}; }
			if ($ajax_params->{addtl_params_func}) { $addtl_params_func = $ajax_params->{addtl_params_func}; } #if this is given it should be the name of a js function that will return a js object.
		}
		$result_tmpl_params->{ajax_mode} = 1;
		$result_tmpl_params->{ajax_mode_results_div_id}    = $results_div_id;
		$result_tmpl_params->{ajax_mode_addtl_params_func} = $addtl_params_func;
	}

	#set up rendering if we are doing that too.
	my ($render, $output_tmpl) = (0, 'general/generic_searchform.tmpl'); #default of NOT rendering, and a nice generic editform tmpl to not render. This way we can just turn on rendering and not have to specify a template :)
	if ($args->{render}) {
		$render = 1;
	}
	if ($render && $args->{tmpl_name}) {
		$output_tmpl = $args->{tmpl_name}; #of course we can set a different output tmpl if we _want_ to though.
	}

	$self->ch_debug(["generic_searchform_controller: full set of tmpl_vars: ", $result_tmpl_params, 'and search params', $search_params ]);
	#$data_obj->_dereference();

	#render output or return params, depending.
	if (!$render) {
		#no render, send back tmpl_params.
		return $result_tmpl_params;
	} else {
		#otherwise, load it up and render it.
		return $self->render_interface_tmpl([$output_tmpl], $result_tmpl_params, $args->{render_args});	
	}
}

sub generic_viewform_controller {
	my $self = shift;
	my $args = shift;
	
	#i imagine this will be very similar to the editform controller, just that it will be sure to default to a template where everything is display only.

	my $for_screen = $args->{for_screen};
	if (!$for_screen) { die "Screen name required (for_screen) so that (mainly) any valuesearched items know where to be saved. Regardless of whether valuesearching features will be used. Also editform we will retrieve expects it."; }
			
	my $tmpl_params = $args->{tmpl_params} ? $args->{tmpl_params} : {}; #pre-defined tmpl_params, or empty hashref?
	my $record_id_param = 'record_id';

	if ($args->{record_id_param}) {
		$record_id_param = $args->{record_id_param};
	}
	
	my $cgi = $self->query();
  my $record_id = undef;
	if ($args->{record_id})  { 
		$record_id = $args->{record_id};
	} else {
		$record_id = $cgi->param($record_id_param);
	}
	if (!$record_id) { 
		die "Record ID required.";
	}

	#it seems to make sense that if we are cancelling an editform, we should do it via the processing controller. we whould be told where to go upon cancellation. bail if we get the cancel cgi param but dont know what to do.
	if ($cgi->param('action_cancelled')) {
		my $cancel_to = $args->{cancel_to_screen};
		if (!$cancel_to) { die "generic_viewform_controller: saw the action_cancelled cgi param, but have no indication of where to send you."; }
		return $self->redirect_runmode($cancel_to, { $record_id_param => $record_id });
	}

	#establish data object.
	my $data_obj = $args->{data_obj};
	if (!$data_obj && $args->{data_obj_classname}) {
		$data_obj = ($args->{data_obj_classname})->new($self);
	}
	if (!$data_obj) {
		die "Data object (data_obj) required.";
	}
	
	$data_obj->record_id($record_id);
	my $editform_args = $args->{editform_args} ? $args->{editform_args} : {};
	$editform_args->{plaintext_html} = 1; #for viewforms, we have added ability of fields_direct mode of sql record selection to be able to do a plaintext version.
	$editform_args->{wrap_text} = 1; #for viewforms, also we have text wrapping for TEXTINPUT and DISPLAY fields.
	$editform_args->{ouput_style} = 'view'; #so some field processing code inside _perform_select will know what options to look at (view or edit) to determine if it needs to wrap text, etc.
	my $editform_tmpl_params = $data_obj->get_editform({ for_screen => $for_screen, %$editform_args }); #passed in editform args override automatic ones.

	$tmpl_params = { %$editform_tmpl_params, %$tmpl_params }; #merged such that existing tmpl_params take precedence (which may or may not be a bad thing)
	$tmpl_params->{form_label}   = $args->{form_label};
	$tmpl_params->{form_buttons} = $self->form_button_vars($args->{buttons});

	#related records? #experimental 2007 05 08.
	if ($args->{related_records_display}) {
		#we can show some related records underneath the edit records (or wherever). we can do multiple sets of these. (or I'd like to)
		if (ref($args->{related_records_display}) ne 'ARRAY') { $args->{related_records_display} = [ $args->{related_records_display} ] };
		foreach my $relation_setup (@{$args->{related_records_display}}) {
			$self->_editform_related_records({ 
				relation_setup            => $relation_setup, 
				valuesearched_form_values => $self->session()->param('valuesearched_form_values')->{$for_screen},
				tmpl_params               => $tmpl_params, 
				data_obj                  => $data_obj,
			});
		}
	
		$self->ch_debug(['generic_viewform_controller: related_records_display shaped up like:', $tmpl_params->{related_records_display} ]);
	}

	#set defaults for rendering and template name.
	my ($render, $output_tmpl) = (0, 'general/generic_viewform.tmpl'); #default of NOT rendering, and a nice generic editform tmpl to not render. This way we can just turn on rendering and not have to specify a template :)
	if ($args->{render})            { $render = 1;	}
	if ($render && $args->{tmpl_name}) {
		$output_tmpl = $args->{tmpl_name}; #of course we can set a different output tmpl if we _want_ to though.
	}

	##This is probably going to need work in terms of what to send back. Right now (20070129) I am realizing that I want to be able to get the DataObj back along with the tmpl params .... going to kludge something in for that.
	if (!$render) {
		return {
			data_obj    => $data_obj,
			tmpl_params => $tmpl_params,
		};
	} else {
		#otherwise, load it up and render it.
		$self->ch_debug(['viewform tmpl_params:', $tmpl_params]);
		return $self->render_interface_tmpl([$output_tmpl], $tmpl_params, $args->{render_args});	
	}

}

#copied from formgen ideas:
#was thinking about a valuesearch controller the other day
#define a list of all forms associated with edit screens that can go off to do valuesearching. we need it to be able to know what form to get in here.
#be passed the name of the param and screen that valuesearching is being done for. This gives from the list of forms, the form we need.
#obtain the formspec, get the editmode fields, pickup cgi values, and save in the session.
#also the details in the field info for the field that we are valuesearching for will tell us the search runmode.
#we go to that search runmode in a valuesearch context. That means the search runmode must be valuesearch-aware, and in that context show a "use" button which comes back to the vsc.
#the valuesearch context must be passed forward via a hidden form var. that is the best way IMO. then also you could make a new record from thevaluesearch and the save mode for that would have to be valuesearch aware to pass it back to the search screen. finally the search screen would return with the 'use'd record, back to the vsc.
#the vsc then plugs in the chosen value into the field cgi_value
	#display values should be re-looked up for any fields related to the valuesearched field. (that will be hairy methinks).

#in the meantime I can cheese up an editform controller. I mean, theres really nothing to THAT. 
#default behaviour is to build all the vars for the the specified form name in edit mode, and return the tmpl params.
	#args like:
		#form_name (required)
		#for_screen (required)
		#record_id_param (optional, would be cgi param to look for record id in -- default is app-wide standard 'record_id')
		#buttons (optional, provide tmpl_vars for button rendering, pass in an arrayref of hashrefs, enties must each contain a key like 'type', example type is type => 'simple_save', please see the code and rendering tmpl for what other button entry keys can/should be provided.)
		#form_label (optional form label to include in tmpl_vars, and possibly show on the screen depending on the output tmpl)
		#render (optional, default 0, if 1 is specified, the tmpl vars will be passed to a template and the rendered tmpl output will be returned)
		#tmpl (optional, name a specific template to use for rendering, ignored if 'render' is not turned on in the args).
		#record_id (optional, normally picked up from cgi, providing in args would force handling of a specific record)
		#retry_form (optional, normally picked up from cgi, providing in args would force retry of the form -- experimental to force that here)
sub generic_editform_controller {
	my $self = shift;
	my $args = shift;
	my $record_id_param = 'record_id';

	#general setup based on args
	my $form_name   = $args->{form_name};
	my $data_obj    = $args->{data_obj};
	my $data_obj_classname = $args->{data_obj_classname};
	my $tmpl_params = $args->{tmpl_params} ? $args->{tmpl_params} : {}; #pre-defined tmpl_params, or empty hashref?
	my $for_screen  = $args->{for_screen};
	my $for_designed_form = $args->{for_designed_form};

	#ability to tell the controller what cgi param to look for for its record id pickup (in case for some reason its not simply record_id)
		#also note the editform itself can submit using a custom record_id_param but that is separate from THIS record_id_param arg. custom record id param for editform submission is done via editform_args->{record_id_param}.
	if ($args->{record_id_param}) {
		$record_id_param = $args->{record_id_param};
	}
	
	if (!$for_screen)            { die "generic_editform_controller: for_screen argument is required\n"; }
	if ($form_name && $data_obj) {	die "generic_editform_controller: Sanity check: you passed a data obj AND a form_name? what should I be using??"; }
	
	my $cgi = $self->query();

	my $need_dobj = 1;
	if ($for_designed_form)  { $need_dobj = 0; } #for a designed form, we might not have a data object. but if we get one (or a name of one) we'll use it.

	my $record_id = undef;
	my $retry_form = $cgi->param('retry_form');
	if ($args->{retry_form}) { $retry_form = 1; }		
	
	#handle record_id pickup, which we usually will do.
	my $record_id_pickup = 1;
	if ($args->{no_load_from_db}) { #should this be renamed from no_load_from_db to no_record_id_pickup ? that would seem a more apt name.
		$record_id_pickup = 0;
	}
  if ($record_id_pickup) {
  	$record_id = $cgi->param($record_id_param);
  }
	if ($args->{record_id})  { $record_id = $args->{record_id}; }

	#instantiate data obj if we got a classname and no data_obj.
	if (!$data_obj && $args->{data_obj_classname}) {
		$data_obj = ($args->{data_obj_classname})->new($self);
	}
		
	if ($form_name && !$data_obj) {
		#setup for record id and retry
		$data_obj = $self->get_new_dataobj($form_name, $record_id);
	} elsif ($data_obj) {
		#or set a record id on the passed in dobj.
		$data_obj->record_id($record_id);
	}
	
	if ($need_dobj && !$data_obj) {
		die "remove this and you can see what happens when we need a dobj and didnt get one passed in or didnt get a useable form_name/data_obj_classname to create one with";
		if(!$form_name) { die "generic_editform_controller: we need a data obj. So form_name argument is required if a data_obj is not passed.\n"; } 
	}
	
	$self->ch_debug(['generic_editform_controller: we have a data object to work with:', ($data_obj ? 1 : 0)]);

	if ($data_obj) {
		my $editform_args = $args->{editform_args} ? $args->{editform_args} : {};
		$editform_args->{include_captchas} = 1; #new for 2008 11 27
		my $editform_tmpl_params = $data_obj->get_editform({ retry_form => $retry_form, for_screen => $for_screen, %$editform_args }); #passed in editform args override automatic ones.
		#what about overriding default values in form fields for a new record (no record id) that is not retrying form? (which _should_ mean showing for first time. might eventually want another param that would control this better.)
		if (!$record_id && !$retry_form && $args->{default_values}) {
			$data_obj->set_edit_values($args->{default_values});
		}
#		#2008 04 17 I have a form that shows a cbox that the value for it is determined by 2 flags in the actual record itself and i can't just load_record_for_edit since there is nothing to populate the cbox - i need to be able to figure out the value of the cbox outside of here and pass it in. or a field level hook for obtaining its value from somewhere other than the db! lol.
#			#so its very similar to the thing for default_values above except we should only do it if there is a record id (b/c otherwise it should be the default values)
#		if ($record_id && !$retry_form && $args->{override_values}) {
#			$data_obj->set_edit_values($args->{override_values});
#		}
#wait no, I want to do something more interesting. like a hook in get_editform to augment loaded db values thru code that lives in the data object.
		
		#$self->ch_debug(['generic_editform_controller: the editform_tmpl_params to be added to all the others:', $editform_tmpl_params, 'the tmpl_params we already have:', $tmpl_params]);
		#die "for stopping the bad";
		$tmpl_params = { %$editform_tmpl_params, %$tmpl_params }; #merged such that existing tmpl_params take precedence (which may or may not be a bad thing)
	}

	$tmpl_params->{form_label}   = $args->{form_label};
	#I'd like to be able to generically handle buttons and shit here too. I think I'd like the searchform controller to maybe be able to do that as well. Lets maybe try something here tho for starters.
		#this is all just an experiment anyways ... I must strive not to hang myself with it!
	$tmpl_params->{form_buttons} = $self->form_button_vars($args->{buttons});
	
	#think about including detail record stuff too ... but that might be better suited through callback hooks for now.
		
	#I want to be able to show messages on editforms. This will probably be the first experimental usage of a modernized app_interface_string
	my ($errmsg, $confmsg) = (undef, undef);
	#errormsg name pickup
	if ($args->{editform_errmsg}) {
		$errmsg = $args->{editform_errmsg};
	} elsif ($cgi->param('editform_errmsg')) {
		$errmsg = $cgi->param('editform_errmsg');
	}
	#confmsg name pickup
	my $confmsg_as_html = 0;
	if ($args->{editform_confmsg}) {
		$confmsg = $args->{editform_confmsg};
	} elsif ($args->{editform_html_confmsg}) {
		$confmsg = $args->{editform_html_confmsg};
		$confmsg_as_html = 1;
	} elsif ($cgi->param('editform_confmsg')) {
		$confmsg = $cgi->param('editform_confmsg');
	}
	my @stringnames = ();
	if ($confmsg) { push(@stringnames, 'confmsg__' . $confmsg); }
	if ($errmsg)  { push(@stringnames, 'errmsg__' . $errmsg); }
	#error and conf msg obtaining and templating
		#for the substitutions, I am not implementing it yet, but would like to be able to save some hashref of substitition values at a certain screen-and-msg-name related kay in the session, then we can easily pull that back in here even though we redirected here, etc.
	my $strings = $self->get_strings(\@stringnames);
	$self->ch_debug(['generic editform controller: err and conf string names picked up from args or cgi:', [$errmsg, $confmsg], 'the strings hashref obtained for those is like:', $strings]);
	if ($strings->{'errmsg__' . $errmsg}) {
		$tmpl_params->{errmsg} = 1;
		$tmpl_params->{errmsg_name} = $errmsg;
		$tmpl_params->{errmsg_text} = $strings->{'errmsg__' . $errmsg};
	}
	if ($strings->{'confmsg__' . $confmsg}) {
		$tmpl_params->{confmsg} = 1;
		$tmpl_params->{confmsg_name} = $confmsg;
		$tmpl_params->{'confmsg_' . ($confmsg_as_html ? 'html' : 'text')} = $strings->{'confmsg__' . $confmsg};
	}

	#bulk addition of tmpl params via callback.
	if ($args->{tmpl_params_callback}) {	
		my $callback_func = $args->{tmpl_params_callback};	
		my $callback_args = {
			data_obj    => $data_obj,
			tmpl_params => $tmpl_params,
		};
		if ($args->{tmpl_params_callback_args} && (ref($args->{tmpl_params_callback_args}) eq 'HASH')) {
			$callback_args->{passed_args} = $args->{tmpl_params_callback_args};
		}
		#so our callback args will default to having just the two standard items (existing tmpl_params, and the data_obj if any). But then we can add passed_args in too for more control.
			#lets accept output, but for now discard it. not sure what kind of output would be useful since the point of the callback is to modify the tmpl_params.
		my $callback_output = eval '$self->$callback_func($callback_args)'; #see callback code in dobj for more info.
		die "Error executing SpApp->generic_editform_controller for the tmpl_params_callback: $@" if $@;
	}

	#clearing of valuesearched values when not in retry_form mode? (experiment for the experimental valuesearch controller stuff.
		#wait a minute ... we dont need to be so specific about what to remove ... any and all valuesearch targets for the screen.
#	if ($args->{valuesearch_targets} && !$retry_form) {
#		#so we are just showing the form for the first time -- therefor we cannot be displaying valuesearched sub/related items, only actually saved and truly attached sub/related items.
#		foreach my $values_target (@{$args->{valuesearch_targets}}) {
#			if (!$self->session()->param('valuesearched_form_values')) { $self->session()->param('valuesearched_form_values') = {} }; #ensure it exists.
#			$self->session()->param('valuesearched_form_values')->{$for_screen}->{$values_target} = undef; #clear out the values target.
#		}
#	}
	if (!$self->session()->param('valuesearched_form_values')) { $self->session()->param('valuesearched_form_values' => {}) }; #ensure it exists.
	if (!$retry_form) {
		#so we are just showing the form for the first time -- therefor we cannot be displaying valuesearched sub/related items, only actually saved and truly attached sub/related items.
		delete($self->session()->param('valuesearched_form_values')->{$for_screen}); #clear out any valuesearched values 
	}

	#related records? #experimental 2007 05 08.
#	if ($args->{related_records_display}) {
# 2008 04 01, only do related records display stuff for an editform if its a saved record with a record id.
	if ($args->{related_records_display} && $record_id) {
		#we can show some related records underneath the edit records (or wherever). we can do multiple sets of these. (or I'd like to)
		if (ref($args->{related_records_display}) ne 'ARRAY') { $args->{related_records_display} = [ $args->{related_records_display} ] };
		foreach my $relation_setup (@{$args->{related_records_display}}) {
			$self->_editform_related_records({ 
				relation_setup            => $relation_setup, 
				valuesearched_form_values => $self->session()->param('valuesearched_form_values')->{$for_screen},
				tmpl_params               => $tmpl_params, 
				data_obj                  => $data_obj,
			});
		}
	
		$self->ch_debug(['generic_editform_controller: related_records_display shaped up like:', $tmpl_params->{related_records_display} ]);

	}

	#set defaults for rendering and template name.
	my ($render, $output_tmpl) = (0, 'general/generic_editform.tmpl'); #default of NOT rendering, and a nice generic editform tmpl to not render. This way we can just turn on rendering and not have to specify a template :)
	if ($args->{render})            { $render = 1;	}
	if ($args->{for_designed_form}) { $render = 0;	}
	if ($render && $args->{tmpl_name}) {
		$output_tmpl = $args->{tmpl_name}; #of course we can set a different output tmpl if we _want_ to though.
	}

	##This is probably going to need work in terms of what to send back. Right now (20070129) I am realizing that I want to be able to get the DataObj back along with the tmpl params .... going to kludge something in for that.
	if (!$render) {
		if ($args->{for_designed_form}) {
			return {
				data_obj    => $data_obj,
				tmpl_params => $tmpl_params,
			};
		} else {
			return $tmpl_params;
		}
	} else {
		#otherwise, load it up and render it.
		$self->ch_debug(['tmpl_params:', $tmpl_params]);
		return $self->render_interface_tmpl([$output_tmpl], $tmpl_params, $args->{render_args});	
	}
}

###Basically what we do here is as follows (writing this down as pseudocode for eventual abstracted controller for this stuff)
	#establish primary editform controller params (generic_editform_controller should be made to also work with perl-defined data objects and not just named DB forms)
	#get back from generic_editform_controller the form_params (of which we are concerned with the tmpl_params and the data_obj we get from it)
	#do a bunch of shit to tmpl_params (which will probably be done via specifying a callback, the callback would probably just need to get whatever the generic_editform_controller sends back, as callback params)
		#should this piece just be moved to the generic_editform_controller anyway?
	#render the "custom" template with the tmpl_params. (will _not_ include refilling the form fields, but would do anything else like showing pieces of information that have been obtained from other screens or something)
	#get the error-flagged html (processed with my custom routine for doing that) based on the already-validated data_obj we got from the generic_editform_controller and the custom form html that was just rendered. it will find any id of lbl_* on any html start tag, where * is the parameter name of the field, and apply the "error" class to any fields that had errors.
	#finally the form is filled for form-field values via H:FiF and the field repopulation vlaues obtained from the data_obj->
		#i think this is where some work will need to be done for a callback which can do stuff to the repop-values that get sent to fill_form.
		# - can just have another callback for this, in this case here i would have to pass it the $offerings_param somehow since it decodes the JSON for that, ... THAT or the DataObj::get_edit_values c/should take MULTISELECT things into accound and decode automatically. not sure if that would be dangerous.
sub generic_designed_editform_controller {
	my $self = shift;
	my $editform_controller_params = shift;

	$editform_controller_params->{for_designed_form} = 1; #forced so that we get a dobj and tmpl_params back.
					
	#get the signup form template object. Will include the form-specced stuff, which is primarily just the main text and dropdown fields of the form.
	my $form_params = $self->generic_editform_controller($editform_controller_params);
	my ($tmpl_params, $data_obj) = ( $form_params->{tmpl_params}, $form_params->{data_obj} );

	#some standard field processing to set up vars that won't otherwise be accessible to the designed form:
		#be sure to do listoptions only if they havent already been done, since the tmpl_params callback could have placed them there already (and doing it again now could replace with nohting, if they were totally custom and not part of the field spec!)
		#may need same check-for-already-done for RCF thing but not worrying about it right now.
		#Yeah seriously this whole rcf thing needs to be redone from scratch with more thought. I think after we fire CMC or CMC fires us we should completely remove anything to do with this rcf crap from everything, since its becoming a mess, especially the multi-lang aspect of it.
	foreach (@{$tmpl_params->{fields}}) {
		if (ref($_->{edit_listoptions}) && !$tmpl_params->{$_->{parameter_name} . '_options'}) {
			#$self->ch_debug(['generic_designed_editform_controller:, setting up listoption vars in easy to reach places - going to add this param:', $_->{parameter_name} . '_options', 'which we will place this value at:', $_->{edit_listoptions}, 'which will overwrite this existing value (which it should not though!', $tmpl_params->{$_->{parameter_name} . '_options'}]);
			$tmpl_params->{$_->{parameter_name} . '_options'} = $_->{edit_listoptions};
		}
		if ($_->{edit_fieldtype} =~ /^COMBO_RADIO_CONTROLLED_FIELD/) {
			$self->ch_debug(['generic_designed_editform_controller: with a COMBO_RADIO_CONTROLLED_FIELD, is the control json flagged as utf8?', Encode::is_utf8($_->{rcf_control_json}) ]);
			#die "stop to see something";
			$tmpl_params->{$_->{parameter_name} . '_rcf_control_json'} = $_->{rcf_control_json};
			$tmpl_params->{$_->{parameter_name} . '_rcf_control'}      = $_->{rcf_control}->{control};
			$tmpl_params->{$_->{parameter_name} . '_rcf_' . $_->{rcf_control}->{control_type} . 'controlled'} = 1; #ugh maybe NOT radio controlled. maybe select controlled. (select-controlled-field?? well really now i need a new name like field-controlled-field or something because its not always a radio that controls it now! yargh. (it will end up being remote-controlled-field)
			#woops need this for multilang
			$tmpl_params->{$_->{parameter_name} . '_rcf_blankitem_label'} = $_->{rcf_control}->{blankitem_label};
			$self->ch_debug(['generic_designed_editform_controller: rcf blankitem param', $_->{parameter_name} . '_rcf_blankitem_label', $tmpl_params->{$_->{parameter_name} . '_rcf_blankitem_label'}]);
		}			
		if ($_->{edit_fieldtype} =~ /^CAPTCHA/) {
			#2008 12 30 note this is coded like the other stuff that was already here with parameter name prefix ... so happens that multiple captchas would probably break ... and that we use "captcha" as the param name so the var in the html will be like "captcha_captcha_html" ... but whatever.
			$tmpl_params->{$_->{parameter_name} . '_captcha_html'} = $_->{captcha_html};
		}
	} 	

	#do tmpl_params callback
		#I may want to move this into the generic_editform_controller ... but probably should wait until the first time I want to modify the tmpl params in there before doing it.
		#err 2007 03 29 I _did_ move it.

	#$self->ch_debug(['generic_designed_editform_controller: tmpl_params at point alpha:', $tmpl_params]);
	#die "stop to inspect tmpl_params at this point.";
	
	my $tmpl_name = $editform_controller_params->{tmpl_name};
	if (!$tmpl_name) { die "error: generic_designed_editform_controller requires a tmpl_name but none was provided."; }
	my $html = $self->render_interface_tmpl([ $tmpl_name ], $tmpl_params, $editform_controller_params->{render_args});	
	
#	###debug ... uncomment proper my $html = .... above and remove this ...
#	$tmpl_params = {
#		foo_screwed => "\x{263A}", #is a utf8 happy face
#		bloot => "é˜¿æ¾å“¦æˆ‘ä¹Ÿ",
#	};
#	foreach (keys(%$tmpl_params)) {
#		#??? since tmpl params can be quite the nested data structure ..... want to walk the whole fuckin thing????? omg. no.
#	}
# 	use Module::Info;
# 	my $htc_ver = Module::Info->new_from_module("HTML::Template::Compiled")->version;
# 	my $ue_ver  = Module::Info->new_from_module("URI::Escape")->version;
#	$self->ch_debug(['generic_designed_editform_controller: debugging weird templating issue, some HTC and UE', $htc_ver, $ue_ver]);
#
#	my $html = $self->render_interface_tmpl([ $tmpl_name ], $tmpl_params, $editform_controller_params->{render_args});	
	$self->ch_debug(['generic_designed_editform_controller: utf8 flag on the html we are about to send?', Encode::is_utf8($html) ]);
#	return $html;
#	###end debug.
	
	#I imagine I might want a hook for the repop values stuff as well, but for now this seems totally logical the way it is.
	my $repop_values = {};
	if ($data_obj) {
		$repop_values = $data_obj->get_edit_values();
		#flag errors in the form html.
		$html = $self->_tweak_form_html({ data_obj => $data_obj, html_ref => \$html, error_css_class => $editform_controller_params->{error_css_class} });
	}

	#give the tmpl the tmpl_params and render it so that we can use HTML::FillInForm on it afterwards to repopulate.
	$self->ch_debug(['generic_designed_editform_controller: tmpl_params:', $tmpl_params, 'edit_values from the data object:', $repop_values]);
	
	#repopulate the form fields.
	keys %$repop_values; ##Note, the only reason for this (1.5hrs wasted) is to deal with an unknown issue where a Dumper of the hashref with sortkeys on somehow fucks it up for HTML::FillInForm. Hobbs on #perl gave this as a suggestion. It seems to work. So it must be something about the internal keys iterator that gets screwed up for HTML::FillInForm. I suspect its a bug in H:FIF since the code in Data::Dumper seems pretty simple and its only H::FIF that is fucking up. Will see about filing a bug report. (I _AM_ running latest versions of both modules)
	my $filled_html = $self->fill_form(\$html, $repop_values); ###NOTE, method "fill_form" of course provided by using CGI::Application::Plugin::FillInForm

	return $filled_html;
}

sub generic_processform_controller {
	my $self = shift;
	my $args = shift;

	#pick up the record id based on the record_id param, use the data obj to process the form, passing along actions and args.
		#also need to have setup the ability to save related records that were valuesearched based on some kind of descriptor to do that.

	my $cgi = $self->query();
	my $record_id = undef;
	my $record_id_param = 'record_id';
	my $record_id_pickup = 1;
	if ($args->{record_id_param}) {
		$record_id_param = $args->{record_id_param};
	}
	if ($args->{no_record_id_pickup}) {
		$record_id_pickup = 0;
	}
  if ($record_id_pickup) {
  	$record_id = $cgi->param($record_id_param);
  }
	if ($args->{record_id})  { $record_id = $args->{record_id}; }

	#it seems to make sense that if we are cancelling an editform, we should do it via the processing controller. we whould be told where to go upon cancellation. bail if we get the cancel cgi param but dont know what to do.
	if ($cgi->param('action_cancelled')) {
		my $cancel_to = $args->{cancel_to_screen};
		if (!$cancel_to) { die "generic_processform_controller: saw the action_cancelled cgi param, but have no indication of where to send you."; }
		my $cancel_to_rm = $cancel_to;
		if (ref($cancel_to) eq 'HASH') {
			if ($record_id) {
				$cancel_to_rm = $cancel_to->{with_record_id};
			} else {
				$cancel_to_rm = $cancel_to->{without_record_id};
			}
			if (!$cancel_to_rm) { die "generic_processform_controller: cancelling the processing of a form using a multi-mode cancel_to_screen descriptor, but could not determine what mode to send you to. record id was $record_id. Is the descriptor coded correctly?"; }
		}
		return $self->redirect_runmode($cancel_to_rm, { $record_id_param => $record_id });
	}

	my $data_obj = $args->{data_obj};
	if (!$data_obj && $args->{data_obj_classname}) {
		$data_obj = ($args->{data_obj_classname})->new($self);
	}
	if ($record_id) {
		$data_obj->record_id($record_id);
	}
	my $actions = $args->{actions};
	my $process_args = { report_only => 1};

	#other args we want to explicitly carry forward here?
	if ($args->{for_screen})                  { $process_args->{for_screen}                  = $args->{for_screen};	}
	if ($args->{defer_save})                  { $process_args->{defer_save}                  = $args->{defer_save};	}
	if ($args->{pre_save_inject_fields})      { $process_args->{pre_save_inject_fields}      = $args->{pre_save_inject_fields};	}
	if ($args->{suppress_redirect_record_id}) { $process_args->{suppress_redirect_record_id} = $args->{suppress_redirect_record_id};	}
	if ($args->{record_id_param})             { $process_args->{record_id_param}             = $args->{record_id_param};	} #passing this arg will change the whole process to look for and send out this record_id_param
	if ($args->{redirect_record_id_param})    { $process_args->{record_id_param}             = $args->{redirect_record_id_param};	} #passing this arg will still have us look for 'record_id' here but allow the ok action redirect to have something else in there.
	
	my $process_report = $data_obj->process_form_submission($actions, $process_args); #we want to get back a report in all cases. then we will handle the redirects directly in here (possibly after doing some other stuff)
	if ($args->{report_only}) {
		return $process_report;
	}

	#anything to do with an ok submission thats now been saved to the db? 
	if ($process_report->{ok}) {
		#save unsaved valuesearched items -- this is the whole motivator for me finally getting around to making this generic_processform_controller in the first place.
			#we pretty much need to be told exactly how to do it. its the kind of thing that I'll probably end up using callbacks for. but proceeding with this first pattern of use as if its the only one ;)
		if ($args->{save_valuesearched_items}) {
			$self->_save_valuesearched_items({ save_valuesearched_items => $args->{save_valuesearched_items}, edit_record_id => $process_report->{record_id} });
		}	
		
		#now handle the output. probably a redirect, but we could have been told to return 'callback_output_only'. do what we're told.
		if ($process_report->{callback_output_only}) {
			return $process_report->{callback_output};
		} else {
			return $self->redirect_runmode($actions->{ok}, $process_report->{redirect_params} );
		}

	} elsif ($process_report->{not_ok})  {
		
		#just handle the not_ok output ... which is probably a redirect.
		return $self->redirect_runmode($actions->{not_ok}, $process_report->{redirect_params} );

	} else {
		die "Unexpected result from form processing report."
	}	
	
}

sub _editform_related_records {
	my $self = shift;
	my $args = shift;

	my $relation_setup = $args->{relation_setup};
	my $tmpl_params    = $args->{tmpl_params};
	my $data_obj       = $args->{data_obj}; #the edit data obj. we can get stuff we need out of it.
	my $valuesearched_form_values = $args->{valuesearched_form_values};

	$self->ch_debug(['_editform_related_records: should be going to find records using this info, and then sticking something into tmpl params.', $relation_setup ]);
	if (!$tmpl_params->{related_records_display}) { $tmpl_params->{related_records_display} = []; }

	my $saved_search_results = {};
	my $unsaved_search_results = {};
	#so I think we're aiming to have stuff formatted as search results jammed into that search results hash
		#for whatever means we use to get the related records, should still structure the data in terms of search_results, as that is what we are set up with for templating.
	
	#if we have a record id for the dataobj and a relationship to get related records with, do so. (cannot do this bit without a record id tho!)
	if ($data_obj->record_id()) {
		if ($relation_setup->{relationship}) {
			#get using a relationship
			my $sort_relations = undef;
			if ($relation_setup->{sort_relations}) {
				$sort_relations = $relation_setup->{sort_relations};
			}
			my $relationship_func = 'get_' . $relation_setup->{relationship};
			#get a proper search result hashref from the relationship, and slap it in wholesale.
			$saved_search_results = $data_obj->$relationship_func({
				related_results       => 1, 
				record_id_param       => $relation_setup->{relation_name} . '_record_id',
				short_text            => 1,
				plaintext_html        => 1,
				sort_relations        => $sort_relations,
			});

#ok this was, I thought, a good idea, but now I'm thinking I should just stick with object relationships. no need to re-implement that here ... the below would still need to know by what fields the records would relate.
#		} elsif ($relation_setup->{relation_classname}) {
#			#get using a passed in object classname. (new 2007 06 08)
#			$saved_search_results = ($relation_setup->{relation_classname})->new($self)->get_search_results({
#				record_id_param => $relation_setup->{relation_name} . '_record_id',
#				short_text     => 1,
#				plaintext_html => 1,
#				user_sort      => $sort_relations,
#			});
		}
			
		$saved_search_results->{related_record_id_param} = delete($saved_search_results->{record_id_param}); #confusing to have multiple record_id_param vars being referenced at different levels, so renaming with related_ prefix for clarity.
		$saved_search_results->{relation_name} = $relation_setup->{relation_name};
		$saved_search_results->{relation_display_name} = $relation_setup->{relation_display_name};
		$saved_search_results->{multi_value_selection} = $relation_setup->{multi_value_selection} ? 1 : 0;
		$self->ch_debug(['_editform_related_records: got this list of saved_search_results records for a relation named', $saved_search_results, $relation_setup->{relation_name} ]);
	}
	
	#to display unsaved valuesearched values along side (above?) the already-existing-in-db-related-records, we can obtain some hashrefs and cram (unshift) them in.
	my $valuesearched_record_ids = $valuesearched_form_values->{$relation_setup->{valuesearched_target}};
	if ($valuesearched_record_ids && scalar(@$valuesearched_record_ids)) {
		my $records_obj;
		if ($relation_setup->{valuesearched_record_display_data_obj_classname}) {
			$records_obj = ($relation_setup->{valuesearched_record_display_data_obj_classname})->new($self);
		}
		if ($records_obj) {
			$unsaved_search_results = $records_obj->get_search_results({
				restrict => {
					record_id => { 
						match_cond => 'IN', 
						match_str => '(' . join(', ', map {'?'} @$valuesearched_record_ids ) . ')',
						bind_params => $valuesearched_record_ids,
					},
				},
				record_id_param => $relation_setup->{relation_name} . '_unsaved_valuesearched_record_id',			
				short_text      => 1,
				plaintext_html  => 1, 
			});
			$unsaved_search_results->{relation_name} = $relation_setup->{relation_name};
			$unsaved_search_results->{relation_display_name} = $relation_setup->{relation_display_name};

			$self->ch_debug(['_editform_related_records: getting details on the valuesearched records, we have found this set of results:', $unsaved_search_results]);
		}
	}

	#thinking that defining one set of buttons should be enough, and if they have to work different for saved/unsaved related records, then we'll handle that in the templating js calls. 
		#well, at any rate, only making buttons available under the "saved" results for now. The whole unsaved shit might not actually be used anymore.
	if ($relation_setup->{buttons}) {
		$saved_search_results->{related_record_buttons} = $self->form_button_vars($relation_setup->{buttons});
		$saved_search_results->{has_action_buttons}     = 1;
	} else {
		$saved_search_results->{has_action_buttons}     = 0;
	}		

	my $related_records_vars = {
		saved       => $saved_search_results, 
		has_saved   => $saved_search_results->{num_records} ? 1 : 0,
		unsaved     => $unsaved_search_results,
		has_unsaved => $unsaved_search_results->{num_records} ? 1 : 0,
		valuesearch_mode => $relation_setup->{valuesearch_mode}, #for template to use in js function calls for functions on these related records.
	};
	
	#slap them in the list.
	push(@{$tmpl_params->{related_records_display}}, $related_records_vars);

	#also the js funcs I'm gonna write to deal with all this shit are going to use jquery, so make sure we load that.
		#meh, this is dumb. going forward, jquery is generally going to be required, because I'm not likely going to be writing js that doesnt use it very much.
	#$tmpl_params->{jquery_support_required} = 1;
	
	return 1;
	#die "not finished ... need to go find related records if the dataobj is not a new record, also need to display info for records which were valuesearched but which have not been saved";
}

sub _save_valuesearched_items {
	my $self = shift;
	my $args = shift;
	
	if (!$args->{save_valuesearched_items}) { die "_save_valuesearched_items requires a save_valuesearched_items datastructure as an arg";	}
	if (!$args->{edit_record_id})           { die "_save_valuesearched_items requires a edit_record_id arg"; }
	
	$self->debuglog(['_save_valuesearched_items: before going over save_valuesearched_items']);
	foreach my $save_item (@{$args->{save_valuesearched_items}}) {
		if (!$save_item->{valuesearched_for_screen})            { die "_save_valuesearched_items, valuesearched_for_screen param was missing - wont know what screen params to look under";	}
		if (!$save_item->{valuesearched_target})                { die "_save_valuesearched_items, valuesearched_target param was missing - wont know what key under the screen params to look under"; }
		if (!$save_item->{save_record_with_data_obj_classname}) { die "_save_valuesearched_items, save_record_with_data_obj_classname param was missing - wont be able to save records";	}

		my $for_screen = $save_item->{valuesearched_for_screen};
		my $valusearched_record_ids = $self->session()->param('valuesearched_form_values')->{$for_screen}->{$save_item->{valuesearched_target}};
		my $save_with_data_obj = ($save_item->{save_record_with_data_obj_classname})->new($self);

		my $special_values = {
			_edit_record_id => $args->{edit_record_id},
		};

		#$self->ch_debug(['generic_processform_controller, going to save related valusearched records, using these related record ids:', ]);
		#save each of those records (assuming theres more than one).
		$self->debuglog(["_save_valuesearched_items: going to save records using an instance of classname $save_item->{save_record_with_data_obj_classname}"]);
		foreach my $record_id (@$valusearched_record_ids) {
			$special_values->{_valuesearched_record_id} = $record_id;
			my $field_values = {};
			
			#this is the part that might make more sense to use a callback for or something. but right now I see there really only being two fields that can be set in the target data obj by this, those being the id of the valuessearched record, and the id of the edit record its to be related to. then we just need to know what fields to stick them into. so I'm gonna accept a list of fields, and each one can either give a special value that maps to something we already know about, or a hardcoded value (or fuck maybe a callback to obatin the value for that field, that might be cool)
			foreach my $param (keys(%{$save_item->{save_using_field_params}})) {
				my $value = $save_item->{save_using_field_params}->{$param};
				if ($special_values->{$value}) {
					$value = $special_values->{$value};
				}
				$field_values->{$param} = $value;
			}
			
			$self->debuglog(['_save_valuesearched_items: about to save a record using this data obj class and these field values:', $save_item->{save_record_with_data_obj_classname}, $field_values ]);
			#die "stop before saving";
			
			$save_with_data_obj->new_record_for_edit()->set_edit_values($field_values)->save_edited_record();
			$self->debuglog(['_save_valuesearched_items: (finished saving the record)' ]);
			
		}
	}
	$self->debuglog(['_save_valuesearched_items: after going over save_valuesearched_items']);

	return undef;
}

sub _tweak_form_html {
	my $self = shift;
	my $args = shift;

	my $data_obj = $args->{data_obj};
	my $html_ref = $args->{html_ref};
	my $error_css_class = $args->{error_css_class} ? $args->{error_css_class} : 'error'; #classname to apply for a field label of a field that was in error can be supplied.
	
	my $edit_errors = $data_obj->get_edit_errors();
	$self->ch_debug(['_tweak_form_html: edit errors like: ', $edit_errors]);
	#require HTML::TokeParser;
	my $p = HTML::TokeParser->new($html_ref);
	#i think we care about any start tag that has an id attribute, and the subset of those we really care about are ones where there is a lbl_ prefix to it.
	#then we need to see what the lbl_ prefix is for, and check in our list of field errors if that one appears with a field_error of any kind ... and if so, apply an error class to the tag. simple as that. really!
	
#	#so we have to go thru the document find the 2nd level comments like <!-- 2nd level -->, then get the html from the open <tr which immediately follows, all the way to the close /tr>. Not sure on how exactly to approach this gayness.
#		#and btw I'm a retard thinking the module was totally broken -- wasted like an hour being a retard not seeing the html bits in the debug output .... because I WAS VIEWING IT IN A WEB BROWSER FUCKING RETARD. God I feel so dumb after that.
	my $errorflagged_html = undef;
	while (my $tok = $p->get_token()) {
		my $found_lbl    = 0;
		my $adjust_lbl   = 0;
		my $redefine_lbl = 0;
		my $error_lbl    = 0;
		my $lbl_for_param = undef;

		#is it a start token with an id attribute like lbl_.* where .* in the edit errors is flagged with an error?
#		if ($tok->[0] eq 'S' && $tok->[2]->{id} =~ /^lbl_(.*)/ && $edit_errors->{$1}->{field_error}) {
#			#$self->ch_debug(['_tweak_form_html: on a S token like: ', $tok]);
#			$adjust_lbl = 1;
#		}
		if ($tok->[0] eq 'S' && $tok->[2]->{id} =~ /^lbl_(.*)/) {
			#$self->ch_debug(['_tweak_form_html: on a S token like: ', $tok]);
			$found_lbl = 1;
			$lbl_for_param = $1;
		}

#		if ($found_lbl) { $self->ch_debug(['_tweak_form_html: working with label for field param:', $lbl_for_param ]); }
#		if ($found_lbl && $edit_errors->{$lbl_for_param}->{field_error})            { $error_lbl = 1; $adjust_lbl = 1; }
#		if ($found_lbl && $data_obj->fieldref($lbl_for_param)->{multi_lang_labels}) { $redefine_lbl = 1; $adjust_lbl = 1; }
		#update 2009 06 03 rewriting the above 3 lines into a bigger IF that can handle some stupid situation ... namely the code that goes to pull a fieldref can return nothing if the named label does not actuall have a fieldref. the error it was producing was not giving anything useful.
		if ($found_lbl) {
			$self->ch_debug(['_tweak_form_html: working with label for field param:', $lbl_for_param ]);
			if ($edit_errors->{$lbl_for_param}->{field_error}) { 
				$adjust_lbl = 1; 
				$error_lbl = 1; 
			}
			my $fieldref = $data_obj->fieldref($lbl_for_param);
			if ($fieldref && $fieldref->{multi_lang_labels}) { 
				$adjust_lbl = 1; 
				$redefine_lbl = 1; 
			}
		}
				
		if ($adjust_lbl) {

			if ($error_lbl) {
				#assuming token is a 'S' token if we're here and pulling the attrs from element 2.
					#add/override a class to the tag and then rebuild the tag with the updated attribute list.
				my $tag_attr = $tok->[2];
				$tag_attr->{class} = $error_css_class;
				$errorflagged_html .= '<' . $tok->[1] . ' ' . join(' ', map {$_ . '="' . $tag_attr->{$_} . '"'} keys(%{$tag_attr}) ) . '>';
			} else {
				#if we are not applying an error class while we are here adjusting labels, then keep the existing start tag for the label.
				$errorflagged_html .= $tok->[4];
			}

			if ($redefine_lbl) {
				#the actual label text should be the next text node, get up to that, and discard it. replace with correct text from the fieldref.
				#$self->ch_debug(['_tweak_form_html: with a token like', $tok]);
				$p->get_text(); #get the text of the label ... and discard it!
				my $new_lbl = $data_obj->fieldref($lbl_for_param)->{edit_display_name};
				$errorflagged_html .= $new_lbl;
			}			

		} else {
			#simple html reconstruction -- using ternary operator like a switch/case/if-elsif dealo.
			$errorflagged_html .= (($tok->[0] eq 'S') ? $tok->[4] :
									           ($tok->[0] eq 'E') ? $tok->[2] :
									           ($tok->[0] eq 'C') ? $tok->[1] : #2007 06 27 -- uhmm ... keeping comments is nice.
									           ($tok->[0] eq 'D') ? $tok->[1] : #2007 06 27 -- uhmm ... keeping doctype is nice. (declararions)
									           ($tok->[0] eq 'T') ? $tok->[1] : undef);
		}									         
	}
	return $errorflagged_html;
}

sub generic_delete_controller {
	my $self = shift;
	my $args = shift;
	
	my $form_name = $args->{form_name};
	my $data_obj  = $args->{data_obj};

	my $cgi = $self->query();
	my $record_id_param = 'record_id';
	if ($args->{record_id_param}) {
		$record_id_param = $args->{record_id_param};
	}
	my $record_id  = $cgi->param($record_id_param);
	
	if ($form_name && $data_obj) {	die "generic_searchform_controller: Sanity check: you passed a data obj AND a form_name? what should I be using??"; }
	if (!$data_obj && $args->{data_obj_classname}) {
		$data_obj = ($args->{data_obj_classname})->new($self);
	}
	if ($form_name && !$data_obj) {
		$data_obj = $self->get_new_dataobj($form_name, $record_id);
	} elsif ($data_obj) {
		$data_obj->record_id($record_id);
	}		
	if (!$data_obj) {
		die "Failed to obtain a data object";
	}

	#if (!$form_name) { die "generic_delete_controller: form_name argument is required\n"; } 
	my $actions = $args->{actions};
	if (!$actions) { die "generic_delete_controller: need actions acgument .. must pass like: actions => { ok => runmode_name }"; }

	$self->ch_debug(['generic_delete_controller: going to delete a record with an id like: ', $record_id, 'with a data obj whos form spec looka like: ', $data_obj->form_spec() ]);

	return $data_obj->delete_record($actions);
}

sub generic_tree_controller {
	my $self = shift;
	my $args = shift;
	
	my $tree_classname  = $args->{tree_classname} or die "tree_classname arg is required";
	my $items_classname = undef;
	#my $items_classname = $args->{items_classname}; 
	#i'm thinking, the only reason it HAS items is because tehre is a searchform that goes with it. the dobj used for the searchform would be the dobj to use for items manipulation. 
	if (!$items_classname && $args->{gsfc_args}->{data_obj_classname}) {
		$items_classname = $args->{gsfc_args}->{data_obj_classname};
	}
	if (!$items_classname) { die "items_classname could not be determined."; }
	my $treenode_field  = $args->{treenode_field} or die "treenode_field arg is required";
	my $for_screen      = $args->{for_screen} or die "for_screen arg is required";
	#my $tree_rm         = $args->{tree_rm} or die "tree_rm arg is required";
	
	#just some hacking and playing here. gonna use this mode for several parts of it while i can.
	my $cgi = $self->query();

	if ($cgi->param('json_tree')) {
		my $treeobj = $tree_classname->new($self);
		my $records = $treeobj->get_search_results({ user_sort => {parameter_name => 'display_order' }, restrict => {is_trashed => 0}})->{records_simple};

		my $records_formatted = [ map {{
			'attributes' => { id => 'treenode_' . $_->{record_id}, rel => 'folder', parent_id => $_->{parent_id}, record_id => $_->{record_id} },
			#'data'       => $_->{name} . ' - ' . $_->{record_id},
			'data'       => $_->{name},
			'children'   => [],
		}} @$records ];

		my $records_by_id = { map { $_->{attributes}->{record_id} => $_ } @$records_formatted };
		
		#just go thru the already-sorted list of records and make sure parents know about their direct childrens. this should bring the family together through references. except for orphans since they have no references. poor orphans. feed them to the pigs.
		foreach my $record (@$records_formatted) {
			my $parent_id = $record->{attributes}->{parent_id};
			if ($parent_id) {
				my $parent_ref = $records_by_id->{$parent_id};
				push(@{$parent_ref->{children}}, $record);
			}
		}

		#then get only the top-level nodes out. bam done.
		#my $tree = [  ]; #now just get out the top level parents who have now been told about their childrens.
		my $tree = [{
			'attributes' => { id => 'treenode_root', rel => 'root' },
			'data'       => 'Unsorted',
			'state'      => 'open',
			'children'   => [ grep { !$_->{attributes}->{parent_id} } @$records_formatted ],
		},{
			'attributes' => { id => 'treenode_wastebin', rel => 'wastebin', record_id => 'wastebin' },
			'data'       => { title => 'Wastebin', icon => 'remove.png' },
			'children'   => [ map {{
				'attributes' => { id => 'treenode_' . $_->{record_id}, rel => 'wastebin_item', parent_id => $_->{parent_id}, record_id => $_->{record_id} },
				'data'       => $_->{name},
			}} @{ $treeobj->get_search_results({ user_sort => {parameter_name => 'name' }, restrict => {is_trashed => 1}})->{records_simple} } ]
		}];

		$self->ch_debug(['made this tree:', $tree, 'from this:', $records ]);
		
		return JSON::XS::encode_json($tree);
	}

	if ($cgi->param('tree_action')) {
		my $tree_action = $cgi->param('tree_action');
		if ($tree_action eq 'createnode') {
			my $parent_id = $cgi->param('parent_id');
			my $ref_node_id = $cgi->param('ref_node_id');
			my $ref_type = $cgi->param('ref_type'); #seems to always be one of 'after' or 'inside'. and only 'inside' if there is nothing already inside the parent for it to go 'after'.
			my $after_node_id = undef;
			if ($ref_type eq 'after') {
				$after_node_id = $ref_node_id;
			}
			my $restrictor = { parent_id => $parent_id };
			if (!$parent_id) { 
				$parent_id = undef;
				#gah .. you know what i should do .. in sql abstraction if the bind param value is undef for a simple restrictor the sql abstraction should automatically turn it into a complex IS NULL type of restrictor. but it doesnt. 
				$restrictor = {parent_id => { match_cond => 'IS',  match_str => 'NULL'}};
			} #no parent_id means its a root level node.

			my $treenodes = $tree_classname->new($self)->get_search_results({ restrict => $restrictor, user_sort => {parameter_name => 'display_order'} })->{records_simple};
			my $tree_obj  = $tree_classname->new($self);
		
			my $dispord_incr = 10;
			my $disp_ord = 0;
			my $new_node_disp_ord = undef;
			my $new_node_id = undef;
			
			#logic here largely borrowed from Libarary::BMG::CMS::add_stack, simplified a bit.
				#note if we didnt get a $after_node_id it should be because there was no node to put it after and it will be an only-child.
			#$self->debuglog(['tree_experiment: must find out display order of new node. here is existing nodes under the same parent:', $treenodes, 'obtained using restrictor:', $restrictor, 'node ref stuff:', { parent_id => $parent_id, ref_node_id => $ref_node_id, ref_type => $ref_type, after_node_id => $after_node_id } ]);

			foreach (@$treenodes)	{
				$disp_ord += $dispord_incr;
		
				#save existing node with a display order.
				$tree_obj->load($_->{record_id})->set_edit_values({
					display_order => $disp_ord,
				})->save_edited_record();
		
				if (!$new_node_disp_ord && ($after_node_id == $_->{record_id}) ) {
					#new stack will go after some other node ... after THIS node!
					$disp_ord += $dispord_incr; #incr display order so we have something new
					$new_node_disp_ord = $disp_ord; #so it gets the NEW display order we just incr'd, so it like, goes AFTER the stack we just saved a second ago.
				}
			}
			#if we got here without having figured out a $new_node_disp_ord then its probably going to be an only child. so it should start at the lowest it would normally be.
			if (!$new_node_disp_ord) { $new_node_disp_ord = $dispord_incr; }

			my $new_node_id = $tree_obj->new_record_for_edit({
				name          => 'new tree node',
				parent_id     => $parent_id,
				display_order => $new_node_disp_ord,
			})->save()->record_id();
			#die "feeling unfriendly";
			return JSON::XS::encode_json({'new_node_id'=>$new_node_id});
		
		} elsif ($tree_action eq 'renamenode') {
			my $node_id = $cgi->param('node_id');
			my $node_name = $cgi->param('node_name');
			if (!$node_id || !$node_name) {
				die "Either node_id or node_name was missing.";
			}
			$tree_classname->new($self, {record_id=>$node_id})->set_edit_values({name=>$node_name})->save();
			return JSON::XS::encode_json({'success'=>1});

		} elsif ($tree_action eq 'movenode') {
			my $node_id     = $cgi->param('node_id');
			my $ref_node_id = $cgi->param('ref_node_id');
			my $ref_type    = $cgi->param('ref_type'); #seems to always be one of 'after' or 'inside'. and only 'inside' if there is nothing already inside the parent for it to go 'after'.
			#$self->debuglog(['tree_experiment: must mess with display orders. the one with the node_id has to go in ref_type style in relation to ref_node_id.', { ref_node_id => $ref_node_id, ref_type => $ref_type, node_id => $node_id } ]);

			#from what I can tell, 
				#inside = now a child of the ref node, at the end of the display orders.
				#before = now a child of ref_node's parent, display order before that of ref_node.
				#after  = now a child of ref_node's parent, display order after that of ref_node.
			my $new_parent_id = undef;
			if ($ref_type eq 'inside') {
				$new_parent_id = $ref_node_id;
			} else {
				$new_parent_id = $tree_classname->new($self, {record_id=>$ref_node_id})->val('parent_id');
			}

			my $restrictor = { parent_id => $new_parent_id };
			if (!$new_parent_id) { 
				$new_parent_id = undef;
				#gah .. you know what i should do .. in sql abstraction if the bind param value is undef for a simple restrictor the sql abstraction should automatically turn it into a complex IS NULL type of restrictor. but it doesnt. 
				$restrictor = {parent_id => { match_cond => 'IS',  match_str => 'NULL'}};
			} #no parent_id means its a root level node.
			##oh yeah, dont include the node we are moving in the result.
			#$restrictor->{record_id} = { match_cond => '!=', match_str => '?', bind_params => $node_id };

			my $siblings = $tree_classname->new($self)->get_search_results({ restrict => $restrictor, user_sort => {parameter_name => 'display_order'} })->{records_simple};
			my $tree_obj = $tree_classname->new($self);
		
			my $dispord_incr = 10;
			my $disp_ord = 0;

			#$self->debuglog(['tree_experiment: need to fit the node amongst:', $siblings, 'obtained with restrictor:', $restrictor ]);

			my $node_new_vals = { parent_id => $new_parent_id };
			foreach (@$siblings)	{
				if ($_->{record_id} == $node_id) { next; } #node was in the siblings already. dont let that mess up our reordering.
				
				$disp_ord += $dispord_incr;
		
				if ($ref_type eq 'before' && $_->{record_id} == $ref_node_id) {
					$node_new_vals->{display_order} = $disp_ord;
					$disp_ord += $dispord_incr;
				}
		
				#save existing node with a display order.
				$tree_obj->load($_->{record_id})->set_edit_values({
					display_order => $disp_ord,
				})->save_edited_record();

				if ($ref_type eq 'after' && $_->{record_id} == $ref_node_id) {
					$disp_ord += $dispord_incr;
					$node_new_vals->{display_order} = $disp_ord;
				}
			}
			if ($ref_type eq 'inside') {
				#inside means at the end of the children of the ref node. so, here.
				$disp_ord += $dispord_incr;
				$node_new_vals->{display_order} = $disp_ord;
			}

			#apply the change to display_order and (possibly) parent_id to the node that was moved.
			$tree_obj->load($node_id)->set_edit_values($node_new_vals)->save_edited_record();
	
			#$self->debuglog(['tree_experiment: resulted in newly fetched siblings like: ', $tree_classname->new($self)->get_search_results({ restrict => $restrictor, user_sort => {parameter_name => 'display_order'} })->{records_simple} ]);

			return JSON::XS::encode_json({'success'=>1});
		} elsif ($tree_action eq 'trashnode') {
		
			my $node_id = $cgi->param('node_id');
			if (!$node_id) {
				die "node_id was missing.";
			}

#			##Yeah I thought this was reasonable but Steve wants some kind of trash-can type shit. fuck me.
#			#if its got children of any kind (folders or leaves) lets just not delete it.
#			#find other tree nodes that this is the parent of:
#			my $child_nodes = Library::BMG::DataObj::ImageTree->new($self)->get_search_results({
#				restrict => { parent_id => $node_id }
#			})->{records_simple};
#			my $node_items = Library::BMG::DataObj::Image->new($self)->get_search_results({
#				restrict => { imagetree_id => $node_id }
#			})->{records_simple};
#
#			my $has_child_things = 0;
#			if (scalar(@$child_nodes)) { $has_child_things = 1; }
#			if (scalar(@$node_items))  { $has_child_things = 1; }
#			
#			my $result = {success=>1};
#			if (!$has_child_things) {
#				#it has no child things. kill it in the face.
#				Library::BMG::DataObj::ImageTree->new($self, {record_id=>$node_id})->delete_record();
#			} else {
#				$result->{success} = 0;
#				$result->{node_not_empty} = 1;
#			}

			$tree_classname->new($self, {record_id=>$node_id})->set_edit_values({ is_trashed => 1 })->save_edited_record();
			my $result = {success=>1};
			
			return JSON::XS::encode_json($result);

		} elsif ($tree_action eq 'untrashnode') {
			my $node_id = $cgi->param('node_id');
			if (!$node_id) { die "node_id was missing."; }
			$tree_classname->new($self, {record_id=>$node_id})->set_edit_values({ is_trashed => 0 })->save_edited_record();
			my $result = {success=>1};
			return JSON::XS::encode_json($result);

		} elsif ($tree_action eq 'emptytrash') {
			#now the fun begins.
			my $treeobj  = $tree_classname->new($self);
			my $itemsobj = $items_classname->new($self);
			my $records  = $treeobj->get_search_results({restrict => {is_trashed => 1}})->{records_simple};
			$self->debuglog(['emptytrash']);
			$self->recursive_tree_kill({ 
				records => $records, 
				tree_dataobj => $treeobj, 
				items_dataobj => $itemsobj,
				treenode_field => $treenode_field,
			});
			my $result = {success=>1};
			return JSON::XS::encode_json($result);

		} elsif ($tree_action eq 'treedrop') {
			#associate some record with some treenode.
			my $ref_node_id = $cgi->param('ref_node_id');
			my $ref_type    = $cgi->param('ref_type'); 
			my $item        = $cgi->param('item');
			
			if (!$ref_type || !$item) { die "a required param(s) was missing."; }
			if (!$ref_node_id) { $ref_node_id = undef; } #if we didnt get it make sure its really undef so we stick the item into the root of the tree.
			#if the type is inside, then the ref_node_id gives us the treenode_id to stick the item under.
			#otherwise, the ref_node_id gives us the node whos PARENT we have to stick the item under.
			#item comes in the form of rec_\d+_handle. the numeric bit is all i care about.
			(my $item_id = $item) =~ s|^.*?(\d+).*$|$1|;
			my $new_treenode_id = $ref_node_id;
			if ($ref_type ne 'inside') {
				#its not an 'inside' which means it must be a 'before' or 'after' and we dont really care what since we are stickig an item into a folder. the folder to stick it into is the parent folder of whatever we were told to put it before or after.
				$new_treenode_id = $tree_classname->new($self, {record_id=>$ref_node_id})->val('parent_id');
			}
			
			#now associate the item with its new treenode id.
			$items_classname->new($self, {record_id=>$item_id})->set_edit_values({
				$treenode_field => $new_treenode_id,
			})->save();
			
			$self->debuglog(['tree_experiment: treedrop with: ', { ref_node_id => $ref_node_id, ref_type => $ref_type, item => $item, item_id => $item_id }]);
			my $result = {success=>1};
			return JSON::XS::encode_json($result);
		}

	}
	
	my $gsfc_args = $args->{gsfc_args};
	# a couple things here I'm expecting will be hardcoded always here. i guess i'll code for them to be allowed to be provided and if not we'll do defaults.
	if (!$gsfc_args->{for_screen}) { $gsfc_args->{for_screen} = $for_screen; }
	if (!$gsfc_args->{ajax_mode})  { $gsfc_args->{ajax_mode}  = { addtl_params_func => 'tree_params' }; }

	my $treenode_search = $cgi->param('treenode_search');
	if ($treenode_search) {
		#only need to pick up a treenode_id when doing ajax_searchform. and restrict based on it.
		my $treenode_id = $cgi->param('treenode_id');
		$self->debuglog(['tree_experiment: treenode_id was:', $treenode_id ]);
		#pick a restrictor depending on whether we have to match a actual treenode id or a NULL treenode id.
		my $nodeitems_restrict = $treenode_id ? { $treenode_field => $treenode_id } : { $treenode_field => { match_cond => 'IS', match_str => 'NULL' } };
		$gsfc_args->{forced_search_params} = { restrict => $nodeitems_restrict };
	} else {
		$gsfc_args->{'reset'} = 1;
	}

	my $tmpl_params = $self->generic_searchform_controller($gsfc_args);
	$tmpl_params->{treedrop_handles} = 1;
	$tmpl_params->{tree_rm} = $for_screen;
	$tmpl_params->{jstree_support_required} = 1;

	if ($treenode_search) {
		return $self->render_interface_tmpl(['general/search_result_table.tmpl'], $tmpl_params, { standalone => 1 });
	}
		
	#regular template output of the whole master with subtmpl. this should only be rendered the first time the mode is requested as all subsequent requests will be tree updates or for treenode searches output html blocks.
	return $self->render_interface_tmpl(['general/generic_tree.tmpl'], $tmpl_params );
	
}
sub recursive_tree_kill {
	my $self = shift;
	my $args = shift;
	
	#accept args 
	
	my $records       = $args->{records};
	my $tree_dataobj  = $args->{tree_dataobj};
	my $items_dataobj = $args->{items_dataobj};
	my $treenode_field = $args->{treenode_field};

	#$self->debuglog(['recursive_tree_kill: here with records: ', $records, 'treenode field is', $treenode_field ]);

	$args->{depth}++;
	if ($args->{depth} > 100) { die "insane recursion error."; }
	
	foreach my $record (@$records) {
		#get kids and walk down the tree	
		my $childrens = $tree_dataobj->get_search_results({restrict => {parent_id=>$record->{record_id}}})->{records_simple};
		$args->{records} = $childrens;
		$self->recursive_tree_kill($args);

		#place any items that were in this node into no node.
		my $items = $items_dataobj->get_search_results({restrict=>{$treenode_field=>$record->{record_id}}})->{records_simple};
		#$self->debuglog(['recursive_tree_kill: here1 after coming back up from step down into things. items i must locate under no node:', $items ]);
		foreach my $item (@$items) {
			my $new_vals = { $treenode_field => undef };
			$items_dataobj->load($item->{record_id})->set_edit_values($new_vals)->save();
		}
		
		#kill the treenode.
		#$self->debuglog(['recursive_tree_kill: to remove this record id using obj of type', $record->{record_id}, ref($tree_dataobj) ]);
		$tree_dataobj->record_id($record->{record_id})->delete_record();
	}

	$args->{depth}--;
	return 1;
}

sub generic_valuesearch_controller {
	my $self = shift;
	my $args = shift;
	
	my $cgi = $self->query();
	#if its a editform submission, we gotta know what screen its for so we can then save the cgi params.
	#the reason we're here is beacuse we're going off to find a/some value(s) with a searchform, that are gonna be needed back on this first screen.
	#so I think anything that needs to go off to another screen is going to have to hit a custom rm, that will then go through this iwth all the right params.
		#those may be wildassed assumptions to be better conrrolled through args.
	my $for_screen         = $args->{for_screen};
	my $valuesearch_mode   = $args->{valuesearch_mode}; #s/b the name of the valuesearch runmode that sent us into here. we can reuse the rm as a rm name for doing the searching.
	my $edit_data_obj      = $args->{edit_data_obj};
	my $search_data_obj    = $args->{search_data_obj};
	my $multi_value_search = $args->{multi_value_search};
	my $edit_record_id_param     = $args->{edit_record_id_param}     ? $args->{edit_record_id_param}     : 'record_id';
	my $searched_record_id_param = $args->{searched_record_id_param} ? $args->{searched_record_id_param} : 'record_id';
	my $search_params      = $args->{search_params} ? $args->{search_params} : {}; #search params to force, along with anything that we'd force from this automatically.
	my $values_target      = $args->{values_target}; #unique name to store the searched values with, failling under the screen name (could go off to different valuesearches for the same screen)
	
	#couple vars for minor record operations, like removing unsaved/valuesearched and saved related records.
	my $relation_name              = $args->{relation_name};
	my $related_data_obj_classname = $args->{related_data_obj_classname};

	my $begin_valuesearch  = 0;
	my $valuesearching     = 0;
	my $back_to_originator = 0; #is it time to go back to the originator/initiator runmode?
	my $searchedvalues     = 0; #bool for if we successfully searched values. will stay false if we cancelled.
	my $selected_values    = {};

	if ($cgi->param('begin_valuesearch_from_editform')) {
		#this is the bit where we need to save all those form params that were just submitted in the session, so that we can re-show the form when we come back to it in the same state it was in before.
		$edit_data_obj->pickup_and_sessionize_cgi_values({ for_screen => $for_screen});

		#also take note of the record id in the session (which there may not be if its a new record, but we should send it back if we had one)
		$self->session()->param('valuesearched_for_record_id')->{$for_screen} = $cgi->param($edit_record_id_param);

		#now show the search screen. its probbaly a new search.
		$begin_valuesearch = 1;
	}

	if ($cgi->param('begin_valuesearch_from_viewform')) {
		$self->session()->param('valuesearched_for_record_id')->{$for_screen} = $cgi->param($edit_record_id_param);
		$begin_valuesearch = 1;
	}

	
	if ($cgi->param('related_record_operation_type')) {
		#we're going to be doing something with our valuesearched records, either saved or unsaved, based on the related_record_operation_type we should be able to figure out what we're doing.
		if (!$relation_name) { die "generic_valuesearch_controller: cannot perform related_record_operation without known the relation_name (mainly b/c we need that to get the correct record_id out of the cgi)"; }

		#note record id so we can return back to edit after.
		my $edit_record_id = $cgi->param($edit_record_id_param);
		$self->session()->param('valuesearched_for_record_id')->{$for_screen} = $edit_record_id;
		$self->ch_debug(['generic_valuesearch_controller: performing an action for records related to an edit record id of:', $self->session()->param('valuesearched_for_record_id')->{$for_screen}, 'for_screen, edit_record_id_param, edit_record_id: ', $for_screen, $edit_record_id_param, $edit_record_id ]);
		#die "stop to ensure we know the edit record id";
		
		#and grab all the form values if its an editform submission.
		if ($cgi->param('editform_submission')) {
			$edit_data_obj->pickup_and_sessionize_cgi_values({ for_screen => $for_screen});
		}

		my $operation = $cgi->param('related_record_operation_type');
		if ($operation eq 'remove_unsaved') {
			#here we're simply removing item(s?) from the list of valuesearched record ids. easy..
			my $remove_value = $cgi->param($relation_name . '_unsaved_valuesearched_record_id');
			my @filtered = grep { $_ ne $remove_value } @{$self->session()->param('valuesearched_form_values')->{$for_screen}->{$values_target}};
			$self->session()->param('valuesearched_form_values')->{$for_screen}->{$values_target} = \@filtered;
		} elsif ($operation eq 'remove_saved') {
			#to remove a saved related record, we need a data obj to do that. we should be given the classname of a data obj where we can just remove them based on the id we pick up from cgi.
				#not even sure this stuff really belongs in here.
			#2008 04 01 updated to handle multiple values. the unsaved shit above will need this too if it ever gets used.
			my @remove_values = $cgi->param($relation_name . '_record_id');
			#$self->ch_debug(['generic_valuesearch_controller: going to be removing related records with ids of:', \@remove_values ]);
			#die "stopping before removing saved valuesearched item.";
			if (!@remove_values) { die "generic_valuesearch_controller: failed to obtain a remove_value/record_id to operate on. "; }
			if (!$related_data_obj_classname) { die "generic_valuesearch_controller: cannot perform related_record_operation on a saved related record without knowing the classname to use for that operation. (values we are to remove must be pk field of the data obj as well)"; }
			
			#2008 06 09 - I've decided that I want to still be able to use this minor operation shit but i need more complicated actions so i'm coding hook for using a callback.
			if ($args->{remove_saved_callback}) {
				#custom behavior via callback. give it the record ids
				$args->{remove_saved_callback}->($self, { record_ids => \@remove_values, data_obj_classname => $related_data_obj_classname });
				
			} else {
				#super-simple automatic way. not very intelligent.
				my $remove_dataobj = ($related_data_obj_classname)->new($self);
				#$self->ch_debug(['generic_valuesearch_controller: instantiated with this classname, the following object:', $related_data_obj_classname, $remove_dataobj ]);
				foreach my $remove_value (@remove_values) {
					$remove_dataobj->record_id($remove_value)->delete_record();
				}
			}
		} else {
			die "Illegal operation";
		}
		
		$back_to_originator = 1;
	}

	if ($cgi->param('valuesearching')) {
		#its safe to just spit out the search results.
		$valuesearching = 1;
	}
	
	if ($cgi->param('searchedvalues_submission')) {
		#this would be the final process, they've said 'use' the values, and so here we are.

		#figure out where in cgi values come from 
			#using json for multi-values-across-multi-pages.
		$self->debuglog(['generic_valuesearch_controller: handling searchedvalues_submission']);

		#get values out of cgi
		my (@selected_values, $selected_value);
		if ($args->{multi_value_search}) {
			#@selected_values = $cgi->param($record_id_param);
			$selected_values = {};
			@selected_values = ();
			if ($cgi->param('selected_values')) {
				$selected_values = JSON::Syck::Load($cgi->param('selected_values'));
				@selected_values = grep { $selected_values->{$_} } keys(%$selected_values);
			}
			
		} else {
			my $record_id_param = 'record_id';
			if ($args->{searched_record_id_param}) {
				$record_id_param = $args->{searched_record_id_param};
			}
			$selected_value = $cgi->param($record_id_param);
		}

		#save values to session.
			#i think i always want to do that as an arrayref, makes it easier to process later, just loop over the values and if theres only one, so fuckin what.
		$self->session()->param('valuesearched_form_values')->{$for_screen}->{$values_target} = $args->{multi_value_search} ? \@selected_values : [ $selected_value ];

		#is there ever a chance we might want to actually SAVE that shit? why yes, yes there fucking is! and fortunately we already came up with a way of describing that.
		if ($args->{save_valuesearched_items}) {
			#we can (and must, if they are missing) set some default parameters for each of the save_valuesearched_items. But dont be afraid to specify these things explicitly when calling this generic_valuesearch_controller.
			foreach (@{$args->{save_valuesearched_items}}) {
				if (!$_->{valuesearched_for_screen})            { $_->{valuesearched_for_screen}            = $for_screen; }
				if (!$_->{valuesearched_target})                { $_->{valuesearched_target}                = $values_target; }
				if (!$_->{save_record_with_data_obj_classname}) { $_->{save_record_with_data_obj_classname} = $related_data_obj_classname; }
			}
			$self->_save_valuesearched_items({ save_valuesearched_items => $args->{save_valuesearched_items}, edit_record_id => $self->session()->param('valuesearched_for_record_id')->{$for_screen} });
		}	

		#or maybe we will call a function with the values. we should get the vlaues outside of that if then.
		$self->ch_debug(['generic_valuesearch_controller: used these values: ', $self->session()->param('valuesearched_form_values')->{$for_screen}->{$values_target} ]);
		#die "so we should have picked up the value(s) and saved to session. now we have to go back to the editform. is that gonna work right? should do retry form. but probably need to send the record id (using the right record id param) unless its a new record still over there.";
		$searchedvalues = 1;
		$back_to_originator = 1;
		$self->debuglog(['generic_valuesearch_controller: finished handling searchedvalues_submission']);
	}

	if ($cgi->param('valuesearch_cancelled')) {
		#this would be the final process, they've said 'use' the values, and so here we are.
		#die "cancelled -- are we gonna go back to the edit form properly?";

		#make sure no values is saved to the session - because we cancelled.
		$self->session()->param('valuesearched_form_values')->{$for_screen}->{$values_target} = undef;
		$back_to_originator = 1;
	}
	
	### We've determined what to do .. now we will do it.
	my $redirect_params = {};
	if ($back_to_originator) {
		$redirect_params = {
			retry_form            => 1,
			$edit_record_id_param => $self->session()->param('valuesearched_for_record_id')->{$for_screen},
		};
		
		#if we finished the job we can set this flag too. that should let the editform controller know it has some values to do something with.
		if ($searchedvalues) {
			$redirect_params->{valuesearched_values} = 1;
		}
		
		return $self->redirect_runmode($for_screen, $redirect_params );

	} elsif ($begin_valuesearch) {
		#so we would have just come from an edit form, saved form params in session, and now we will safely redirect back into the valuesearch mode. which will end up having us do the stuff below.
		$redirect_params->{valuesearching} = 1;
		return $self->redirect_runmode($valuesearch_mode, $redirect_params );

	} elsif ($valuesearching) {
		#probbaly need to do a bit more here, like send a bunch of templating vars to the searchform controller, and set the mutli-value flag thinger (which is nyi across the board)

		my $all_search_params = { %$search_params, search_initially => 1 };
		$self->ch_debug(['generic_valuesearch_controller: returning generic_searchform_controller output, using forced_search_params of:', $all_search_params]);

		return $self->generic_searchform_controller({
			form_label           => $args->{form_label},
			for_screen           => $valuesearch_mode,
			data_obj             => $search_data_obj,
			forced_search_params => $all_search_params,
			valuesearching       => 1,
			multi_value_search   => $args->{multi_value_search},
			buttons => [{
				type => 'valuesearch_use',
				process_runmode => $valuesearch_mode
			},{
				type => 'valuesearch_cancel',
				process_runmode => $valuesearch_mode,
			}],
			render => 1,
		});

	} else {
		die "generic_valuesearch_controller: Not sure what to show you.";
	}

}	
	
### DOnt get too attached to this code. this was a thought experiment. it may not really be what we want to do. or it might. lets see. 
sub generic_conf_controller {
	my $self = shift;
	my $args = shift;

	my $all_strings_suffix  = $args->{string_suffix};	
	if (!$all_strings_suffix && $args->{name}) {
		$all_strings_suffix = $args->{name}; #cuz I dont like saying string_suffix ... I want to pretend I'm asking for a conf that has a name.
	}
	my $suffix_overrides    = $args->{string_suffix_overrides}; #keys would be among the predefined list of conf string prefixes, values would be the suffix to use/look for..
	my $direct_strings      = $args->{direct_strings} ? $args->{direct_strings} : {}; #give a way to forget about going to get interface strings (oh sooo bad to not do that tho) and have hardcoded-in-source shit jammed right in!
	my $tmpl_params         = $args->{tmpl_params} ? $args->{tmpl_params} : {};

	my $string_prefixes = [ 'conf_body', 'conf_heading' ]; #maybe we'll have other well defined elements later too!
	my $string_names = [];
	my $tmpl_param_map = {}; #map of "standard" tmpl_var names to the stringname that we'll be getting in $strings.
	
	#figure out the actual string names to ask for, and map those to a set of standard var names to use in the template
	foreach (@$string_prefixes) {
		if ($direct_strings->{$_}) { next; } #dont get this one from the db in this case.
		my $string_name = $_ . '__' . ($suffix_overrides->{$_} ? $suffix_overrides->{$_} : $all_strings_suffix);
		push(@$string_names, $string_name);
		$tmpl_param_map->{$_} = $string_name;
	}

	#get the strings, in the HTC rendering mode so that they can be little micro templates that get rendered.
	$self->ch_debug(['generic_conf_controller: going to use these string names: ', $string_names ]);
	my $strings = {};
	if (scalar(@$string_names)) {
		$strings = $self->get_strings($string_names, { render => 1, tmpl_params => $tmpl_params });
	}
	$self->ch_debug(['generic_conf_controller: used these stringnames to get back these strings:', $string_names, $strings]);

	#put the strings at the standard tmpl_var names.
	###oops might want to NOT obliterate passed in tmpl_params....
	###my $tmpl_params = {
	###	form_label => $args->{form_label},
	###};
	$tmpl_params->{form_label} = $args->{form_label};
	
	foreach(@$string_prefixes) {
		if ($direct_strings->{$_}) { 
			#use directly passed string if provided (icky and lazy to hardcode strings! especially when ones from the db can be treated like tmpls!)
			$tmpl_params->{$_} = $direct_strings->{$_};
		} else {
			#or use what was collected from the db (better)
			$tmpl_params->{$_} = $strings->{$tmpl_param_map->{$_}}; #pull string out of $strings and place it in an already known tmpl param (defined by the prefixes list)
		}
	}

	#setup for some debug output if asked to ...
	if ($self->param('debug_mode') || $self->config('include_conf_screen_debug')) {
		$tmpl_params->{debug_conf_info} = 1;
		$tmpl_params->{debug_stringnames} = join(', ', @$string_names);
		$tmpl_params->{debug_direct_strings_used} = scalar(keys(%$direct_strings)) ? 'Yes' : 'No';
	}

	#handle automatic carry-forward of record_id that we would be dealing with from some screen.
	my $record_id_param = 'record_id';
	if ($args->{record_id_param}) {
		$record_id_param = $args->{record_id_param};
	}
	my $cgi = $self->query();
  my $record_id = undef;
	if ($args->{record_id})  { 
		$record_id = $args->{record_id};
	} else {
		$record_id = $cgi->param($record_id_param);
	}
	$tmpl_params->{record_id} = $record_id;
	$tmpl_params->{record_id_param} = $record_id_param;
	$tmpl_params->{suppress_auto_heading} = $args->{suppress_auto_heading};
	if ($args->{buttons}) {
		$tmpl_params->{conf_buttons} = $self->form_button_vars($args->{buttons});
		$tmpl_params->{has_buttons} = 1;
	}	
	
	#render the output.
	return $self->render_interface_tmpl([$args->{tmpl_name}?$args->{tmpl_name}:'general/generic_conf.tmpl'], $tmpl_params, $args->{render_args} );	
}

sub form_button_vars {
	my $self = shift;
	my $buttons = shift;
	my $args = shift;
	
	my $btn_id = 0;
	my $tmpl_buttons = [];
	
	if ($buttons) {
		foreach my $btn (@$buttons) {
			#rebuild array but with added keys. May also need to do additional processing for some types of buttons. at the time of this writing the only thing to add is a key for the type_ variable.
			my $btn_params = [];
			if ($btn->{params}) {
				#turn a hashref into an array ref of hashrefs with name and value attributes.
				@{$btn->{button_params}} = map { {name => $_, value => $btn->{params}->{$_}} } keys(%{$btn->{params}});
				#and since that is going to be stupid to work with and I want to try something else, also include the original d.s as a JSON string!
				$btn->{json_params} = JSON::Syck::Dump($btn->{params});
			}

			push (@$tmpl_buttons, {
				'type_' . $btn->{type} => 1, #the type definition
				'id' => ++$btn_id,
				%$btn, #and the rest of the properties.
			});
		}
		$self->ch_debug(['form_button_vars: requested as', $buttons, 'processed into', $tmpl_buttons]);
		return $tmpl_buttons;;
	} else {
		return undef;
	}
}

#####Also, break out this stuff into a SpApp::DataFormatter module or something. anyone that calls format_row_disp_values will have to call it that way.
###how bout some docs here .... ugh. maybe build them as i use this thing more.
	#args hashref:
	#	- row: hashref of row values to format.
	# - formatting: formatting descriptor.
	#Formatting descriptors:
	#??? hahah 
sub format_row_disp_values {
	my $self = shift;
	my $args = shift;
	my $row = $args->{row};
	my $formatting = $args->{formatting};
	
	foreach my $fld (keys(%$formatting)) {
		$row->{$fld . '_disp'} = $row->{$fld};
		my $str = undef;
		if ($row->{$fld} < 0 && $formatting->{$fld}->{lt_zero_value}) {
			$str = $formatting->{$fld}->{lt_zero_value};
		} elsif (!defined($row->{$fld}) && defined($formatting->{$fld}->{undef_val_final_str})) {
			$str = $formatting->{$fld}->{undef_val_final_str};
		} elsif ($formatting->{$fld}) { 
			$str = $row->{$fld . '_disp'};
			my $abs_neg_parens = 1; #negative numbers are converted to their absolute value and then parenthesized ... thats the default anyway. can turn it off.
			if (exists($formatting->{$fld}->{no_abs_neg_parens})) {
				$abs_neg_parens = 0;
			}
			if ($abs_neg_parens) {
				$str = abs($str); #only do abs() on it if that behaviour was not turned off (still doing it by default - is actually prettier and more standard in the realm of high finanace I thinks)
			}
			
			if ($formatting->{$fld}->{multiplier}) {
				$str = $str * $formatting->{$fld}->{multiplier};
			}
			if (defined($formatting->{$fld}->{decimals})) {
				if ($formatting->{$fld}->{formatter_module}) {
					my $decimal_style = 'en';
					if ($formatting->{$fld}->{decimal_style}) { $decimal_style = $formatting->{$fld}->{decimal_style}; }
					my $decimal_chars = {'en'=>'.','fr'=>','};
					my $thousands_sep = ' ';
					if ($formatting->{$fld}->{thousands_sep}) { $thousands_sep = $formatting->{$fld}->{thousands_sep}; }
					my $formatter = Number::Format->new(
						DECIMAL_DIGITS     => $formatting->{$fld}->{decimals},
						THOUSANDS_SEP      => $thousands_sep,
						DECIMAL_POINT      => $decimal_chars->{$decimal_style},
						MON_THOUSANDS_SEP  => ' ',
						MON_DECIMAL_POINT  => $decimal_chars->{$decimal_style},
						DECIMAL_FILL       => 1,
					);
					$str = $formatter->format_number($str);
				} else {
					$str = sprintf("%.$formatting->{$fld}->{decimals}f", $str);
					if ($formatting->{$fld}->{decimal_style} eq 'fr') {
						#change . to , for fr.
						$str =~ s|\.|,|;
					}
				}
			}

			if ($row->{$fld} > 0 && $formatting->{$fld}->{gt_zero_prefix}) {
				$str = $formatting->{$fld}->{gt_zero_prefix} . $str;
			}

			#percent number handling
			if ($formatting->{$fld}->{'%'}) {
				$str = $str . '%';
			}
			
			#2007 07 19, revising the negative number parenthesis handling. could be abs value in parens, or could be plain value with the minus sign in front.
			if (($row->{$fld} < 0) && $abs_neg_parens) {
				$str = '(' . $str . ')';
			}
				
			if ($formatting->{$fld}->{prefix})   { $str = $formatting->{$fld}->{prefix} . $str; }
			if ($formatting->{$fld}->{'$'}) { $str = '$' . $str; }
			if ($formatting->{$fld}->{'()'}) { $str = '(' . $str . ')';	} #i had thought some fields always have to go in parens ... but maybe not.
		}
		$row->{$fld . '_disp'} = $str;			
	}
	return 1; #we are modifying references.. nothing really to return.
}
#formerly known as monify
sub round_cents {
	my $self = shift;
	my $number = shift;
	#just takes the floating point number and rounds to 2 decimals. for use in currency math.
	return (int(($number * 100) + 0.5) / 100);
}

sub ch_debug {
	my $self = shift;
	#always pass a var (should be a var ref for dump mode) and a mode
	my $config = $self->param('_config');
	my $session = $self->param('_session');

	if ($config->{suppress_debug_output} || !$self->param('debug_mode')) {
		#die "returning immediately for some reason: '" . $config->{suppress_debug_output} . "','" . $self->param('debug_mode') . "'"; ;
		return;
	}

	my $var = shift;
	my $mode = shift; #either "print" or "dump", assume dump if unspecified
	
	#return immediately if no var passed
	if (!$var) { return 0;  }
	
	#assign default mode if none set
	if (!$mode) { $mode = 'dump';   }
	
	#print header if not already done
	if (!$self->param("CH_DEBUG_HEADER_SENT")) {
		print "Content-type: text/html\n\n";
		$self->param("CH_DEBUG_HEADER_SENT", 1);
	}
	
	if ($mode eq 'dump') {
		if (ref($var) ne 'ARRAY') { $var = [$var] } 
		my $d = Data::Dumper->new([$var]); #not sure why I have to stick it into ANOTHER arrayref to get the output the way I used to have it ... but seems like I do. Whatev! Maybe check out Data::DumperHTML or something like that for more superfoo at a later date.
			#well, it can be useful to separate it out without the extra ones ... but not that useful.
		#why isnt my data dumper object working right? well what version is it?
			#goddam .. something weird was going on. I tried to update to the newest version .. didnt take. I had to manually remove the old version, do the build/install, then restart apache. finally it picks up the new one (in a different location).
			#and to use the Module::Info I had to turn off taint check. not sure why, but it was stopping execution.
#		use Module::Info;
# 		my $mod = Module::Info->new_from_loaded('Data::Dumper');
#		push(@$var, 'Dumper version: ' . $mod->version . ' located in ' . $mod->inc_dir);
		$d->Sortkeys(1);
		print "<pre>" . $d->Dump . "</pre>";
	} else {
		#simpler to print for any mode other than 'dump' .. easy
		print $var;
	}
	
	print "<br><br>\n\n";
	
	return 1;
}

sub dbg_print {
	my $self = shift;
	return undef; #standaloneutil defines this. but dont want to break if other things call it outside of a standalone script.
}

sub debuglog {
	my $self = shift;
	my $var = shift;

	if (ref($var) ne 'ARRAY') { $var = [$var] } 
	my $d = Data::Dumper->new([$var]); #not sure why I have to stick it into ANOTHER arrayref to get the output the way I used to have it ... but seems like I do. Whatev! Maybe check out Data::DumperHTML or something like that for more superfoo at a later date.
	$d->Sortkeys(1);
	#$d->Indent(0);
	$d->Varname('DBG');

	#this override for _vhost_root has to be set as an app param in the instance script because we write to debuglog even before we've read the config file.
	my $dbglog_filename = $self->param('_debuglog_name') ? $self->param('_debuglog_name') : 'debuglog';
	my $dbglog_filepath = $self->param('_vhost_root') . '/' . $dbglog_filename;
	#die "Dieing before trying to write to $dbglog_filename";
	if (!-e $dbglog_filepath || !-w $dbglog_filepath) {
		die "Cannot write to debuglog $dbglog_filepath";
	}
	my $tp = localtime();
	my $tstr = $tp->ymd . ' ' . $tp->hms . ' pid:' . $$;
	open DBG, ">>$dbglog_filepath" or die "Failed to open debuglog file '$dbglog_filename' for writing";
	print DBG	$tstr . ": " . $d->Dump . "\n";
	close DBG;
	
	return 1;
}

#just a shortcut to calling redirect_runmode(undef, undef, { pagename => 'foo.html'});
	#use like: redirect_pagename('foo.html');
sub redirect_pagename {
	my $self = shift;
	my $pagename = shift;
	my $query_params = shift;
	my $other_args = shift;
	
	if (!defined($other_args)) {
		$other_args = {};
	}
	$other_args->{pagename} = $pagename;
	
	$self->redirect_runmode(undef, $query_params, $other_args);
	return undef;
}

#can be used to redirect to a runmode or a pagename ... use only a pagename arg for a pagename ... also added a convenience method just for pagename so you can do return $self->redirect_pagename('foo.html');
	#ssl base redirect: (undef, undef, {https => 1})
	#ssl pagename redirect: (undef, undef, {https => 1, pagename => '/foo.html'})
	#ssl runmode redirect: ('foo_rm', undef, {https => 1})
	#ssl runmode redirect with query params: ('foo_rm', {query_param => value}, {https => 1})
	#regular runmode ('foo_rm', {query_param => value})
	#regular pagename (but you should use redirect_pagename for that): (undef, undef, {pagename => '/foo.html'})
sub redirect_runmode {
	my $self = shift;
	my $runmode = shift;
	my $query_params = shift;
	my $other_args = shift;
	
	#$self->param('can_send_session_cookie' => 0); #experiment, if we're diong a redirect, dont send the cookie.
	
	my $url_str;
	if ($other_args->{https}) {
		my $host = $self->env('http_host');
		#host could have a port num on it, and we'd want to switch the last 3 digits to 443 if it did.
		if ($host =~ /:.*\d{3}$/) {
			$host =~ s|(:.*)\d{3}$|$1 . '443'|e;
		}
		$url_str = 'https://' . $host;
	} else {
		$url_str = $self->param('_script_url_prefix');
	}

	if ($runmode) {
		if ($self->param('_dispatch_redirect_style')) {
			#die "wtf?";
			#now with nicer urls.
			$url_str .= $self->param('_script_name') . '/' . $runmode . '/'; #we'll have to add a ? down below if we are adding query params.
		} else {
			$url_str .= $self->param('_script_name') . "?rm=" . $runmode;
		}
	} elsif ($other_args->{pagename}) {
		$url_str .= $other_args->{pagename};
	} 
	
	if ($query_params) {
		if ($self->param('_dispatch_redirect_style')) {
			$url_str .= '?'; #dispatch style urls with params need the ?mark since they wont have that already.
		}
		foreach (keys(%$query_params)) {
			$url_str .= '&' . $_ . '=' . $query_params->{$_};
		}
	}

	#$self->ch_debug([\%ENV, $self->env(), $self->param('_script_name'), $url_str]); 
	#die "sthe tsop";
	#$self->ch_debug(['the environment', \%ENV, 'and the url so far:', $url_str, 'runmode, queryparams and otherargs:', $runmode, $query_params, $other_args]);
	#die "to stop";
		
	$self->header_add(-location => $url_str);
	#line below does NOT put utf-8 charset into the redirect. I am not sure how to do it. and its a waste of time worrying about it since it only seems to be doing the wrong charset on these redirects not on normal output.
	#$self->header_props(-location => $url_str, -type => 'text/html; charset=utf-8');
	$self->header_type('redirect');
		
#	my $html = qq{
#		<HTML>
#			<HEAD>
#				<TITLE>Application Redirect</TITLE>
#				<meta http-equiv="Refresh" CONTENT="0;URL=$url_str">
#				<meta http-equiv="pragma" content="no-cache">
#				<meta http-equiv="cache-control" content="no-cache">
#				<script type="text/javascript">
#					window.location.href = '$url_str';
#				</script>
#			</HEAD>
#		</HTML>
#	};
#
#	return $html;
	return undef; #gonna try with just headers. I dont think I need the html bit.
}

sub send_nocache_headers {
	my $self = shift;
	
	#prevent IE from caching responses. Hopefully. http://support.microsoft.com/kb/234067
	$self->header_add(-CacheControl => 'no-cache');
	$self->header_add(-Pragma => 'no-cache');
	$self->header_add(-Expires => '-1');
	return 1;
}

sub get_dbh {
	my $self = shift;
	my $args = shift;

	if (!$args) { $args = {}; }

	my $dbh_param = '_dbh';
	if ($args->{db_name}) {
		#non-default db.
		$dbh_param .= '_' . $args->{db_name};
	} else {
		$dbh_param .= '_' . $self->param('_config')->{db_name};
	}
	$args->{dbh_param} = $dbh_param;
	
	if (!$self->param($dbh_param) || $args->{reconnect}) {
		#2010 12 29 I suspect that a realllllly long job lost its db due to some kind of timeout b/c it didnt use db for hours and then bam db went away when it went to do reporting? i dont think so. homie dont play that.
		#also blow away some prepared locks related stuff if we're in here
		$self->param('prepared_db_locks'      => {});
		$self->param('prepared_db_unlocks'    => {});
		$self->param('prepared_db_lockchecks' => {});

		#and yeah caller could just delete the dbh param first but that would be lamer.
		$self->debuglog(["pid $$ connecting to db"]);
		$self->connect_dbh($args);
		
	}
	return $self->param($dbh_param);
}

# connect to the database
sub connect_dbh {
  my $self = shift;
  my $args = shift;
  
  my $db_params = {
		db_name => undef,
		db_host => undef,
		db_user => undef,
		db_pass => undef,
  };
  if ($args->{db_name} && ($args->{db_name} ne $self->config('db_name'))) { 
  	#custom db, go find the db params elsewhere. (assuming the "custom" db is not the one specified in the config file!)
			#update 2008 03 12 - this stuff with having a set db_info_file (the mysql config file lol) is cool and works pretty good - but sometimes (starting today for a education app thing where we need to make queriesto all the edu apps and we just finished going over getting all their db info by reading all their config files, well we want to be able to just tell it the db params to use.
			#so first try to get all the stuff out of args, and if we didnt get all of it, only THEN should we go looking for db_info_file db info extraction stuff.
		my $look_in_db_info_file = 0;
		foreach (keys(%$db_params)) {
			if (!$args->{$_}) {
				$look_in_db_info_file = 1; #didnt get all the things we need directly in args. look to db_info_file.
				last;
			}
			$db_params->{$_} = $args->{$_};
		}

		if ($look_in_db_info_file) {
			$db_params = $self->get_db_params($args->{db_name}, $args->{db_info_file});
		}
  	$self->ch_debug(['connect_dbh: to a non-config file db, using these params:', $db_params]);

  } else {
		#default db, pull from config ...
		my $config = $self->param('_config');
		foreach (keys(%$db_params)) {
			$db_params->{$_} = $config->{$_};
		}
#  	$self->ch_debug(['connect_dbh: to the config file db, using these params:', $db_params]);
  }
  
  my $c_database  = $db_params->{db_name};
  my $c_server    = "DBI:mysql:$c_database:" . $db_params->{db_host};#also contains the port number
  my $c_username  = $db_params->{db_user};
  my $c_password  = $db_params->{db_pass};
  my $dbh         = DBI->connect( $c_server, $c_username, $c_password, {mysql_enable_utf8=>1, serial=>8});
  if (!$dbh) {
  	$self->debuglog(["Failed to connect to db (using serv, user, pass of: $c_server, $c_username, $c_password), DBI error was: $DBI::errstr", 'args were:', $args, 'db params are:', $db_params ]);
  	die "Can not connect to Database - see debuglog for more detail - timestamp: " . localtime();
  }

	#2007-07-10, experiment to support utf across the board, we will run these statements as indicated in the changelog of DBD::mysql in release older than the one we are running. This could change if/when we upgrade DBD::mysql.
 	#I think at this point, anywyas at least with this version of DBD::mysql 3.0006 that I do need them, because with it off I did not keep the utf encoding all the way to the db when I saved a record.
 	#2007-07-11: ok the lines below were doing something useful with DBD::mysql 3.0006 but I think I dont need them with the upgraded DBD::mysql v4.005 and the mysql_enable_utf8 connect param. Values are making their way to the db un-mangled.
 	#$dbh->do("set character set utf8");
  #$dbh->do("set names utf8");

  $self->param( $args->{dbh_param} => $dbh );
}


sub _get_db_lock {
	my $self = shift;
	my $args = shift;
	
	## JUST A NOTE TO SELF: You cannot nest calls to this. Any time GET_LOCK is called with the dbh 
	
	my $name = $args->{name};
	if (!$name) { die "need a name to establish for the lock"; }
	my $timeout = $args->{timeout};
	if (!$timeout) { $timeout = 60; }
	
	my $prepped_locks = $self->param('prepared_db_locks');
	if (!$prepped_locks) { 
		$prepped_locks = {};
		$self->param('prepared_db_locks' => $prepped_locks);
	}
	my $prepared_lock = $prepped_locks->{$name};
	if (!$prepared_lock) {
		#$self->debuglog(["preparing db lock named $name for the first and only time in pid $$"]);
		$prepared_lock = $self->get_dbh()->prepare('SELECT GET_LOCK(?,?)');
		$prepped_locks->{$name} = $prepared_lock;
	}
	#my $lock = $self->get_dbh()->selectrow_arrayref("", undef, ($name,$timeout))->[0]; #if the operation takes more than 5 sec (or more than 0 sec really) its fucked.
	$prepared_lock->execute($name,$timeout);
	my $lock = $prepared_lock->fetchrow_arrayref()->[0];
	
	if (!$lock) { die "NO DATABASE LOCK (TIMEOUT ???)"; }
	return $lock;
}

sub _check_db_lock {
	my $self = shift;
	my $args = shift;
	
	my $name = $args->{name};
	if (!$name) { die "need a name to establish for the lock"; }
	my $timeout = $args->{timeout};
	if (!$timeout) { $timeout = 60; }
	
	my $prepped_checks = $self->param('prepared_db_lockchecks');
	if (!$prepped_checks) { 
		$prepped_checks = {};
		$self->param('prepared_db_lockchecks' => $prepped_checks);
	}
	my $prepared_check = $prepped_checks->{$name};
	if (!$prepared_check) {
		#$self->debuglog(["preparing db lock check named $name for the first and only time in pid $$"]);
		$prepared_check = $self->get_dbh()->prepare('SELECT IS_USED_LOCK(?)');
		$prepped_checks->{$name} = $prepared_check;
	}
	#my $lock = $self->get_dbh()->selectrow_arrayref("", undef, ($name,$timeout))->[0]; #if the operation takes more than 5 sec (or more than 0 sec really) its fucked.
	$prepared_check->execute($name);
	my $check = $prepared_check->fetchrow_arrayref()->[0];
	
	return $check; #should be undef if there was no lock with that name.
}

sub _release_db_lock {
	my $self = shift;
	my $args = shift;
	
	my $name = $args->{name};
	if (!$name) { die "need a name to establish for the lock"; }

	my $prepped_unlocks = $self->param('prepared_db_unlocks');
	if (!$prepped_unlocks) { 
		$prepped_unlocks = {};
		$self->param('prepared_db_unlocks' => $prepped_unlocks);
	}
	my $prepared_unlock = $prepped_unlocks->{$name};
	if (!$prepared_unlock) {
		#$self->debuglog(["preparing db Unlock named $name for the first and only time in pid $$"]);
		$prepared_unlock = $self->get_dbh()->prepare('SELECT RELEASE_LOCK(?)');
		$prepped_unlocks->{$name} = $prepared_unlock;
	}
	#my $lock = $self->get_dbh()->selectrow_arrayref("", undef, ($name,$timeout))->[0]; #if the operation takes more than 5 sec (or more than 0 sec really) its fucked.
	$prepared_unlock->execute($name);
	my $unlock = $prepared_unlock->fetchrow_arrayref()->[0];

	#my $unlock = $self->get_dbh()->selectrow_arrayref("SELECT RELEASE_LOCK(?)", undef, ($name))->[0]; #if the operation takes more than 5 sec (or more than 0 sec really) its fucked.
	if (!defined($unlock)) { die "wtf no lock with that name at all?"; }
	if (!$unlock)          { die "wtf lock not established by us??"; }
	return $unlock;
}

sub get_new_dataobj {
	my $self = shift;
	my $form_name = shift;
	my $record_id = shift;
	my $args = shift;
	
	$args->{form_name} = $form_name;
	$args->{record_id} = $record_id;
	
	#pick up db settings if any -- otherwise it will just use the default db, whatever is obtained via config('db_name');
	if (!$args->{formcontrol_db} && $self->param('_formcontrol_db')) {
		$args->{formcontrol_db} = $self->param('_formcontrol_db');
	} 
	if (!$args->{data_db} && $self->param('_data_db')) {
		$args->{data_db} = $self->param('_data_db');
	} 
	$self->ch_debug(['get_new_dataobj: creating new dataobj with args like:', $args]);
	#I'd _LIKE_ to be able to hand back the right kind of data object based on the form name. Not sure how that'll work. For now I'm just going to set the form name into the dataobj.
	
	#not even sure if this will end up being useful ... who will want a generic data object? Well maybe if it will just become something else.
	
	return SpApp::DataObj->new($self, $args);
}

sub get_db_params {
	my $self = shift;
	#any more args and change it to hashref.
	my $db_name = shift;
	my $db_info_file = shift; 

	$self->debuglog(["get_db_params: pid $$ passed arg and config for db_info_file:", $db_info_file, $self->config('db_info_file') ]);
	
	#get one or all of the db params by reading from the file. if we did it already, we can refer to data we already set.
	if ($self->config('no_cache_db_info')) {
		$_DB_PARAMS = undef; #caching disabled, will rebuild each time.
	}

	if (!$_DB_PARAMS) { $_DB_PARAMS = {};	}
	
	if (!$_DB_PARAMS->{$db_name}) {
		$self->debuglog("get_db_params: pid $$ reading from the filesystem, parsing the file");
		#go get em.
			#the line below should probably take into account dev vs prod ... somehow. uhhhm yeah "somehow" should be covered by %ENV chief.
				#except that it wont accommodate apps running domains that dont have a mysql/config.inc.php which should be ok for now since only the formtool app should be needing this right now, but if ever that is changed then we'll need to code for a way to specify where to suck the info from or something. maybe config->{db_params_vhost} or something.
#		my $db_info_file = '/home/httpd/vhosts/appdev.spiserver3.com/httpdocs/mysql/config.inc.php';

		#if we were explicity passed in the path to the db_info_file, we will use that, otherwise we will try to figure it out (from config option, or from relative paths)
			#20071001 fixed idiot logic error from being stupid retardation problem.
		if (!$db_info_file) {
			if ($self->config('db_info_file')) {
				#for now must be the complete path to the file. in future could do something for just knowing the vhost name and then finding it based on standardized paths. whatever.
				$db_info_file = $self->config('db_info_file');
			} else {
				$db_info_file = $self->param('_vhost_root') . '/httpdocs/mysql/config.inc.php';
			}
		}
		if (!$db_info_file) { die "get_db_params: dont have a path to read from."; }
		if (!-e $db_info_file || !-r $db_info_file) { die "get_db_params: path $db_info_file either does not exist or is unreadable."; }
		$self->debuglog("get_db_params: pid $$ reading from file path: $db_info_file");
		open INFILE, "<$db_info_file";
		my $found_block = 0;
		while (<INFILE>) {
			if ($_ =~ m|//APP_DB_PARAMS_BEGIN|) { $found_block = 1;	} #found the start ... flag it.
			if ($found_block && $_ =~ m|//APP_DB_PARAMS_END|) { last;	} #found the end, stop looking
			if ($found_block && $_ =~ m|^\s*//|) { next; } #skip commented-out lines. well at least of the // (at the beginning of the line) variety. /* foo */ would be ... umm stupidly complex.
			if ($found_block && $_ =~ /'user'\s*=>\s*'(.*?)'\s*,\s*'password'\s*=>\s*'(.*?)'/) { #process the block items.
				my ($db_name, $db_pass, $db_host, $db_port) = ($1, $2, 'localhost', '3306');

				#check for port and hostname override ... new 2007-07-30
					#note, there is some queerness where using "localhost" as the name will force it to the mysql4 db, regardless of the port being used. I dont quite understand why that is, it was explained (by RS and RP) as some automatic mysql thing, or that it uses the default socket file and not tcp when it sees localhost or something. either way, have to use 127.0.0.1 to FORCE it to use tcp ... so I have to do this to talk to the mysql5 db.
				if ($_ =~ /'port'\s*=>\s*'(.*?)'/)     { $db_port = $1;	}
				if ($_ =~ /'hostname'\s*=>\s*'(.*?)'/) { $db_host = $1;	}

				$_DB_PARAMS->{$db_name} = {
					db_name => $db_name,
					db_user => $db_name,
					db_pass => $db_pass,
					db_host => "$db_host:$db_port",
				};
				$self->debuglog("get_db_params: pid $$ found info for db like $db_name, $db_pass, $db_port");
			}
		}
		close INFILE;
		
		##also, be sure to include the information from the config file about db's .... it would override anything in the phpmyadmin config.inc.php file.
			#this way we can ask for the db named in the config file explicitly.
		my $config = $self->param('_config');
		if ($config->{db_name}) {
			$_DB_PARAMS->{$config->{db_name}} = {
				db_name => $config->{db_name},
				db_user => $config->{db_user},
				db_pass => $config->{db_pass},
				db_host => $config->{db_host},
			};
		}
		
	} else {
		$self->debuglog("get_db_params: pid $$ using already-stored information.");
	}
	
	if ($db_name) {
		return $_DB_PARAMS->{$db_name};
	} else {
		return $_DB_PARAMS;
	}
}

sub get_auth {
	my $self = shift;
	#if ($self->param('_auth_obj')) {
	#	$self->ch_debug('get_auth: sending back existing auth_obj');
	#	return $self->param('_auth_obj');
	#} else {
		$self->ch_debug('get_auth: sending back new auth_obj');
		my $auth = SpApp::Auth->new($self);
	####Somehow, and I have no fucking clue, the line below COMPLETELY DESTROYS THE session so that it doesnt even get written to disk. I dont get it.
		#though the fact that the obj uses the db maybe has something to do with it?
	#	$self->param('_auth_obj' => $auth);
		return $auth;
	#}
}


#what I should expect to have in userinfo:
	#logged_in (status boolean)
	#id (id of user in whatever user table is set up for _auth_params)
	#userlevel (integer, would come from user table as defined in _auth_params)
	#any other fields from the user table as defined in _auth_params listed in the the 'sessionize' arrayref.
sub get_userinfo {
	my $self = shift;
	my $userinfo_param = '_userinfo_' . $self->param('_app_id');
	my $userinfo = $self->session()->param($userinfo_param);
	#$self->debuglog(['get_userinfo: pulled this from that session param', $userinfo, $userinfo_param ]); #turned out to be an app_id problem. mp hanlder was not including the port in the app_id. so userinfo was not being recovered from where it was saved by the registry script.
	return ($userinfo ? $userinfo : {});
}

sub get_strings {
	my $self = shift;
	my $stringnames = shift; #should be arrayref of string names.
	my $args = shift;

	#language pickup. could override lang to use by passing one in. otherwise will use whatever is set as self->param('lang'), if any.
		#also if it doesnt figure out a language here it will use 'en' in the SpApp::Strings code.
	if (ref($args) ne 'HASH') { $args = {}; } #ensure args is a hashref. (if it isnt one make it one)
	if (!$args->{lang}) {
		#if no lang arg is specified attempt to set as self param 'lang'. --- which might not have a value anyway. strings code defaults to en if nothing is passed.
		$args->{lang} = $self->param('lang');
	}
	
	my $strings_obj = SpApp::Strings->new($self);
	return $strings_obj->get_strings($stringnames, $args);
}

### Auth related standard runmode code ###
sub show_login {
	my $self = shift;
	my $tmpl_params = shift;
	my $args = shift; #20070119 I want to be able to override the template used. 

	my $cgi = $self->query();
	if ($cgi->param('bad_login')) {
		$tmpl_params->{bad_login} = 1;
	}
	
	if (!$tmpl_params) { 
		$tmpl_params = {};
	}
	#not a regular interface tmpl -- a full html document in one tmpl for the login screen.
	$self->ch_debug(['show_login with tmpl params like:', $tmpl_params, 'and args like', $args ]);

	my $tmpl = 'general/login.tmpl';
	if ($args->{tmpl}) { $tmpl = $args->{tmpl}; }
	my 	$t = $self->load_tmpl($tmpl);
	$t->param($tmpl_params);
	return $t->output();
}

sub process_login {
	my $self = shift;
	
	#basic_auth should send us to the right place automatically. if good login, should be a redirect to the good login mode. if a bad login will probably skip redirect and just feed the login page with errors flagged.
	my $auth = $self->get_auth();
	my $result = $auth->basic_auth();
	
	return $result; #s.b. a redirect.
}

sub logout {
	my $self = shift;

	my $auth   = $self->get_auth();
	my $result = $auth->logout_redirect();
	return $result; #s.b. a redirect.

}
### End of Auth related standard runmode code ###

sub cgiapp_postrun {
	my $self = shift;

#	die "yes here in postrun";
#	if ($self->param('can_send_session_cookie') && !$self->session()->param('session_cookie_sent')) {
#		$self->debuglog(['cgiapp_postrun: and we believe we should send the cookie, will be for session id: ', $self->session()->id()]);
#		$self->session_cookie();
#		$self->session()->param('session_cookie_sent' => 1);
#	}
}

sub teardown {
	my $self = shift;

	$self->send_nocache_headers(); #want to see what are the ramifications of doing this all the time. The particular problem to solve right now by doing this is that the signup_form in IE is being cached sometimes (or maybe only when passing through the cookie verification stuff). either way its unacceptable b/c the form is showing up without the email address but if you ctrl-f5 it shows up right.
	$self->session()->flush();
	#print STDERR "\n\n\n"; #separate log info from the next request with a few blank lines.
}

#### general purpose utility funcs ######
sub random_string {
	#this func, and its incredibly interesting syntax, lifted from http://www.codeproject.com/useritems/perl_randomstring.asp
	       #damn its neato, elegent and concise. That syntax with the join and map is .... b-b-b-badass.
	       #i changed some var names to be more generic.
	my $self = shift;
	my $args = shift; #hashref ... key 'len' is REQUIRED.
	my $stringsize = $args->{len};
	my @chars;
	if (!$args->{len}) { die "data_obj->random_string: missing 'len' argument."; }
	if (!$args->{charset}) {
		$args->{charset} = 'standard';
	}
	if ($args->{charset} eq 'standard') {
		@chars = ('a'..'z', 'A'..'Z', 0..9);
	} elsif ($args->{charset} eq 'licenseplate') {
		@chars = ('A'..'Z', 1..9);
	} elsif ($args->{charset} eq 'numbers') {
		@chars = (1..9);
	} else {
		die "spapp::core->random_string: invalid 'charset' argument."; 
	}
	my $randstring = join '', map $chars[rand @chars], 1..$stringsize;
	
	return $randstring;
}

sub cgi_params_hashref {
	my $self = shift;
	my $cgi = $self->query();
	my @allparams = $cgi->param();
	my $params = {};
	foreach (@allparams) {
		$params->{$_} = $cgi->param($_);
	}
	return $params;
}

#simple call: figures out user_id and user_table from the self->get_userinfo, but it wont work if there is no user logged in.
	#$self->log('actiontext', 'detailtext'); #detailtext not required.

#complex call: 
	#$self->log('actiontext', 'detailtext', { userinfo => { id => 234} }) #figures out user_table from the self->get_userinfo, but lets you tell it the user_id. can be used to log something about a user when not actually logged in.
	
#unsupported usage:
	#when there is not enough information to know the user_table AND user_id somehow. This would fall out of the scope of this logging function, and would neccessitate the creation of a more general, call it, system log, or something. this app_log stuff is to log interactions of users we know something about.
sub log {
	my $self = shift;
	my $action = shift;
	my $detail = shift;
	my $other_args = shift;

	my $userinfo;
	if (!$other_args) { $other_args = {}; }
	if ($other_args->{userinfo}) {
		$userinfo = $other_args->{userinfo};
	} else {
		$userinfo = $self->get_userinfo();
	}

	#dont be a fucking tool and fail just because we didnt get a userid.
	#if (!$userinfo->{id}) { return 0; } #can't do anything without userinfo. might not have it if somehow we are trying to log in a public mode -- mainly this will happen for logout as we'd like to keep logout as a public mode but once its been hit once by a logged in user, they will not have userinfo.
	my $user_id = $userinfo->{id};
	if (!$user_id) { $user_id = $other_args->{user_id}; } #can maybe be given one.
	if (!$user_id) { $user_id = '[System]'; } #or can just make one up if we still dont have one. if its not a logged in user its probably a system thing.
	
	#my $log_dobj = $self->get_new_dataobj('APP_LOG');
	my $log_dobj = SpApp::DataObjects::AppLog->new($self);
	$log_dobj->new_record_for_edit->set_values({
		app_name => $self->param('_app_name'),
		user_table => $self->_auth_params()->{table},
		user_id    => $user_id,
		action     => $action,
		detail     => $detail,
	})->save_edited_record();

	$self->ch_debug(["SpApp::Core->log() -- logging  $action action."]);
	return 1;
}

sub send_email {
	my $self = shift;
	my $message_params = shift;

	#2009 04 30 dont try to determine mail master template name in here. this func is now just a pure shortcut to send_basic_html_email.
		#2009 04 30 this is because we have changed how we pass some args to _mail_master_template, (it seemed to never be used before and I want to implement a little cleaner now that its time to do something like this for amifx case vs lead master tmpl decision. we will pass master_tmpl_args hashref in the message_params if there is something to send to _mail_master_tmpl.
	#my $master_tmpl_name = $self->_mail_master_template($message_params); #pass args along, maybe something the _mail_master_template needs to key/trigger/fap on.
	#$message_params->{master_template} = $master_tmpl_name;
	$self->send_basic_html_email($message_params);
}

sub send_basic_html_email {
	my $self = shift;
	my $message_params = shift;

	#NEEDED:
	#recipient_email
	#subject
	#master_template (name of master template file -- should be added by a module's Core send_email function, or can just be auto-obtained from a defined _mail_master_template sub)
	#message_template (name of sub template file)
	#template_params (hashref of template params)

	#OPTIONAL:
	#recipient_name
	#attachments
	
	my $master_template = $message_params->{master_template};
	my $message_template = $message_params->{message_template};
	if (!$master_template) { 
		$master_template = $self->_mail_master_template($message_params->{master_tmpl_args}); 
	} #can try to get it from a function which, if we are trying to call it, must be defined in the subclass (calling the baseclass version will cause us to die with a reminder about defining it in the subclass!)

	my $template_params = $message_params->{template_params};

	#check to make sure there is a real email address provided before proceeding (with qmail we wouldnt care, but with sendmail having a bad email address gives errors.)
	my $email_provided = 0;
	if ($message_params->{recipient_email} && $message_params->{recipient_email} =~ /^[\w.-]+\@([\w-]+\.)+\w+$/) {
		$email_provided = 1;
	}
		
	if (!$email_provided) { 
		$self->ch_debug(['send_basic_html_email error no(/invalid?) email address with msg params like:', $message_params]);
		die "Error: attempt to send mail with no email address.";
	}

	#print STDERR "\ngot an email addr, doing the mailout";
	my $config = $self->param('_config');

	#the activation email we are sending will welcome the new user to the system and include the activation code inside a link to the account activation mode. (see notes inside there for more info)
	#2007 02 02 - I _never_ want to see an email that doesnt have a mail_return_address so die if its not been set up.
	if (!$config->{mail_return_address}) {
		$self->ch_debug(['send_basic_html_email: i think I dont have a mail_return_address, do I?', $config]);
		die "Not allowed to send email without a mail_return_address in the config.";
	}
	
	#the recipient specific information for the message template
	my $sender_email = $message_params->{sender_email} ? $message_params->{sender_email} : $config->{mail_return_address};
	my $sender_name  = $message_params->{sender_name}  ? $message_params->{sender_name}  : $config->{mail_return_name};
	my $sender_formatted = undef;
	if ($sender_name) {
		$sender_formatted = '"' . $sender_name . '" <' . $sender_email . '>',
	} else {
		$sender_formatted = $sender_email;
	}

	my $mail_subject = $message_params->{subject};

	my $recipient_formatted = undef;
	if ($message_params->{recipient_name}) {
		#btw this format for the recip and sender is just ripped from how it is represented in headers in Thunderbird. I have read no RFC. Seems to worky. Better than what was there before.
		$recipient_formatted = '"' . $message_params->{recipient_name} . '" <' . $message_params->{recipient_email} . '>',
	} else {
		$recipient_formatted = $message_params->{recipient_email};
	}
	
	my ($host_name, $mail_img_dir)     = ($self->_mail_host(), $self->_mail_img_dir());
	$template_params->{'HOST_NAME'}    = $host_name; #not so useful anyway.
	$template_params->{'MAIL_IMG_DIR'} = $mail_img_dir; #more useful. Should _always_ start with http:// (or https://) for mail.

	$template_params->{'message_title'} = $message_params->{subject}; #just what we want in the title tag (not even really used for an html email).

	#templaterinos.
	my $master_t = $self->load_tmpl($master_template);
	my $sub_t    = $self->load_tmpl($message_template);
	
	$master_t->param($template_params);
	$sub_t->param($template_params);
	my $f = HTML::FormatText::WithLinks->new(); #experiment with including text only contents. this module should be able to do it! see its page on cpan for more options. just playing with default for now.
	my $sub_t_output          = $sub_t->output();
	my $sub_t_output_textonly = $f->parse($sub_t_output);
	$master_t->param('sub_tmpl'          => $sub_t_output);
	$master_t->param('sub_tmpl_textonly' => $sub_t_output_textonly);
#	$master_t->param(simple_preview => 1);
	
#		$self->ch_debug(['textonly content: ', $sub_t_output_textonly]);
#		die "stop before sending the email";
	
	my $msg = MIME::Lite->new();

	my $message_contents = $master_t->output();
		
	#doing attachments?
	my $attachments = $message_params->{attachments}; #array of hashrefs, with keys (type, data, [filename])
	if ($attachments && ref($attachments) eq 'ARRAY') {
		#message with main contents and attachments as attachments.
		#die "no attachments yet! make sure old stuff still works right!";
		$msg->build(
			Type    => 'multipart/mixed',
		);
		$msg->attach(
			Type     => 'text/html; charset=utf-8',
			#Type     =>'TEXT/HTML',
			Data     => $message_contents,
		);		
		foreach (@$attachments) {
			$msg->attach(
				Type     => $_->{type},
				Data     => $_->{data},
				Filename => $_->{filename},
			);		
		}
	} else {
		#plain jane simple message.
		$msg->build(
			Type     => 'text/html; charset=utf-8',
			#Type     =>'TEXT/HTML',
			Data     => $message_contents,
		);
	}

	$msg->replace('X-Mailer' => $self->param( '_app_label'));
	#setting it as 'text/html; charset=utf-8' across the board is not right, messing up our attachments (s.b multipart/mixed for those)
	#$msg->add('Content-Type' => 'text/html; charset=utf-8');
	$msg->add("Return-Path"  => $sender_email );
	$msg->add("Errors-To"	   => $sender_email );
	$msg->add("X-Errors-To"	 => $sender_email );
	$msg->add('From'	       => $sender_formatted);
	$msg->add('To'		       => $recipient_formatted); #ex: $attendee_display_values->{email} . " ($attendee_name)"
	$msg->add('Bcc'          => 'all_apps_mail_copies@chws.ca');
	$msg->add('Subject'	     => $mail_subject);
	
	$self->ch_debug(['send_basic_html_email: sending an email to:', $recipient_formatted, 'from', $sender_formatted, 'subject:', $mail_subject ]);
	$self->dbg_print(['send_basic_html_email: sending an email to:', $recipient_formatted, 'from', $sender_formatted, 'subject:', $mail_subject ]);
	
	my $smtp_mode = $self->config('smtp_mail');
	if ($smtp_mode) {
		
		if ($self->config('smtp_tls')) {
		
			#having a weird mail problem with headers repeating at the bottom in place of the closing content. really weird. maybe a content-length related issue?
			
			my $smtp = Net::SMTP::TLS->new(
				$self->config('smtp_host'),
				Hello    => $self->config('smtp_host'),
				Port     => 25, #redundant. yes. i agree.
				User     => $self->config('smtp_username'),
				Password => $self->config('smtp_password'),
				Timeout  => 20, #20 seconds is plenty long to timeout by.
			);
	#		$self->ch_debug([\%ENV]);
	
	    $smtp->mail($self->config('smtp_username'));
	    $smtp->to($message_params->{recipient_email});
			
			$smtp->data();
	
			$msg->add('Content-Transfer-Encoding' => '7bit');
			my $headers = $msg->header_as_string();
	#		$$msg->delete('Content-Length'); #trying to find out what is causing the weird SMTP issue.
			#tried to delete the Content-Length header. no luck. processing manually to see if that is the source of the smtp content fuckup.
			$headers =~ s|Content-Length:\s.*?\n||s;
			$smtp->datasend($headers);
	#		$self->debuglog(['including in the headers of an email some lines like:', $headers]);
			
			###hack to attempt to fix content issue ... send data line by line.
				#seemed to do the trick. looked like line endings were fucking it up somehow. dont know. dont care. now it works.
				#might have to deal with line length > 1000 chars in future.
	#		my $msg_body = $msg->body_as_string();
	#		my @body_lines = split("\n", $msg_body);
	#		$smtp->datasend("\n");
	#		$self->debuglog(['including in the body of an email some this many lines of text/html:', scalar(@body_lines)]);
	#		my $max_line_length = 988;
	#		foreach(@body_lines) {
	#			#due to known issues with mail, its inadvisable for lines to be too long. so split em if needed.
	#			my @line_broken = ($_);
	#			if (length($_) > $max_line_length) {
	#				$Text::Wrap::columns = $max_line_length;
	#				#my @broken_up = split(/.{50}/, $stupidly_long);
	#				@line_broken = split(/\n/, Text::Wrap::wrap('', '', $_));
	#			}
	#			foreach (@line_broken) {
	#				$smtp->datasend($_ . "\n");
	#			}
	#		}
	
			my $msg_body = $msg->body_as_string();
			my $max_line_length = 988;
			$Text::Wrap::columns = $max_line_length;
			my @body_lines = split(/\n/, Text::Wrap::wrap('', '', $msg_body));
	
			$smtp->datasend("\n");
			$self->debuglog(['including in the body of an email some this many lines of text/html:', scalar(@body_lines)]);
			foreach(@body_lines) {
				$smtp->datasend($_ . "\n");
			}		
			
			$smtp->dataend(); #not really sure what the deal is with this SMTP content overlap bug, but adding more content seems to do something good for it.
			$smtp->quit();
			
			#end of TLS version of smtp code.
		} else {
			#reg SMTP attempt.
			my $smtp_port = $self->config('smtp_port');
			if (!$smtp_port) { $smtp_port = 25; }

			my $smtp = Net::SMTP->new(
				$self->config('smtp_host'),
				Hello    => $self->config('smtp_host'),
				Port     => $smtp_port, #redundant. yes. i agree.
				Timeout  => 20, #20 seconds is plenty long to timeout by.
				#Debug => 1,
			);
			#the auth call below wasnt working for me at first. turns out its because Net::SMTP wont even try any auth method if Authen::SASL is missing from the system. took an hour and a half to figure out that this missing module is why it wouldnt auth to send to non chws.ca domains. it didnt report any error. ripped the code apart tho and debugged to find the fail point. lame lol.
			$smtp->auth($self->config('smtp_username'), $self->config('smtp_password'));
	    $smtp->mail($self->config('smtp_username'));
	    $smtp->to($message_params->{recipient_email});
			my $result = $smtp->data($msg->as_string());
			if (!$result) { die "failed to send email data to $message_params->{recipient_email}"; }
			$smtp->quit();
		
		}

		#die "just after trying to send via smtp!";
	} else {
		#yeah ok so i just seen "can't fork" error when trying to use this, and also we are sometimes definitely getting duplicate mailings. its weird. going to go back to the old tried tested and true method. we really DONT need to fork to send a fecking single message. now if we were sending a thousand of them, that might be different.
		#$msg->send("sendmail"); #trying this out the official MIME::Lite way.
		
		# get the content of the mime
		my $mime	= $msg->as_string();
		
		###maybe should try the builtin sendmail method of MIME::Lite since this looks icky.
			#tried it, kinda worked, kinda had weird bugs with forking and duplicating messages. so fuck it!
		#send the message on its merry way. #the old fashioned way.
		#send 10 copies of it to see the volume go up and wonder why none are being delivered.
		#foreach (1..10) {
			#$self->debuglog(["sending email from $sender_formatted to $recipient_formatted"]);
			open (SENDMAIL, '| /usr/sbin/sendmail -t -i');
 			binmode SENDMAIL, ":utf8"; #stop a "wide character in print" warning ... thx to http://ahinea.com/en/tech/perl-unicode-struggle.html
			print SENDMAIL $mime;
			close(SENDMAIL);
		#}

		#experimental 2007 06 14 - fucking sick of ppl saying they didnt get the email. send me a copy of everything.
			#try with bcc for hopeful speed betterness.
		#$msg->replace('To'      => 'all_apps_mail_copies@chtest.spiserver3.com'); #ex: $attendee_display_values->{email} . " ($attendee_name)"
		#$msg->replace('Subject'	=> "Copy of '$mail_subject' email");
	
		#die "stopped after sending a mail via sendmail."; #was having weird issues. turned out that all memory was eaten and so couldnt spawn sendmail or fucking much else either.
	}
}

#simple_mail_preview will only work if the subclass defines a _mail_master_template function.
	#got this going for CMCReg, also did concept of sub _mail_master_template for it too.
sub simple_mail_preview {
	my $self = shift;
	my $master_template = $self->_mail_master_template(); #can try to get it from a function which, if we are trying to call it, must be defined in the subclass (calling the baseclass version will cause us to die with a reminder about defining it in the subclass!)
	my $master_t = $self->load_tmpl($master_template);	

	my ($host_name, $mail_img_dir) = ($self->_mail_host(), $self->_mail_img_dir());
	$master_t->param('HOST_NAME'    => $host_name); #not so useful anyway.
	$master_t->param('MAIL_IMG_DIR' => $mail_img_dir); #more useful. Should _always_ start with http:// (or https://) for mail.
	$master_t->param('message_title' => 'Simple Mail Preview'); #for real, message_title is sourced from the subject.
	$master_t->param(simple_preview => 1);

	my $message_contents = $master_t->output();
	return $message_contents;
}

sub _mail_master_template {
	#subclass should define this. if it is ever called here, bail. there are ways to not have this be called, but a better thing to do is define it in the subclass!
	die "_mail_master_template:: this function must be specified in the subclass if it is to be used. dieing for being here when not allowed";
}

sub _mail_host {
	my $self = shift;
	if ($self->config('mail_resources_host')) {
		return $self->config('mail_resources_host');
	} else {
		return $self->env('http_host');
	}
}

sub _mail_img_dir {
	my $self = shift;
	if ($self->config('mail_img_dir')) {
		return $self->config('mail_img_dir');
	} else {
		return ('http://' . $self->env('http_host') . '/images/');
	}
}

sub _split_keywords {
	my $self = shift;
	my $args = shift;

	#this code is working pretty well. exapmle of a really stupid query and what we'd give back:
	#input -> '   gas "peak oil" gold,      "plys "some really " dumb, shit    '
  #output -> ['gas', 'peak oil', 'gold', 'plys ', 'some', 'really']; #note it bailed after 'really' since with the inclomplete rmaining quote none of what is left matched properly. i think thats ok. users do mismatched quotes, expect gay results or in this case it just giving up after parsing stuff that was intelligible.

	my $kw = $args->{kw};
	if (!$kw || $kw =~ /^\s+$/) {
		return []; #undef, empty, or only whitespace, send back empty.
	}
	#my $kw_split = [ split(/\s+/, $kw) ];

	my $kw_split = [];
	my $matching = 1;
	my $kw_temp = $kw;

	#strip stuff that will definltey screw us up (like commas, or really anything that if it appeared at the beginning of the attempted match would cause it it to fall out of the loop while still possibly having legit stuff to parse)
	$kw_temp =~ s|,||g;

	while ($matching) {
		$kw_temp =~ s|^\s+||; #strip space from front
		#$self->ch_debug(['kw_temp before current attempted match: ', $kw_temp ]);

		my $curr_kw = undef;
		if ( $kw_temp =~ s|^\"(.*?)\"|| ) {
			#extract quoted phrase from beginning of what is left of the kw_temp
			$curr_kw = $1;
			#$self->ch_debug(['fail 1a:', $1 ]);
		#} elsif ( $kw_temp =~ s|(^\w+)|| ) {
		} elsif ( $kw_temp =~ s|(^\S+)|| ) { #this seems to work better. previous totally broke when user searched for a url like http://anything
			#extract single kw from beginning of what is left of the kw_temp
			$curr_kw = $1;
			#$self->ch_debug(['fail 1b:', $1 ]);
		}
		#$self->ch_debug(['kw_temp and curr_kw after current attempted match:', $kw_temp, $curr_kw ]);
		
		if ($curr_kw) {
			push (@$kw_split, $curr_kw);
		} else {
			$matching = 0; #didnt pull out a kw, we are done.
		}
	}
	#my $kw_temp = $kw;
	#my @phrases = 
	#while ($kw_temp =~ 

	#$self->ch_debug(['accepted this kw arg and broke into these keywords:', $kw, $kw_split ]);
	#die "stopped with keywords";

	return $kw_split;
}

1;
