package SpApp::DbSchemaDumper;
use base "SpApp::StandaloneUtil";
use strict;

########## SETUP METHODS #############
sub _start_mode {	return 'schema_dumper'; }

sub _runmode_map {
	my $self = shift;
	return {
		'schema_dumper'   => {},
	}
}

sub schema_dumper {
	my $self = shift;
	
	my $db_params = {};

	my $dbinfo_files = {
		'dev'  => $self->config('dev_dbinfo_file'),
		'mod'  => $self->config('mod_dbinfo_file'),
		'prod' => $self->config('prod_dbinfo_file'),
	};
	
	my $app_db_names = {
		#abriachart => { dev  => 'abria_dev', mod => 'abria_mod', prod => 'abriachart_prod',	},
		#edu_r1     => { dev  => 'edudev',    mod => '', prod => 'cmcschool',	},
		#edu_r2     => { dev  => 'cmcfxdev',  mod => 'cmcfxmod',  prod => 'cmcfxprod',	},
		#cmcreg     => { dev  => 'cmcredev',  mod => 'cmccanmod', prod => 'cmccanprod',	},
		#lbg        => { dev  => 'lbg_dev',   mod => 'lbg_mod',   prod => 'lbg_prod',	},
		#jc_legacy_ac => { dev  => 'jc_ac_dev',   mod => undef,   prod => 'jc_ac',	},
		manportfolio => { dev  => 'man_dev',   mod => undef,   prod => 'man_prod',	},
	};
	
	my @dump_app_dbs = keys(%$app_db_names);
	if ($self->query()->param('dump_app')) {
		@dump_app_dbs = ( $self->query()->param('dump_app') );
	}
	$self->dbg_print(["going to dump schema's for these apps: ", \@dump_app_dbs]);
	print "Press ENTER to continue, ctrl-c to bail. \n\nAlso note, you might want to run this from a subdir since it will pollute the working directory with new schema.foo directories.";
	my $do_it = <STDIN>;
	
	foreach my $area ('dev', 'mod', 'prod') {
		my $dbinfo_file = $dbinfo_files->{$area};

		if (!-e $dbinfo_file || !-r $dbinfo_file) { die "path $dbinfo_file either does not exist or is unreadable."; }
		open INFILE, "<$dbinfo_file";
		my $found_block = 0;
		while (<INFILE>) {
			if ($_ =~ m|//APP_DB_PARAMS_BEGIN|) { $found_block = 1;	} #found the start ... flag it.
			if ($found_block && $_ =~ m|//APP_DB_PARAMS_END|) { last;	} #found the end, stop looking
			if ($found_block && $_ =~ m|^\s*//|) { next; } #skip commented-out lines. well at least of the // (at the beginning of the line) variety. /* foo */ would be ... umm stupidly complex.
			if ($found_block && $_ =~ /'user'\s*=>\s*'(.*?)'\s*,\s*'password'\s*=>\s*'(.*?)'/) { #process the block items.
				$db_params->{$area}->{$1} = {
					db_name => $1,
					db_user => $1,
					db_pass => $2,
					db_host => 'localhost:3306',
				};
				#$self->dbg_print(["get_db_params: pid $$ found info for db like $1, $2"]);
			}
		}
		close INFILE;

		#with all the db's, we can dump schemas for the area.
		my $out_dir = "db_schema." . $area;
		if (!-e $out_dir) {
			mkdir($out_dir);
		} elsif (!-w $out_dir) {
			die "File $out_dir exists but is not writable.";
		} elsif (!-d $out_dir) {
			die "File $out_dir exists but is not a directory.";
		}

		foreach my $app (@dump_app_dbs) {
			if (!$app_db_names->{$app}->{$area}) { next; } #skip the db for this area if we dont have one set up/listed.
			
			my $out_file = $out_dir . '/' . $app . '.sql';
			my $db_p = $db_params->{$area}->{$app_db_names->{$app}->{$area}};
			
			my $cmd = "mysqldump -u $db_p->{db_user} -p$db_p->{db_pass} --opt -d $db_p->{db_name} > $out_file";

			$self->dbg_print(["should produce $out_file with command and db_params :", $cmd, $db_p]);
			system($cmd);
			#print "Should produce $out_file\n";
		}

	}
	
	#$self->dbg_print(['discovered this db info:', $db_params ]);

	
		
	return "Job Complete\n";


}
1;