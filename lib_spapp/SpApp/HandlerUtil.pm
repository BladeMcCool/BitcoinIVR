package SpApp::HandlerUtil;
use base 'SpApp::Core';
use strict;
#this is so that I can have some code which will give me my standard things like a database handle and access to config file, etc, designed to work within an apache handler, which mainly means obtaining its environment information a little differently.
	#I think in the long run the bulk of the code in here and in the similarly named functions from the real app could go into a SpApp::AppUtil package which would have all the code in a unified way.

use FlatFile;
use Apache2::Const;
Apache2::Const->import(-compile => qw(REDIRECT OK HTTP_TEMPORARY_REDIRECT HTTP_MOVED_TEMPORARILY HTTP_NOT_FOUND DECLINED)); #mainly for the redirect stuff. not sure how I'd stick this in vhost.conf
#use Apache2::RequestRec;
#use APR::Request::Apache2;
#use APR::Table;

#use constant MP2 => ( exists $ENV{MOD_PERL_API_VERSION} and $ENV{MOD_PERL_API_VERSION} >= 2 ); #suggested by http://perl.apache.org/docs/2.0/user/coding/coding.html#Environment_Variables

#use vars qw {$APPNAME};

#see notes in SpApp::Core for more info on why these vars are being used.
my $_ALL_CONFIG = {}; 
my $_ALL_LOAD_STATE = {};
my $_CONFIG = undef; 
my $_LOAD_STATE = undef; 


sub new {
	#this constructore code ripped from CGI::App and then chopped down/modified.
	my $class = shift;
	my @args = @_;

	if (ref($class)) {
		# No copy constructor yet!
		$class = ref($class);
	}

	# Create our object!
	my $self = {};
	bless($self, $class);

	return $self;
}

sub _gobal_object_init { return undef } #can override and make it do something else initty . like cache a bunch of uri's that it has to protect or something maybe.

#this should always be the first thing that happens when a new request is being handled. it will set us up with the current request, init our global and process-life-long-constant items (like configuration params) if they havent been done already, etc.
	#_init will run once globally. it has a hook for subclass to do stuff at the end.
	#_init_request will do all the request specific setup, basically the important stuff for executing an application function in response to a particular incoming request. there should be a teardown that atually resets things and this should be a preparer that "sets" things to begin with.
sub _reset_for_request {
	my $self = shift;
	my $r = shift;

	$self->param('_app_name' => $r->dir_config('app_name'));
	$self->param('_conf_name' => $r->dir_config('conf_name'));

	$self->{_R} = $r;
	$self->_init_environment({ _R => $r }); #now hoping to be able to set up and work in a mp handler or as a standalone registry dealo. ... yikes or not. But abstract env info is good anyway.
	
	$self->_init($r); #run once (per app_id - for various reasons like looking for the userinfo in the right place in multinamed vhosts like my dev box)
	$self->_init_request($r);	#run many

	#an init subclass hook.
	#needs to be a run-once kind of deal. maybe stick it over in init with a general, non app_id specific condition for run-once.
#	$self->_gobal_object_init(); #subclass method for doing setup stuff for global objects, stuff that will get run once only.

}
	

#ripped from CAPA: but modded by me to tighten.
sub handler : method {
    my ($class, $r) = @_;
	 die "handler method must be overridden by a subclass!";
    # run it with our new query object
    $class->new(QUERY => SpApp::CAPARRipAPReq->new($r))->run();
    return Apache2::Const::OK();
}

sub ch_debug {
	my $self = shift;
#some options below ... also can just do nothing by having them commented out (you know, in case you want explicit debuglog's only going out and not a bazillion ch_debug's filling up the debuglog)
#	$self->debuglog(@_); #send the info somewhere. but I dont want to do headers right now or put output since we're in an apache handler!
#	$self->debuglog("handlerutil's ch_debug called but we shouldnt be sending any headers rihgt now");
	return undef;
}

sub _init {
	my $self = shift;
	my $r = shift;
	
	
	#init once for every app id ... b/c i have multiple names for this host in the same vhost and so that is fucking up my 
	my $app_id = $self->param('_app_id');
	if ($self->param($app_id . '_inited')) { return $self; } #already init'ed ..
	
#	$self->{_R} = $r;
#	$self->_init_environment($r); #now hoping to be able to set up and work in a mp handler or as a standalone registry dealo. ... yikes or not. But abstract env info is good anyway.

#	$self->param('is_mp_handler' => 1); #so environment vars come from the right place. errr ... that now happens if _init_environment gets a $r.

#	my $vhost_root = $r->document_root();
	my $vhost_root = $self->env('document_root');
	$vhost_root =~ s|(.*)/.*|$1|; #strip last dir off (usually httpdocs) to get siteroot dir
	$self->param('_vhost_root', $vhost_root);

	#get config and load state set up.
	my $debug_loaded_config = 0;

#	my $app_id = $r->hostname  . '|' . $self->param('_app_name') . '|' . ($self->param('_conf_name') ? $self->param('_conf_name') : 'default');
	$_CONFIG = $_ALL_CONFIG->{$app_id}; #that key must be unique system-wide. mod_perlish stuff.
	$_LOAD_STATE = $_ALL_LOAD_STATE->{$app_id}; #that key must be unique system-wide. mod_perlish stuff.
	if (!defined($_LOAD_STATE)) {
		#btw doing this b/c we need to establish a hashref and stick it back into the all_load_state if we havent done so already. otherwise it never 'sticks'.
		$_LOAD_STATE = {};
		$_ALL_LOAD_STATE->{$app_id} = $_LOAD_STATE;
	}
	if (!$_CONFIG) {
		#maybe umm the key should be the conf file name on the vhost instead? i see myself potentially having a problem with it like below ... but whatever for now!
		$_ALL_CONFIG->{$app_id} = $_CONFIG = $self->read_config(); #coded like so b/c read_config will return a new hashref ... we gotta make sure it gets back into the all_config.
		$_LOAD_STATE->{read_config} = 1;
		$debug_loaded_config = 1; #b/c we just loaded it.
	}

	$self->param('_config', $_CONFIG); #would rather the config func refer to a self->param.

	#config dependent stuff:
	my $session_dir = $self->config('session_dir'); #if not provided in config file then default 'sessions' will be used.
	$self->param('_session_path', $vhost_root . '/' . ($session_dir ? $session_dir : 'sessions'));
	$self->param('_app_label', $self->config('app_label'));	
	$self->param('_tmpl_path', $vhost_root . '/tmpl_' . $self->config('tmpldir_suffix'));
	$self->param('_tmpl_cache_path', $vhost_root . '/tmpl_cache_' . $self->config('tmpldir_suffix'));
	
	$self->param($app_id . '_inited' => 1);
	return $self;
}

	#this is basically a rip of my normal cgiapp_init, with a few minor diffs. will probably incorporate those into unified one later.
sub _init_request {
	my $self = shift;
	my $r    = shift;

#	print STDERR "pid $$: entered _init\n";
	
	$self->{__session_established} = 0; #reset this every time we init. dont want to end up ever giving one users session data to another user!
	$self->{__QUERY_OBJ} = $self->cgiapp_get_query($r); #make sure we are using a fresh query object. (which will use the same $r that was just passed in via Apache2::RequestUtil and CAPARRipAPReq and its parents. This way we stop the segfault problem that plagued us all day today 2007 03 23. Makes sense since CA caches the query object and it would be stale and a mismatch with the one running the live request most of the time. So we are sure to update the cache for THIS request! :)

#	print STDERR "pid $$: _init 1\n";

	my $web_prot = ($self->env('https') eq 'on') ? 'https://' : 'http://'; #decide whether we are using http or https ... hint, if the doc root is httpsdocs and we got here on port 443, we're doing https.
#	$self->param('_script_url_prefix', 'http://' . $self->env('http_host')); 
	$self->param('_script_url_prefix', $web_prot . $self->env('http_host')); 
	$self->param('_http_script_url_prefix', 'http://' . $self->env('http_host')); 
	$self->param('_https_script_url_prefix', 'https://' . $self->env('http_host')); 
	$self->param('_script_name', $self->env('script_name')); #for handlers, script name will be the uri.

	#dont set up debugmode in handlers, to avoid uneccessary hit to session (which will probably create it and send the cookie!)
	return $self;
}

sub session {
	my $self = shift;
	#die "whoat there tiger, do you _really_ need the session? Also before we start using it, we'd really like to get it working with the CAP::CS module ... get the code working and then kludge in the wordpress broken cookie jar fix.";
	if (!$self->{__session_established}) {
		my $session = $self->setup_session();
		$self->{__session} = $session;
		$self->{__session_established} = 1;
		return $session;
	} else {
		return $self->{__session};
	}
}

#eventually, if not sooner than later, i'm going to want to take all the functions that both HandlerUtil and SpApp::Core want to use and put them somewhere that both places can use them.	
sub setup_session {
	#changed from setup_session ... thinking that here in this code, I would never actually want to establish it ... just read from it and maybe if it exists already set a value or something but NOT establish it if it is not already established.
	my $self = shift;

	#check our load state before bothering with filesystem checks.
	if (!$_LOAD_STATE->{checked_session_path}) {
		if (!-e $self->param('_session_path')) { die "setup_session: fatal error, sessions path '" . $self->param('_session_path') . "' does not exist"; }
		if (!-w $self->param('_session_path')) { die "setup_session: fatal error, sessions path '" . $self->param('_session_path') . "' exists but is not writable for me";	}
		if (!-r $self->param('_session_path')) { die "setup_session: fatal error, sessions path '" . $self->param('_session_path') . "' exists but is not readable for me";	}
		$_LOAD_STATE->{checked_session_path} = 1; #under mod perl we should only have this once per process ... gonna print to stderr to be sure.
		$self->debuglog("setup_session (hu): just successfully checked the session path " . $self->param('_session_path') . " for pid $$\n");
	} else {
		$self->debuglog("setup_session (hu): already checked the session path for pid $$ and it was fine (you're seeing this)\n");
	}
		
	my $sess_id; #will check cookies, then query. 
	#my $sess_name = 'CGISESSID'; #default of CGI::Session, and all our apps should be using this default. 
	my $sess_name = CGI::Session->name(); #get default session name. all apps should be using default.
	my $apr = APR::Request::Apache2->handle($self->{_R});

	#see http://marc2.theaimsgroup.com/?l=apreq-dev&m=114001388709851&w=2
	#for where I started for the info for the code below. Note it says APR::Request::Apache2->new, which doesnt exist, so I used APR::Request::Apache2->handle which exists, and seems to work.
  #this is basically just an error safe way of getting the cookies I believe. -- we were having errors parsing some cookie that wordpress sets -- but we can't let that bust our ballz!.
		#note this code here is copied from ShorcanHTML::Filter and hacked up. It took me, IIRC, days to figure this shit out and get it working originally. dont fuck with a good thing!
	my $jar;
  eval { 
  	$jar = $apr->jar; 
  }; #table of cookies -- as in a APR::Request::Cookie::Table object.
  if (ref $@ and $@->isa("APR::Request::Error") ) {
     $jar = $@->jar; # table of successfully parsed cookies
     $self->debuglog("setup_session: Error condition (probably bad wordpress cookie or similar issue) while parsing cookies. Should be recoverable with this implementation\n");
  }
  if ($jar) {
  	$sess_id = $jar->{$sess_name};
  } else {
  	$self->debuglog("setup_session: NO cookie jar obtained. Should we have got one?\n");
  }

	#get GET (and/or POST? not sure) params via $apr->param(); -- we're just going to do it if we didnt get a session id through other means.
	my $send_cookie = 0; #send the cookie only if we know we are establishing a new session.
	if (!$sess_id) {
		#I want to be able to easily pass the session id via query params too, because the cheesy templating solution to have the apps load their tmpls via apache (lame I know) will need to pass it along to be accessible here.
		$sess_id = $apr->param('sess_id');
	}

#	#if we got a sess_id, obtain the session and check the logged in status.
#	my $session = undef;
#	if ($sess_id) {
#		$self->debuglog(['session id (presently we are trying cookies first then request params for it):', $sess_id]);
#		$session = CGI::Session->load("driver:File;serializer:Storable", $sess_id, { Directory => 	$self->param('_session_path') });
#	} else {
#		$self->debuglog("setup_session: not doing anything since there was no session id obtained\n");
#	}

	#get a session regardless. 
	my $session = CGI::Session->new("driver:File;serializer:Storable", $sess_id, { Directory => 	$self->param('_session_path') });	
	$session->expire('+7d'); #default. this is bad tho i need like an app::defaults module or something which defines defaults that should be shared by this module and SpApp::Core.
	if (!$session) {
		die "Couldnt create session";
	}
	#using (basically) same rules as CGI::Applicaion::Plugin::Session to decide to send the cookie:
		#we didnt get a sess_id, we got one but the session object gave us a different ID, or the session has an expiry.
#	if (!$sess_id || $sess_id ne $session->id() || $session->expire()) {
	#yeah not sure how the fact that an expiry was ever set would make us want to send the cookie.
	if (!$sess_id || $sess_id ne $session->id()) {
		$send_cookie = 1;
	}
	if ($send_cookie) {
		my $r = $self->{_R};
#		#hrmm should be baking an apache2 cookie. whatev.
#		my $cookie = CGI::Cookie->new(
#			-name  => $session->name(),
#			-value => $session->id(),
#		);
		#hrmm should be baking an apache2 cookie. whatev.
		my $cookie = $self->query()->cookie(
			-name  => $session->name(),
			-value => $session->id(),
			-expires => '+7d',
			-path  => '/',
			-domain => $self->env('http_host_portless'),
		);
		$r->err_headers_out->add('Set-Cookie' => $cookie);
	}
	
	return $session; #if it didnt find it (due to no session id cookie/param or perhaps no existing session matching whatever was provided) then we'll be returning undef here.
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
	if ($query_params) {
		$other_args->{pagename} .= '?';
	}
	
	$self->redirect_runmode(undef, $query_params, $other_args);
}

#can be used to redirect to a runmode or a pagename ... use only a pagename arg for a pagename ... also added a convenience method just for pagename so you can do return $self->redirect_pagename('foo.html');
	#ssl base redirect: (undef, undef, {https => 1})
	#ssl pagename redirect: (undef, undef, {https => 1, pagename => '/foo.html'})
	#ssl runmode redirect: ('foo_rm', undef, {https => 1})
	#ssl runmode redirect with query params: ('foo_rm', {query_param => value}, {https => 1})
	#regular runmode ('foo_rm', {query_param => value})
	#regular pagename (but you should use redirec_pagename for that): (undef, undef, {pagename => '/foo.html'})
sub redirect_runmode {
	my $self = shift;
	my $runmode = shift;
	my $query_params = shift;
	my $other_args = shift;
	
	my $r = $self->{_R};

	my $url_str;

#	if ($other_args->{https}) {
#		$url_str = 'https://' . $r->hostname();
#	} else {
#		$url_str = $self->param('_script_url_prefix');
#	}


#	if ($runmode) {
#		$url_str .= $self->param('_script_name') . "?rm=" . $runmode;
#	} elsif ($other_args->{pagename}) {
#		$url_str .= $other_args->{pagename};
#	} 

#but we can do the pagename part...
	if ($other_args->{pagename}) {
		$url_str .= $other_args->{pagename};
	} 
	
	if ($query_params) {
		foreach (keys(%$query_params)) {
			$url_str .= '&' . $_ . '=' . $query_params->{$_};
		}
	}

	#$self->ch_debug(['the environment', \%ENV, 'and the url so far:', $url_str, 'runmode, queryparams and otherargs:', $runmode, $query_params, $other_args]);
	#die "to stop before redirect header setting.";

	$r->content_type('text/html');
	$r->err_headers_out->set('Location', $url_str);

	$self->debuglog(["redirect_runmode: sending to $url_str"]);
	return 1;
}

1;