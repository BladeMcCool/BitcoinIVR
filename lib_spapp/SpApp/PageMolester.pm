package SpApp::PageMolester;

#the purpose of this gay little bitch module is to 
#	- check if the requested html file is allowed to be seen
#	- read html files out of the file system,
#	-  maybe do something to them, 
#	- and then return the possibly molested content out.
	
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
	} else {
		return $self->{_ERROR_COND};
	}
}

sub ch_debug {
	my $self = shift;
	my $var = shift;
	return $self->{wa}->ch_debug($var);
}

sub show_page {
	my $self = shift;
	my $pagename = shift;
	my $other_args = shift;
	
	my $fixed_pagename = $self->fix_pagename($pagename, undef, $other_args); #note undef should be fixed to be the memberpage dirs when that gets reimplemented ... see the function it calls.
	return $self->read_fix_return($fixed_pagename, $other_args);
}

sub fix_pagename {
	my $self = shift;
	my $pagename = shift;
	my $memberpages_dirs = shift; #we'll pass memberpages dirs so if a bad pagename was specified we can drop them on index page of the first allowed directory.
	my $other_args = shift; #for more control in future.
	
	my $cgi = $self->{wa}->query();

	#no pagename passed in? get it from the query (or pick a pagename failing that)
	if (!$pagename) {
		$pagename = $cgi->param('pagename');
	}
	$pagename = $cgi->unescape($pagename);

	#if user tries to use .. or go to a file that isnt an html file, they'll just get fed the index.html
		#now, a sneaky user could put something like pagename=..%2F..%2Fconf%2Faccess_control.conf and then suddely they are looking at the database uername and password!! very bad. so this is totally insecure ... lets tighten it up a little.
	if ($pagename =~ /\.\./) {
		$pagename = undef; 
	}
		
	#pagename not ending in .html will have index.html added on to it -- that'll screw up requests to non-html pages and tack on index.html to paths that end like somedir/
	if ($pagename !~ /\.html$/) {
		$pagename = undef; 
	}

	#if there is no pagename set (becuase user didnt specify one, or user specified an illegal one thus having it obliterated), set it to index.html inside the first allowed dir.
	if (!$pagename) {
		foreach my $dir (@$memberpages_dirs) {
			if ($dir->{access_type} eq 'allow') {
				$pagename = $dir->{directory} . '/index.html';
				last;
			}
		}
	}

	#if we _still_ dont have a pagename ... just go with plain ol' index.html. and hope it exists haha.	
	if (!$pagename) { 
		$pagename = 'index.html'; 
	}

	return $pagename;
}

sub read_fix_return {
	my $self = shift;
	my $pagename = shift;
	my $other_args = shift;

	my $filepath = $self->{wa}->env('document_root') . '/' . $pagename;
	
	my $outhtml = '';
	if (!-e $filepath) {
		$outhtml .= "Error 404-like: $pagename not found \n";
		$self->error("program would like to read from nonexistant path: $filepath");
		$self->{wa}->ch_debug("program would like to read from nonexistant path: $filepath");
	} else {
		open INFILE, "<$filepath";
		while (<INFILE>) {
			$outhtml .= $_;
		}
		close INFILE;
	}
	
	if ($other_args->{log_pageview}) {
		#assume logging functions are defined in the main spapp core code. that will handle figuring out where to log it, and how. we should just give it the info to log, it must know how to figure the user info its associated with.
		$self->{wa}->log('pageview', $pagename);
	}

	return $outhtml;
}	

###################3
## Be inspired by the code below. But I like much better the idea of rewrite rules to do the actual redirecting requests to the script. That way we dont even actually need to molest the links.
###################3

#sub show_member_page {
#	my $self = shift;
#	my $pagename = shift;
#
#	my $config = $self->{wa}->param('_config');
#	my $memberpages_dirs = $self->{wa}->param('_session')->param('memberpages_dir');
#	$pagename = $self->fix_pagename($pagename, $memberpages_dirs);
#	
#	#we actually need to do a check here to make sure that the memerpage dir for the requested page is available to the user (it could be a denied dir and thats mainly what this is about)
#	my $dir_allowed = 0; #this wont turn true unless the dir of the requested page name is allowed.
#	$self->{wa}->ch_debug(["you've reqested this page: $pagename, and your dir access looks like", $memberpages_dirs]);
#	foreach my $dir (@$memberpages_dirs) {
#		if ($pagename =~ /^$dir->{directory}\//) {
#			if ($dir->{access_type} eq 'allow') {
#				$self->{wa}->ch_debug(["looks like your requested page $pagename falls under dir $dir->{directory} and youre allowed there"]);
#				$dir_allowed = 1;
#			}
#		}
#	}
#	
#	if ($dir_allowed) {
#		return $self->read_fix_return($pagename, $memberpages_dirs, $config->{log_pageviews});
#	} else {
#		#return $self->{wa}->redirect_pagename('/401.html'); #thought this'd work .. well it does, but b/c of the redirect the user can't use the back button properly.
#		#return $self->show_nonmember_page(); #thought this'd work .. well it does, but b/c of the redirect the user can't use the back button properly.
#		return $self->read_fix_return('/401_like.html', $memberpages_dirs, $config->{log_pageviews});
#	}
#}
#
#sub show_nonmember_page {
#	#this func is to process publicly viewable pages which link to members pages such that the links get converted into pagename params to the access control app.
#	my $self = shift;
#	my $pagename = shift;
#
#	$pagename = $self->fix_pagename($pagename);
#	return $self->read_fix_return($pagename);
#}
#
#sub fix_pagename {
#	my $self = shift;
#	my $pagename = shift;
#	my $memberpages_dirs = shift; #we'll pass memberpages dirs so if a bad pagename was specified we can drop them on index page of the first allowed directory.
#	
#	my $cgi = $self->{wa}->query();
#
#	#no pagename passed in? get it from the query (or pick a pagename failing that)
#	if (!$pagename) {
#		$pagename = $cgi->param('pagename');
#	}
#	$pagename = $cgi->unescape($pagename);
#
#	#if user tries to use .. or go to a file that isnt an html file, they'll just get fed the index.html
#		#now, a sneaky user could put something like pagename=..%2F..%2Fconf%2Faccess_control.conf and then suddely they are looking at the database uername and password!! very bad. so this is totally insecure ... lets tighten it up a little.
#	if ($pagename =~ /\.\./) {
#		$pagename = undef; 
#	}
#		
#	#pagename not ending in .html will have index.html added on to it -- that'll screw up requests to non-html pages and tack on index.html to paths that end like somedir/
#	if ($pagename !~ /\.html$/) {
#		$pagename = undef; 
#	}
#
#	#if there is no pagename set (becuase user didnt specify one, or user specified an illegal one thus having it obliterated), set it to index.html inside the first allowed dir.
#	if (!$pagename) {
#		foreach my $dir (@$memberpages_dirs) {
#			if ($dir->{access_type} eq 'allow') {
#				$pagename = $dir->{directory} . '/index.html';
#				last;
#			}
#		}
#	}
#	
#	return $pagename;
#}
#	
#sub read_fix_return {
#	my $self = shift;
#	my $pagename = shift;
#	my $pages_dirs = shift; #leave blank to start in httpdocs.
#	my $log_pageview = shift; #if we get this we need to proces _all_ links to go through the linklogger.
#
##since pagename will now include the dir, this next few lines are not neccessary.
##	my $filepath_startdir = '';
##	if ($startdir) {
##		$filepath_startdir = $startdir . '/'; #prep it to be stuck into the filepath.
##	}
##
##	my $filepath = $ENV{DOCUMENT_ROOT} . '/' . $filepath_startdir . $pagename; #may not have a startdir. no worries.
#	my $filepath = $ENV{DOCUMENT_ROOT} . '/' . $pagename;
#	
#	my $outhtml = '';
#	if (!-e $filepath) {
#		$outhtml .= "Error 404-like: $pagename not found \n";
#		$self->{wa}->ch_debug("program would like to read from nonexistant path: $filepath");
#	} else {
#		open INFILE, "<$filepath";
#		while (<INFILE>) {
#			$outhtml .= $_;
#		}
#		close INFILE;
#		
#		my $cgi = $self->{wa}->query();
#		#$self->{wa}->ch_debug(["going to change this startdir in the file $filepath", $startdir]);
#
#		my $script = $self->{wa}->param('_script_name');
#		foreach my $dir (@$pages_dirs) {
#			my $dirname = $dir->{directory};
#			#now fix the navigation links in the html. (replace something like "/members/foo.html" with "/cgi-bin/access_control.cgi?pagename=foo.html"
#			#$outhtml =~ s|[\"\']$startdir\/(.*?)[\"\']|"\"$script?pagename=" . ($1 ? $1 : 'index.html' ) . "\""|eg;
#			$outhtml =~ s|[\"\']\/$dirname\/(.*?)[\"\']|"\"$script?pagename=" . $cgi->escape("$dirname/" . ($1 ? $1 : 'index.html')) . "\""|eg;
#		}
#		#log pageview if required
#		if ($log_pageview) {
#			#stuff to log the user login
#			my $user_id = $self->{wa}->param('_session')->param('user_id');
#			my $user_obj = spApp::user->new($self->{wa});
#			$user_obj->log('pageview', $user_id, $pagename); #pass pagename for the 'detail' field.
#		}
#	}
#	
#	return $outhtml;
#}	
#
#sub linklogger {
#	my $self = shift;
#	my $lnk = shift;
#	my $cgi = $self->{wa}->query();
#	$lnk = $cgi->unescape($lnk);
#	$self->{wa}->header_type('redirect');
#	$self->{wa}->header_props(-url=>$lnk);
#	
#	print STDERR "user " . $self->{wa}->param('user_id') . " just clicked on $lnk\n";
#	return 1;
#}

1;