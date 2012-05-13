package SpApp::Auth;

use strict;

sub new {
	my $class = shift;
	my $self = {};
	bless $self, $class;

	my $web_app = shift; #needed for access to dbh, query, session, etc.
	my $other_args = shift;

	$self->{_ERROR_COND} = undef;	#set up for error method. why here? dunno.
	if (!$web_app) {
		$self->error('new needs a webapp.');
	}
	$self->{wa} = $web_app;
	
	return $self;
}

sub error {
	my $self = shift;
	my $value = shift;
	
	if ($value) {
		$self->{_ERROR_COND} = $value;
		die "Auth Error: $value";
	} else {
		return $self->{_ERROR_COND};
	}
}

sub forced_login {
	my $self = shift;
	my $args = shift;
	
	my $auth_params = $self->{wa}->_auth_params();
	if (!$auth_params) {
		$self->error("forced_auth needs auth_params to inspect - they weren't passed in and i couldn't obtain them myself.");
	}
	if (!$args->{id}) {
		$self->error("forced_auth needs an 'id' key in args, to log such a user in.");
	}
	
	#$auth_params->{fields} = [ 'id' ]; #override fields list with just the id field to match against.
	$auth_params->{forced_for_id} = $args->{id};
	
	return $self->basic_auth($auth_params);
}

#think, make use of auth_params and then redirect to one of these: 
	#logged_in_rm (possibly with logged_in_callback first)
	#bad_login_rm (possibly with bad_login_callback first)
	
	#callbacks live in webapp and get $userinfo as arg.
sub basic_auth {
	my $self = shift;
	my $auth_params = shift;
	
	if (!$auth_params) {
		$auth_params = $self->{wa}->_auth_params();
	}
	if (!$auth_params) {
		$self->error("basic_auth needs auth_params to inspect - they weren't passed in and i couldn't obtain them myself.");
	}

	#features of basic_auth (and everything should have a default):
		#table to auth against
		#fields to match and how
	#example auth params:
	#	my $auth_params = {
	#		table  => 'user',
	#		fields => ['username', 'password'], #these are the fields we must match.
	#   cgi_params => {username => 'login_username', password => 'login_password'}, #this can give us a db field name to cgi param mapping if for some reason the cgi params are different than the field names.
	#		field_hashing => {password => 'MD5'} #ancient version 3.23 doesnt even have SHA1. Not that either are all that secure. But its nice to know that i dont know the password you use for both SPI apps and your banking.
	#		sessionize => ['first_name, userlevel'], #among other things to put into _userinfo in the session.
	#		logged_out_rm => 'show_login',
	#		logged_in_rm => $self->start_mode(),
	#	};
	
	my $cgi = $self->{wa}->query();
	my $userinfo = {}; #when this is finished we set it in the session.
	if ($auth_params->{forced_for_id}) {
		$auth_params->{fields} = [ 'id' ]; #override fields to check with 
	}
	
	#pick up values from the cgi. when not doing forced auth.
	my $cgi_params;
	if (!$auth_params->{forced_for_id}) {
		foreach (@{$auth_params->{fields}}) { 
			if ($auth_params->{cgi_params}) {
				#cgi param names differ from field names
				$cgi_params->{$_} = $cgi->param($auth_params->{cgi_params}->{$_});
			} else {
				#cgi params are the same as field names (easier)
				$cgi_params->{$_} = $cgi->param($_);
			}
		}
	} else {
		$cgi_params->{id} = $auth_params->{forced_for_id};
	}
		
	$self->{wa}->ch_debug(['basic_auth: cgi_params are presently: ', $cgi_params]);
	my $userlevel_field = $auth_params->{userlevel_field} ? $auth_params->{userlevel_field} : 'userlevel';
	my $table = $auth_params->{table};
	my $where_fields; #dupe free list of fields.
	my $select_fields = {$userlevel_field => 1, 'id' => 1}; #assume this is there.
	my @binds  = ();
	foreach (@{$auth_params->{fields}}) { $where_fields->{$_} = 1; }
	foreach (@{$auth_params->{sessionize}}) { $select_fields->{$_} = 1; }
	if ($auth_params->{field_hashing}) {
		foreach (keys(%$where_fields)) {
			if ($auth_params->{field_hashing}->{$_}) { 
				$where_fields->{$_} = $auth_params->{field_hashing}->{$_}; #now the value is not just 1, its the hashing function to use.
			}
		}
	}

	my @where_fields = map { 
		push(@binds, $cgi_params->{$_});
		("$_ = " . (($where_fields->{$_} eq 1) ? '?' : $where_fields->{$_} . '(?)')); #will get either just the field name or the fieldname wrapped in the function plus = ? for the bind setup.
	} keys(%$where_fields);
	
	#min_userlevel check
	if ($auth_params->{min_userlevel}) {
		push(@where_fields, "$userlevel_field >= ?");
		push(@binds, $auth_params->{min_userlevel});
	}	
	
	#required values on the user record? (new for 20070119)
	if ($auth_params->{required_values}) {
		foreach(keys(%{$auth_params->{required_values}})) {
			push(@where_fields, $_ . ' = ?');
			push(@binds, $auth_params->{required_values}->{$_});
		}		
	}
	
	my @select_fields = keys(%$select_fields);
	my $sql = 'SELECT ' . join(', ', @select_fields) . " FROM $table WHERE " . join(' AND ', @where_fields);
	$self->{wa}->ch_debug(['basic_auth: going to query with this sql and binds: ', $sql, \@binds]);

	my $dbh = $self->{wa}->get_dbh();
	my $row = $dbh->selectrow_hashref($sql, undef, @binds);
	if ($dbh->errstr) {
		die "Stopping with db error: " . $dbh->errstr;
	}
	$self->{wa}->ch_debug(['basic_auth: got this row :', $row]);
	$self->{wa}->debuglog(['basic_auth: got this row :', $row]);
	
	if ($row) {
		my $userinfo = $row;
		$userinfo->{logged_in} = 1;
		$userinfo->{userlevel} = $row->{$userlevel_field}; #with new ability to have a nonstandard userlevel field (added for IDL new pricebook admin piece, to auth against a very ancient legacy admin tanle), we need to make bloody sure that we have something called userelevel in the row since we save it in the session and use it for stuff.
		
		#we must save user info in an app-specific way so that _userinfo of one app is not interpreted by userinfo of another app.
			#now we'll use a parameter name derived from the app name for the userinfo to be stored and checked from.
			#### needs improvement ... edu r1 and edu r2 with different conf files are sharing the same sess param which is buhbuhbuhBAD
		my $sess_param = '_userinfo_' . $self->{wa}->param('_app_id');
		$self->{wa}->session()->param($sess_param => $userinfo);
		$self->{wa}->ch_debug(['basic_auth: to save this userinfo in the session:', $userinfo, 'in a session param named', $sess_param]);
		$self->{wa}->debuglog(['basic_auth: to save this userinfo in the session:', $userinfo, 'in a session param named', $sess_param]);
		
		#one day maybe just return the result. for now, do a redirect based on it!
		#die "to stop with good login before redir";
		
		#try to figure out how to do a callback to a app func that might not even be defined and dont crash if it isnt
			#this seems to work -- figured through pouring over CGI::App hook stuff which uses similar concept.
		#2007 03 27: making a new rule about auth callbacks: they can return a runmode name, or a hashref of { rm => 'runmode name', redirect_params => { foo => 'bar' } }
		if ($auth_params->{forced_for_id}) { return 1; }
		return $self->{wa}->redirect_runmode($self->execute_pre_redirect_callback('logged_in', {
			auth_params   => $auth_params, 
			callback_args => $userinfo,
		} ));
	} else {
		#for now I'm not going to damage an already good login if incorrect creds are put on the login screen again
		$self->{wa}->ch_debug(['no match. sql error if there was one:', $dbh->errstr]);
		#die "to stop with bad login before redir";

#		#2007 02 02, adding a bad_login_callback that gets the cgi_params mainly so that I can just put the cmcreg login email address in the session so that i can later redisplay it in the form, but I imagine this could be generally useful anyway.
#		if (defined($auth_params->{bad_login_callback})) {
#			my $callback_func = $auth_params->{bad_login_callback};
#			my $callback_output = eval '$self->{wa}->$callback_func($cgi_params)'; #note, was calling it like eval($self->{wa}->$callback($self)) before but that would NOT let me return a string ... using eval '' or eval {} seems to work though -- apparently {} will be compiled at compile time, but i will use '' so to be sure it is compiled at runtime. honestly not sure if I _need_ to do that, but sounds safer to me since the callback function will change with each call, compiling it once could cause a problem i would imagine if the callback was to be used differently within the same request.
#			#well we dont really need output for it .. but i'll take it anyways.
#			die "Error executing Auth->basic_auth bad_login_callback: $@" if $@;
#		}
		if ($auth_params->{forced_for_id}) { return 0; }

		my $default_redir_params = { bad_login => 1};
		#2007 03 27 abstracted out callback execution. coolness.
		return $self->{wa}->redirect_runmode($self->execute_pre_redirect_callback('bad_login', { 
			auth_params => $auth_params, 
			callback_args => $cgi_params, 
			redir_params => $default_redir_params,
		} ));
#		return $self->{wa}->redirect_runmode($auth_params->{bad_login_rm}, { bad_login => 1} );
	}
	
	#return $self;
}

sub logout_redirect {
	my $self = shift;

	my $auth_params = $self->{wa}->_auth_params();
	my $userinfo    = $self->{wa}->get_userinfo(); #not sure but thinking get_userinfo should live here in auth and the SpApp function should just call this. though the information IS stored in the webapp's session .. so hrm.
	#in this case, we need to do any callback stuff before unsetting the session userinfo, so we do the callback/runmode-change setup first, unset the info, then do the redirect.
	my @redir_args = $self->execute_pre_redirect_callback('logged_out', { auth_params => $auth_params, callback_args => $userinfo });
	$self->{wa}->session()->param('_userinfo_' . $self->{wa}->param('_app_id') => {}); #clear userinfo
	return $self->{wa}->redirect_runmode(@redir_args);
}

sub logout {
	my $self = shift;
	$self->{wa}->session()->param('_userinfo_' . $self->{wa}->param('_app_id') => {}); #clear userinfo
	return undef;
}

sub is_logged_in {
	my $self = shift;

	#my $userinfo = $self->{wa}->session()->param('_userinfo');
	#my $sess_param = '_userinfo_' . $self->{wa}->param('_app_name');
	#my $userinfo = $self->{wa}->session()->param($sess_param);
	my $userinfo = $self->{wa}->get_userinfo();
	
	if ($userinfo) {
		return $userinfo->{logged_in};
	} else {
		return undef;
	}
}

sub approve_runmodes {}

sub check_auth {
	#should this function go in Auth.pm? I think so. but then how would the userlevel and runmodes allowed work? Cross this bridge when it arrives.
	
	my $self = shift;
	my $runmode = shift; #the name of the requested runmode as provided by cgiapp_prerun.
	###my $auth_modes = shift; #for of the individual runmode authorization checks. runmode_name => min_userlevel format.
	my $other_args = shift; #for more later.

	#my $userinfo = $self->{wa}->session()->param('_userinfo'); #should'a been put there by SpApp::Auth.
	#my $userinfo = $self->{wa}->session()->param('_userinfo_' . $self->{wa}->param('_app_name')); #should'a been put there by SpApp::Auth.
	my $userinfo = $self->{wa}->get_userinfo();

	$self->{wa}->ch_debug(['check_auth: with userinfo from the session like:', $userinfo, 'from a webapp function named get_userinfo()']);

	if (!$userinfo || !$userinfo->{logged_in}) {
		return 0;
	}
	
	#and what can we do if we are authed?
	#proposed userlevels:
		#1: locked-out user account (sounds cool)
		#10: standard userlevel.
		#20: superuser.

	#eventually I want to be able to be specific about what userlevels can access what.
		#lets say rules for that would be contained in app auth_params and if we didnt get those here then we cant bother to check that stuff out for the calling app.
	my $is_authed = 1; #turns false if the passed in runmode is not allwoed for the luserlevel.
	
	#superbasic min_userlevel thing:
	my $app_runmodes = $self->{wa}->_runmode_map();
	#grep for modes that actually have a userlevel set, 
	
#	my $mode_min_userlevels = { map { $_ => $app_runmodes->{$_}->{userlevel} } grep { $app_runmodes->{$_}->{userlevel} } keys(%$app_runmodes) };
#	$self->{wa}->ch_debug(['checking if authorized for runmode named $runmode, app runmodes are: ', $app_runmodes, 'mode minuserlevels is', $mode_min_userlevels]);
#die "stoppa";
#	if ($mode_min_userlevels->{$runmode} && ($userinfo->{userlevel} < $mode_min_userlevels->{$runmode})) {
#		$is_authed = 0;
#	}

	if ($app_runmodes->{$runmode}->{userlevel} && ($userinfo->{userlevel} < $app_runmodes->{$runmode}->{userlevel})) {
		$is_authed = 0;
	}
	

	#more fine grained -- can call a subroutine maybe to find out if it can be. this I think is where the auth_subref aspect of the _runmode_map would probably be taken into consideration.
	
	#for now I just want to return is_authed status.
	return $is_authed;
}

#this works like so:
	#it is for handling stuff before sending to logged_in_rm, logged_out_rm, bad_login_rm
	#it returns a rm and redirect params, it is expected that a redirect will be done with the return.
	#if no callback is defined for the rm will not be changed from what is defined for the action in auth_params.
	#if a callback is defined, then the rm _could_ be changed. (callbacks can return a scalar for just changing the rm, or a hashref with 'rm' and 'redirect_parms' keys)
sub execute_pre_redirect_callback {
	my $self = shift;
	my $redirect_name = shift;
	my $args = shift;
	
	my $auth_params   = $args->{auth_params};
	my $callback_args = $args->{callback_args};

	if (!$auth_params) {
		$auth_params = $self->{wa}->_auth_params();
	}
	if (!$auth_params) {
		$self->error("execute_pre_redirect_callback needs auth_params to inspect.");
	}
	
	my $rm           = $auth_params->{$redirect_name . '_rm'};
	my $redir_params = $args->{redir_params} ? $args->{redir_params} : {}; #might have some hardcoded ones that it should be based on. will assume that if we get redir_params from the callback that they totally replace anything that was passed in here.

	if (defined($auth_params->{$redirect_name . '_callback'})) {
		my $callback        = $auth_params->{$redirect_name . '_callback'};
		my $callback_output = eval '$self->{wa}->$callback($callback_args)';
		#my $callback_output = $callback->($self, $callback_args);
		if (defined($callback_output)) {
			if (ref($callback_output) eq 'HASH') {
				#note, the way this is coded we should also be able to return just a hash of { redirect_params } to set those up without changing the redirect runmode.
				if ($callback_output->{rm}) {
					$rm = $callback_output->{rm};
				}
				if ($callback_output->{redirect_params}) {
					$redir_params = $callback_output->{redirect_params};
				}
			} else {
				#its defined but its not a hashref, then we assume its just a runmode name
				$rm = $callback_output;
			}
		}
		#dont really care too much what happend in the eval ... it either did it or not .. but for _NOW_ we'll die if there were problems.
		die "Error executing Auth->execute_pre_redirect_callback: $@" if $@;
	}
	
	return ($rm, $redir_params); #returning as a list, intended to be passed directly to redirect_runmode as its arguments (runmode, query_params) 
}


1;
