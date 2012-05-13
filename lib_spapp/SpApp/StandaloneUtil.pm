package SpApp::StandaloneUtil;
use base 'SpApp::Core';
use strict;

use SpApp::DataObj;
use SpApp::DataObj::SupportObj;
use SpApp::DataObj::SupportObj::EditMode;
use SpApp::DataObj::SupportObj::EditModeInternals;
use SpApp::DataObj::SupportObj::FieldProcessing;
use SpApp::DataObj::SupportObj::Listoptions;
use SpApp::DataObj::SupportObj::SearchMode;
use SpApp::DataObj::SupportObj::SQLAbstraction;
use HTML::Template::Compiled;
use HTML::FormatText::WithLinks;
use MIME::Lite;
use DBI;
use JSON::Syck;
use Clone;

$| = 1;

#the point of this is to let a webapp-like object run on the command line and be able to have cgiapp lifecycle kind of things, and also to be able to set up its environment such that is can find its configuration info
#i want it to do things like pick up the runmode from command line args, etc.

sub cgiapp_get_query {
    my $self = shift;
    return SpApp::StandloneQuery->new();
}

sub cgiapp_init {
	my $self = shift;

	$self->_init_environment({standalone => 1}); #now hoping to be able to set up and work in a mp handler or as a standalone registry dealo. ... yikes or not. But abstract env info is good anyway.
	
	#figure out where we live in the server filesystem.
	
	#lets say we're here to do a job for an app, so we should inherit our environment with relation to our config file, because presumably we have a config file that runs along side or is the same as the one the webapp uses. god help us if its a config file shared by multiple hosts, then which host are we? meh.
	my $config_path = $self->query()->param('config');
	if (!$config_path) { $config_path = $self->param('config_path') };
	#print "here with '$config_path'";
	my $vhost_root = $config_path;
	$vhost_root =~ s|(.*)/(.*)|$1|; #strip off the /foo.conf ... (then we do the same thing to strip that next dir off next heh)
	
	#also, grab that foo.conf and set it as the _conf_name, so it gets used as the config file to use.
		#but the way that works in read_config, the .conf part of the filename will be appended so we must strip it here.
	my $conf_name = $2;
	$conf_name =~ s|\.conf$||;
	$self->param('_conf_name' => $conf_name);

	#finalize the vhost_root now
	$vhost_root =~ s|(.*)/.*|$1|; #strip last dir off (drop the 'conf' dir from the path) to get siteroot dir

	#and figure out what is the script file and the protocol we're using.
	#my $script_name = $ENV{REDIRECT_URL} ? $ENV{REDIRECT_URL} : $ENV{SCRIPT_NAME}; #if the script name part of the url is rewritten by mod_rewrite, make use of that name.
	#not sure why i wanted to use the above. can tell you its screwing up redirect_runmode with rewrite rules that already specify a runmode for html files. meaning that I can't then use a real runmode if that is the script that gets redirected to.
	my $script_name = $self->env('script_name'); 
	#my $web_prot = ($ENV{SERVER_PORT} eq '443') ? 'https://' : 'http://'; #decide whether we are using http or https ... hint, if the doc root is httpsdocs and we got here on port 443, we're doing https.
	my $web_prot = ($self->env('https') eq 'on') ? 'https://' : 'http://'; #decide whether we are using http or https ... hint, if the doc root is httpsdocs and we got here on port 443, we're doing https.

	#config independent stuff:
	$self->param('_script_url_prefix', $web_prot . $self->env('http_host')); 
	$self->param('_http_script_url_prefix', 'http://' . $self->env('http_host')); 
	$self->param('_https_script_url_prefix', 'https://' . $self->env('http_host')); 
	$self->param('_script_name', $script_name); 
	$self->param('_vhost_root', $vhost_root);

	my $app_id = $self->param('_app_id');
	$self->debuglog(['cgiapp_init: $app_id is set to:', $app_id]);
	$self->param('_config', $self->read_config()); #would rather the config func refer to a self->param.
	
	#I'd like to support sessions in a command line util, but will need some kind of cookie-like thing, or even just passing the session id in the args. that could work, but I really dont need that stuff right now, so out it goes.
	
#	#config dependent stuff:
#	my $session_dir = $self->config('session_dir'); #if not provided in config file then default 'sessions' will be used.
#	#store the gathered info. yeah, this has to happen for every. single. request.
#	$self->param('_session_path', $vhost_root . '/' . ($session_dir ? $session_dir : 'sessions'));

	$self->param('_app_label', $self->config('app_label'));	
	$self->param('_tmpl_path', $vhost_root . '/tmpl_' . $self->config('tmpldir_suffix'));
	$self->param('_tmpl_cache_path', $vhost_root . '/tmpl_cache_' . $self->config('tmpldir_suffix'));
	
#	$self->setup_session();
#	$self->setup_debugmode();
	return 1;
}

sub cgiapp_prerun {
	my $self = shift;
	my $rm = shift;

	my $std_runmodes = $self->_standard_modes();
	my $app_runmodes = $self->_runmode_map();
	my $orig_rm = $rm;
	
	#entire authorization model code begone.

#	$self->ch_debug(\%ENV);
	#no more having to check if a session var that is supposed to be a hashref actually is a hashref b/c now we can make a list of those and forcibly establish them!
	$self->setup_session_vars(); #### we _could_ set up to treat session params likes self params. 
	
	#hook for running a _spapp_prerun() or something that the subclass could define, as sort of a last chance to change the runmode. (or do other stuff that depends on knowing the final rm)
	my $switch_rm = $self->_spapp_prerun($rm);
	#we expect to often get undef back from _spapp_prerun, so we'll only change the runmode if we get some true value.
	if ($switch_rm) { $rm = $switch_rm;}
	
	if ($rm ne $orig_rm) {
		#$self->debuglog(["cgiapp_prerun: rm changed from originally requested '$orig_rm', to current '$rm'"]);
		#$self->ch_debug(["cgiapp_prerun: rm changed from originally requested '$orig_rm', to current '$rm'"]);
		$self->prerun_mode($rm);
#	} else {
#		$self->debuglog(["cgiapp_prerun: authorized for '$rm', proceeding with that"]);
#		$self->ch_debug(["cgiapp_prerun: authorized for '$rm', proceeding with that"]);
	}

}

#overriding CA's run function mainly so it doesnt try to send http headers
	#the code is all from CA, just with a bit removed/commented out.
sub run {
	my $self = shift;
	my $args = shift;
	
	my $q = $self->query();

	my $rm_param = $self->mode_param() || croak("No rm_param() specified");

	my $rm;

	# Support call-back instead of CGI mode param
	if (ref($rm_param) eq 'CODE') {
		# Get run mode from subref
		$rm = $rm_param->($self);
	}
	# support setting run mode from PATH_INFO
	elsif (ref($rm_param) eq 'HASH') {
		$rm = $rm_param->{run_mode};
	}
	elsif ($args->{rm}) {
		$rm = $q->param($args->{rm});
	}
	# Get run mode from CGI param
	else {
		$rm = $q->param($rm_param);
	}

	# If $rm undefined, use default (start) mode
	my $def_rm = $self->start_mode();
	$def_rm = '' unless defined $def_rm;
	$rm = $def_rm unless (defined($rm) && length($rm));

	# Set get_current_runmode() for access by user later
	$self->{__CURRENT_RUNMODE} = $rm;

	# Allow prerun_mode to be changed
	delete($self->{__PRERUN_MODE_LOCKED});

	# Call PRE-RUN hook, now that we know the run mode
	# This hook can be used to provide run mode specific behaviors
	# before the run mode actually runs.
 	$self->call_hook('prerun', $rm);

	# Lock prerun_mode from being changed after cgiapp_prerun()
	$self->{__PRERUN_MODE_LOCKED} = 1;

	# If prerun_mode has been set, use it!
	my $prerun_mode = $self->prerun_mode();
	if (length($prerun_mode)) {
		$rm = $prerun_mode;
		$self->{__CURRENT_RUNMODE} = $rm;
	}

	my %rmodes = ($self->run_modes());

	my $rmeth;
	my $autoload_mode = 0;
	if (exists($rmodes{$rm})) {
		$rmeth = $rmodes{$rm};
	} else {
		# Look for run mode "AUTOLOAD" before dieing
		unless (exists($rmodes{'AUTOLOAD'})) {
			die("No such run mode '$rm'");
		}
		$rmeth = $rmodes{'AUTOLOAD'};
		$autoload_mode = 1;
	}

	# Process run mode!
	my $body;
	eval {
		$body = $autoload_mode ? $self->$rmeth($rm) : $self->$rmeth();
	};
	if ($@) {
		my $error = $@;
        $self->call_hook('error', $error);
		if (my $em = $self->error_mode) {
			$body = $self->$em( $error );
		} else {
		croak("Error executing run mode '$rm': $error");
		}
	}

	# Make sure that $body is not undefined (supress 'uninitialized value' warnings)
	$body = "" unless defined $body;

	# Support scalar-ref for body return
	my $bodyref = (ref($body) eq 'SCALAR') ? $body : \$body;

	# Call cgiapp_postrun() hook
	$self->call_hook('postrun', $bodyref);

	# Set up HTTP headers
#	my $headers = $self->_send_headers();

	# Build up total output
#	my $output  = $headers.$$bodyref;
	my $output  = $$bodyref;

	# Send output to browser (unless we're in serious debug mode!)
	unless ($ENV{CGI_APP_RETURN_ONLY}) {
		print $output;
	}

	# clean up operations
	$self->call_hook('teardown');

	return $output;
}

sub teardown {
	my $self = shift;
}

sub error {
	my $self = shift;
	my $error_str = shift; #a copy of the $@ of the badness.

	print "\nError (PID $$): $error_str\n\n";
#	
#	
#	#its been requested (by Jay at least) and I know myself it would be a nice thing to do, so here we have an error mode to output app errors in a pretty way, not a "OMG Server Belew UP!" kind of way.
#		#along with error message, we can include particular client/request infos, and we can put a date on it.
#		#should _probably_ be using a specific error handling sub-tmpl that could be overridden by each app, with a nice standardized one. do that when this stuff that was done for CMCReg is not good enough (hardcoded html attributes could make it ugly on another site, but this auto-scrolling div thing works nice on CMC)
#	my $tp = localtime();
#	my $tstr = $tp->ymd . ' ' . $tp->hms;
#	my $userinfo = $self->get_userinfo();
#	my $userid = $userinfo->{logged_in} ? $userinfo->{id} : '[Not Logged In]';
#	my $app_id = $self->param('_app_id');
#	my $secure = $self->env('https') eq 'on' ? 'Yes' : 'No';
#	my $info_str = qq{
#		<div style="width: 555px; overflow-x: auto;">
#			<p style="margin-bottom: 0px;">
#				Date: $tstr<br/>
#				Secure Connection: $secure <br/>
#				App ID: $app_id<br/>
#				User ID: $userid<br/>
#				<br/>
#				Error Details:<br/>
#			</p>
#			<pre style="margin-top: 0px; margin-bottom: 0px;">
#				<p>$error_str</p>
#			</pre>
#			<h2 style="margin-bottom: 25px;">If this is an unexpected error, please forward the above information to <a href="mailto:support\@shrinkingplanet.com?subject=Software Error">support\@shrinkingplanet.com</h2>
#		</div>
#	};
#	
#	return $self->generic_conf_controller({ 
#		direct_strings => {
#			conf_heading => "Software Error",
#			conf_body => $info_str,
#		}, 
#	});
}

sub ch_debug { my $self = shift; return undef; } #bitch begone.

sub dbg_print {
	my $self = shift;
	my $config = $self->param('_config');

	if ($config->{no_standalone_debug_output}) { return; }
	my $var = shift;
	if (!$var) { return undef; }

	if (ref($var) ne 'ARRAY') { $var = [$var] } 
	my $d = Data::Dumper->new([$var]); #not sure why I have to stick it into ANOTHER arrayref to get the output the way I used to have it ... but seems like I do. Whatev! Maybe check out Data::DumperHTML or something like that for more superfoo at a later date.
	$d->Sortkeys(1);
# print "<pre>" . $d->Dump . "</pre>";
	print $d->Dump;
	print "\n\n";
	return 1;
}

#theres not really any purpose for a session function so I'm going to override it here so that CAP::Session doesnt try to set up cookies and stuff.
	#noo wait we can return our self, seince the only thing called on session() is ->param() and we have a param method that will work the same so why the f not! weeeeeee
sub session {
	my $self = shift;
	return $self; 
	#return undef;
}


1;

############################################################################################################
############################################################################################################
######################                                                         #############################
######################    Major Division. New Package below.                   #############################
######################        It replaces our CGI/Apreq-thing                  #############################
############################################################################################################
############################################################################################################

#This StandaloneQuery is to give it a way to access command line args as if they were query params.
package SpApp::StandloneQuery;
use strict;

sub new {
	my $invocant = shift;
	my $class    = ref($invocant) || $invocant;  # Object or class name
	my $self = {};
	bless $self, $class;

	#probably should parse the @ARGV and set up self with it.
	#going to treat it REALLY simple, assume we could have got a series of name=value pairs and split 'em up on equal sign. if there is no equalsign, then whatever was provided equals 1.
	$self->{__PARAMS} = {};
	
	foreach (@ARGV) {
		my ($name, $value) = split(/=/, $_);
		if (!$value) { $value = 1; } #if there is no equal sign.
		$self->{__PARAMS}->{$name} = $value;
	}
	#$self->ch_debug(['the query params:', $self->{__PARAMS}, 'come from argv like:', \@ARGV]);
	#die "the stop";

	return $self;
}

#ripped from CA
sub param {
	my $self = shift;
	my (@data) = (@_);

	# First use?  Create new __PARAMS!
		#nope did it in new.
	#$self->{__PARAMS} = {} unless (exists($self->{__PARAMS}));

	my $rp = $self->{__PARAMS};

	# If data is provided, set it!
	if (scalar(@data)) {
		# Is it a hash, or hash-ref?
		if (ref($data[0]) eq 'HASH') {
			# Make a copy, which augments the existing contents (if any)
			%$rp = (%$rp, %{$data[0]});
		} elsif ((scalar(@data) % 2) == 0) {
			# It appears to be a possible hash (even # of elements)
			%$rp = (%$rp, @data);
		} elsif (scalar(@data) > 1) {
			croak("Odd number of elements passed to param().  Not a valid hash");
		}
	} else {
		# Return the list of param keys if no param is specified.
		return (keys(%$rp));
	}

	# If exactly one parameter was sent to param(), return the value
	if (scalar(@data) <= 2) {
		my $param = $data[0];
		return $rp->{$param};
	}
	return;  # Otherwise, return undef
}

#ripped from CA
sub delete {
	my $self = shift;
	my ($param) = @_;
	#return undef it it isn't defined
	return undef if(!defined($param));

	#simply delete this param from $self->{__PARAMS}
	delete $self->{__PARAMS}->{$param};
}

sub delete_all {
    my $self = shift;
    my $table = $self->{__PARAMS};
    my @args = keys %$table;
    foreach my $arg (@args) {
			delete $self->{__PARAMS}->{$arg};
    }
}

sub cookie {
    my ($self, @args) = @_;
		die "No cookie support in standalone scripts (how would _THAT_ work?). Find a way to not use cookies for your desired standlone command line utillity based task."
}

sub upload {
    my ($self, $file) = @_;
		die "No upload support in standalone scripts (how would _THAT_ work?). Find a way to not use file-upload for your desired standlone command line utillity based task."
}

#ripped from CAPARRipAPReq which is itself ripped and hacked from CGI::Application::Plugin::Apache and CGI::Application::Plugin::Apache::Request.
sub Dump {
    my $self = shift;
    my($param,$value,@result);
    return '<ul></ul>' unless $self->param;
    push(@result,"<ul>");
    foreach $param ($self->param) {
        my $name = $self->escapeHTML($param);
        push(@result,"<li><strong>$name</strong></li>");
        push(@result,"<ul>");
        foreach $value ($self->param($param)) {
            $value = $self->escapeHTML($value);
            push(@result,"<li>$value</li>");
        }
        push(@result,"</ul>");
    }
    push(@result,"</ul>");
    return join("\n",@result);
}

#ripped from CAPARRipAPReq which is itself ripped and hacked from CGI::Application::Plugin::Apache and CGI::Application::Plugin::Apache::Request.
sub Vars {
    my $self = shift;
    my @params = $self->param();
    my %Vars = ();
    foreach my $param (@params) {
        my @values = $self->param($param);
        if( scalar @values == 1 ) {
            $Vars{$param} = $values[0];
        } else {
            $Vars{$param} = \@values;
        }
    }

    if(wantarray) {
        return %Vars;
    } else {
        return \%Vars;
    }
}

#ripped from CAPARRipAPReq which is itself ripped and hacked from CGI::Application::Plugin::Apache and CGI::Application::Plugin::Apache::Request.
sub escapeHTML {
    my ($self, $value) = @_;
    $value = HTML::GenerateUtil::escape_html($value, 
        (
            $HTML::GenerateUtil::EH_LFTOBR 
            | $HTML::GenerateUtil::EH_SPTONBSP 
            | $HTML::GenerateUtil::EH_LEAVEKNOWN
        )
    ); 
    return $value;
}



1;