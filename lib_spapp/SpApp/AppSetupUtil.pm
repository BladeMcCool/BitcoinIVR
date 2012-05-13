package SpApp::AppSetupUtil;
use base "SpApp::StandaloneUtil";
use strict;
use FlatFile;

########## SETUP METHODS #############
sub _start_mode {	return 'install'; }

sub _runmode_map {
	my $self = shift;
	return {
		'install'   => {},
		'audit_vhosts' => {},
	}
}

sub install {
	my $self = shift;
	
	#usage:
		#all the list of args or
		#args_file=[path to a config file style args file] or
		#interactive
	
	######

	#find out what phase its for dev or prod or what (accept dev, prod, mod, test as legit values)
	#find out what config file name to make
	#find out what instance script names to make
	#find out to make admin script as well for that?
	#find out to make the vhost?
	#find out to make the db in the vhost?
	#find out a template db to load?

	my $args = $self->cgi_params_hashref();
	
	if ($args->{args_file}) {
		my %args_file_args = configAccessRead($args->{args_file});
		$args = { %args_file_args, %{$args} };
	}

	$self->dbg_print(['here with:', $args ]);
	my $phase = $args->{phase} ? $args->{phase} : $self->_interactive_input({ prompt => 'Development Phase?', validvals => ['dev','prod'], required => 1 });
	my $phase_longname = {
		'dev' => 'dev',
		'mod' => 'model'
	}->{$phase};
	
	my $config_file = $args->{config_file} ? $args->{config_file} : $self->_interactive_input({ prompt => 'Config file?', validvals => ['ac','fpm',]});
	my $instance_script = $args->{instance_script} ? $args->{instance_script} : $self->_interactive_input({ prompt => 'Instance Script to make?', validvals => ['ac','fpm',]});
	my $vhost_name = $args->{vhost_name} ? $args->{vhost_name} : $self->_interactive_input({ prompt => 'Vhost name?', required => 1 });

	my $vhost_user = $args->{vhost_user} ? $args->{vhost_user} : $self->_interactive_input({ prompt => 'Vhost user?', required => 1 });
	my $vhost_pass = $args->{vhost_pass} ? $args->{vhost_pass} : $self->_interactive_input({ prompt => 'Vhost pass?', required => 1 });

	my $db_name = $args->{db_name} ? $args->{db_name} : $self->_interactive_input({ prompt => 'Db name?', required => 0 });
	my $db_pass = undef;
	if ($db_name) {
		$db_pass = $args->{db_pass} ? $args->{db_pass} : $self->_interactive_input({ prompt => 'Db password?', required => 1 });
	}

	#$self->dbg_print(['here with:', $phase, $config_file ]);

	#fatal errors for input that is a little harder to trap and i dont feel like coding subroutine references and args and hooks to pass it all and call it.
	#some of this code is pretty old and just being lifted from for example sitepilot installer
	$vhost_user = substr($vhost_user, 0, 16);
	$vhost_pass = substr($vhost_pass, 0, 14);
	if (length($vhost_pass) < 5) { my $addon = (5 - length($vhost_pass)); $vhost_pass .= ('0' x $addon); }
	if ($vhost_pass =~ /$vhost_user/) { $self->_errstop('Password is not allowed to contain the username. Try again'); }

	my $vhosts_path = '/var/www/vhosts';
	my $vhost_path = $vhosts_path . '/' . $vhost_name;
	my $files = {
		'debuglog'                        => { touch => 1, own => 1 },
		'sessions'                        => { make => 1, own => 1 },
		'tmpl_cache_mp' . $phase          => { make => 1, own => 1 },
		'tmpl_mp' . $phase                => { sym => $vhosts_path . '/app' . $phase_longname . '.spiserver3.com/spapp/tmpl_spapp' },
		'httpdocs/app_includes_' . $phase => { sym => $vhosts_path . '/app' . $phase_longname . '.spiserver3.com/spapp/app_includes' },
		'httpdocs/app_images_' . $phase   => { sym => $vhosts_path . '/app' . $phase_longname . '.spiserver3.com/spapp/app_images' },
	};
	if (!-d $vhost_path) { die "oops vhost $vhost_name doesnt exist"; }
	print "Doing things with files ";
	foreach my $file (sort(keys(%$files))) {
		print ".";
		my $path = $vhost_path . '/' . $file;
		if ($files->{$file}->{touch}) {
			system("touch $path");
		}
		if ($files->{$file}->{make} && !-d $path) {
			mkdir($path) or die "failed to make $path: $!";
		}
		if ($files->{$file}->{own}) {
			system("chown -R $vhost_user: $path");
			system("chmod -R ug+rwx $path");
		}
		if ($files->{$file}->{sym} && !-l $path) {
			system("ln -s $files->{$file}->{sym} $path");
		}
	}
	print " Done\n";

	my $httpd_include_path = undef;
	my $vhost_conf_path    = undef;
	my $ports = {
		'dev' => { reg => 10080, ssl => 10443 },
		'mod' => { reg => 9080,  ssl => 9443 },
	};

	if ($phase eq 'dev' || $phase eq 'mod') {
		#check for a symlink in vhosts secondary.
		my $vhost_secondary_link = $vhosts_path . '_secondary/' . $vhost_name;
		print "Checking for secondary vhost symlink ...";
		if (!-l $vhost_secondary_link) {
			print " making it ...";
			system("ln -s $vhosts_path/$vhost_name $vhost_secondary_link");
		}
		print " Done\n";

		#check the main httpd include file for a line 
		print "Checking " . $phase_longname . "_httpd.include for the vhost include ...";
		my $httpd_conf_path = '/etc/httpd/conf/' . $phase_longname . '_httpd.include';
		my $found = 0;
		
		$httpd_include_path = "/var/www/vhosts_secondary/$vhost_name/conf/" . $phase_longname . "_httpd.include";
		$vhost_conf_path    = "/var/www/vhosts_secondary/$vhost_name/conf/" . $phase . "_vhost.conf";
		
		my $httpd_include_directive = "Include $httpd_include_path"; 
		open INFILE, "<$httpd_conf_path";
		while (<INFILE>) {
			if ($_ =~ /^$httpd_include_directive/) {
				$found = 1;
				print " found it ...";
				last;
			}
			#print "maybe $_ is not like $httpd_include_directive\n";
		}
		close INFILE;
		#if we didnt find it add it.
		if (!$found) {
			print " didnt find it, making it ...";
			open OUTFILE, ">>$httpd_conf_path";
			print OUTFILE $httpd_include_directive . "\n";
			close OUTFILE;
		}
		print " Done\n";
	
		#check for the $httpd_include_path file and make it if required.
		print "Making " . $phase_longname . "_httpd.include vhost conf file if required ...";
		if (!-e $httpd_include_path) {
			print " making it ...";
			my $t = $self->load_tmpl('appsetuputil/dev_httpd.include.tmpl');
			my $params = {
				phase          => $phase,
				phase_port     => $ports->{$phase}->{reg},
				phase_ssl_port => $ports->{$phase}->{ssl},
				vhost_name     => $vhost_name,
				vhost_user     => $vhost_user,
			};
			$self->dbg_print(['giving it params:', $params ]);
			$t->param($params);
			print "gonna write stome stuff to: $httpd_include_path";
			open OUTFILE, ">$httpd_include_path";
			print OUTFILE $t->output();
			close OUTFILE;
		}
		print " Done\n";
	} elsif ($phase eq 'prod') {
		$vhost_conf_path    = "/var/www/vhosts/$vhost_name/conf/vhost.conf";
	}
	
	#check for the $vhost_conf_path file and make it if required.
	print "Making vhost.conf if required ...";
	if (!-e $vhost_conf_path) {
		print " making it ...";
		my $t = $self->load_tmpl('appsetuputil/dev_vhost.conf.tmpl');
		my $params = {
			vhost_name => $vhost_name,
			vhost_user => $vhost_user,
		};
		$self->dbg_print(['giving it params:', $params ]);
		$t->param($params);
		print "gonna write stome stuff to: $vhost_conf_path";
		open OUTFILE, ">$vhost_conf_path";
		print OUTFILE $t->output();
		close OUTFILE;
	}
	print " Done\n";

	#gracefully restart apache
	print "Gracefully restarting apache ...";
	if ($phase eq 'dev') {
		system('dev_apachectl graceful');
	} elsif ($phase eq 'mod') {
		system('model_apachectl graceful');
	} elsif ($phase eq 'prod') {
		#this should make sure any vhost.conf we just made gets picked up as well (from old documentation notes) and probably from help files on those psa utils themselves.
		system("/usr/local/psa/admin/bin/websrvmng -a -v -u --vhost-name=$vhost_name");
	}	
	print " Done\n";
		
	#make vhost in plesk (borrow code from sitepilot installer)
	#add db to that vhost (research yay probably not too hard though)
	#if for dev:
		#make vhost_secondary symlink if needed
		#add vhost to the main dev_httpd.include file if neccessary

	#if for prod:
		#ensure presence of plain 'vhost.conf' with correct settings for PROD.
		#check httpd.include file for using vhost.conf and if it doesnt:
			#run that psa command that picks it up and uses it.
		#apachectl graceful
	# else
		#set up [phase]_httpd.include and [phase]_vhost.conf
		#[phase]_apachectl configtest (check output for stuff being ok)
		# and if its ok:
			#[phase]_apachectl graceful

	#make (if not already made):
		#debuglog file, 
		#template cache dir, 
		#symlink to the phase templates directory
		#symlink to the phase images and includes directories
	#own: debuglog, sessions, tmpl cache for the phase, 
	#permit group write: debuglog, sessions, tmpl cache for the phase
	
	#if doing a template db, load it
	#if doing config file set it up (do not overwrite existing)
	#if doing instance scripts do those (do not overwrite existing)
		#lets say its probably from a list of known instance scripts and also if the config filename is different from the instance script name then we should do the _config_file => thing in the pl script.
		
	
	
	return "Job Complete!!!!!!!\n";


}

sub _interactive_input {
	my $self = shift;
	my $args = shift;
	
	my $validvals = undef;
	if ($args->{validvals}) {
		$validvals = { map { $_ => 1 } @{$args->{validvals}} };
	}
	my $got_input = 0;
	my $final_input = undef;
	#keep getting input until we get input or we're done b/c we dont care.
	#$self->dbg_print(['here with args:', $args ]);
	while (!$got_input) {
		print $args->{prompt} . ": ";
		my $input = $self->_get_stdinput();
		if ($input) {
			$got_input = 1;
			if ($validvals && !$validvals->{$input}) {
				#$self->dbg_print(['decided that this isnt on the list.', $input, $validvals , $args]);
				$got_input = 0;
				#oops its invalid we unget this input thus needing to get more input. with a prompt again.
			}
		} else {
			if (!$args->{required}) { $got_input = 1 } #it wasnt required and user just pressed enter. null/undef is the input and we got it!
		}
		if ($got_input) {
			$final_input = $input;
		}
	}					
	return $final_input;
}

sub _get_stdinput {
	my $self = shift;
	my $args = shift;
	my $input = <STDIN>;
	chomp($input);
	return $input;
}

sub _errstop {
	my $self = shift;
  my $str = shift;
  print $str  . "\n";
  exit(1);
}

sub audit_vhosts {
	my $self = shift;
	my $dir = $self->param('_vhost_root');
	(my $all_vhost_dir = $dir) =~ s|(.*)/.*|$1|;
	my $logfile = 'statistics/logs/xferlog_regular';
	
	#get a list of all the domains directories in the vhosts dir that have a xferlog_regular log file.
	#my $list = [ grep {-d $_ && -e "$_/$logfile"} glob("$all_vhost_dir/*") ];
	my $list = [ '/home/httpd/vhosts/bmg.spiserver3.com-infected' ];
	
	$self->dbg_print([$list]);
	my $report = {};
	
#	foreach my $vhost_dir (@$list) {
#		foreach my $file ("$vhost_dir/$logfile", "$vhost_dir/$logfile.processed") {
#			open INFILE, "<$file" or die "$!";
#			my $last_file_seen = undef;
#			my $lcnt = 0;
#			while (my $line = <INFILE>) {
#				$lcnt++;
#				my @line_flds = split(/\s+/, $line);
#				#$self->dbg_print([\@line_flds]);
#				my $file_seen = $line_flds[8];
#				my $date_str = join(' ', @line_flds[4,1,2]);
#				if ($file_seen eq $last_file_seen) {
#					#print "$lcnt: yeah $file_seen is the same as $last_file_seen\n";
#					$report->{$vhost_dir}->{all}->{$date_str}++;
#				}
#				$last_file_seen = $file_seen;
#			}
#			close INFILE;
#		}
#	}
#	
#	my $notable = {};
#	foreach my $vhost (keys(%$report)) {
#		foreach my $date (keys(%{$report->{$vhost}->{all}})) {
#			if ($report->{$vhost}->{all}->{$date} > 10) {
#				$notable->{$vhost}->{$date} = $report->{$vhost}->{all}->{$date};
#			}
#		}
#	}
	my $evil_shit = 'galladance.com';
	foreach my $vhost_dir (@$list) {
		print "Looking in $vhost_dir ";
		my $vhost_audit_files = [];
		foreach my $type ('html','css','js','tmpl') {
			my @result = `find $vhost_dir -name '*.$type'`;
			foreach my $file (@result) {
				chomp($file);
				push(@$vhost_audit_files, $file);
				print ".";
			}
		}

		foreach my $audit_file (@$vhost_audit_files) {
			open INFILE, "<$audit_file";
			my $lcnt = 0;
			while (my $line = <INFILE>) {
				$lcnt++;
				if ($line =~ /$evil_shit/) {
					print "!";
					$report->{all}->{$vhost_dir}->{$audit_file}->{$lcnt} = 1;
					$report->{summary}->{$vhost_dir}++;
					(my $file_dir = $audit_file) =~ s|(.*)/.*|$1|;
					$report->{directories}->{$file_dir}++;
				}
			}
			close INFILE;
		}
		
		print "\n";
	}

	$self->dbg_print([ $report->{directories} ]);
	return "Job Complete\n\n";
}

1;