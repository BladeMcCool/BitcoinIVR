package SpApp::AdminBase;
use strict;
use base 'SpApp::Core';
#use base SpApp::MPRegUtil;
use JSON::XS;
use SpApp::Reporting;

#this is intended as a base class for Admin.pm modules of various apps, giving them specific admin-tied functionality, like standard modes for doing reporting. at least that case is the initiator of this thing anyway.

#sub _standard_modes {
#	my $self = shift;
#	my $args = shift;
#
#	my $common_std_modes = $self->SUPER::_standard_modes($args);
#	push(@$common_std_modes, (
#		'show_reports',
#		'show_excel_reports',
#	));
#	
#	return $common_std_modes;
#}

sub _client_runmode_map {
	my $self = shift;
	die "_client_runmode_map should be overridden now in all subclasses of AdminBase. for most it should just mean renaming existing _runmode_map func to _client_runmode_map.\n";
}

sub _runmode_map {
	my $self = shift;

	my $core_rms = {
		#'restricted_example' => {rm_sub=>'subname_can_differ', userlevel=>20, auth_subref=>\&_some_bool_returning_subref, rsf=>['has_passed_test1','has_passed_test2']}, #rm_sub is different from rm name, not public (no pub=>1 present), min userlevel 20, and even then still has to pass credential check in a user function called (in this case) _check_restricted_mode_credentials, and also has to have two (in this case) specific session flags set.
		'show_reports'        => {}, 
		'show_excel_reports'  => {}, 
	};
	
	my $client_rms = $self->_client_runmode_map();
	
	return { %$core_rms, %$client_rms };
}

sub _reports { return [{}]; } #subclass should implement and define arrayref of reporting-setup hashrefs

sub _spapp_setup {
	my $self = shift;
	
	#adding this 2009 04 03 to pick up json context. if this becomes Core stuff, probably stick it in Core::setup() function.
	my $cgi = $self->query();
	if ($cgi->param('json_context')) {
		$self->param('json_context' => JSON::XS::from_json($cgi->param('json_context')));
	}
}

sub show_reports {
	my $self = shift;
	my $args = shift;
	
	if (!$args) { $args = {}; }
		
	my $available_reports = $self->_reports();
	my $active_subset    = [ grep { $_->{active}; } @$available_reports ];
	my $id_to_reportinfo = { map { $_->{id} => $_ } @$active_subset };
	
	$self->ch_debug(['show_report: based on these defined available reports:', $available_reports ]);
	
	my $cgi = $self->query();
	my $selected_report = undef;
	my $excel_output    = $args->{excel_output};
	if ($cgi->param('report_id')) {
		$selected_report = $cgi->param('report_id');
	}
	## also, if we got an arg for selected_report use it (wanting to run a report from code/command line and not via cgi request)
	if ($args->{report_id}) {
		$selected_report = $args->{report_id};
	}		
	
#UNRELIABLE .... due to latent cgi params for even more stuff than i can think of ... better solution is to have a separate rm to engage this.
#	if ($cgi->param('excel_output')) {
#		$excel_output = $cgi->param('excel_output');
#		#buuut ... because we are sending excel as attachment, the page is not being refreshed, so a new click on 'search now' after doing excel output is still submitting the excel_output flag ... so make it exclusive, if we find  new_search then we can't do excel output.
#		if ($cgi->param('new_search')) { $excel_output = 0; }
#	}
	my $reportinfo = $id_to_reportinfo->{$selected_report};
	my $report_data = {};
	if ($reportinfo) {
		#we can show the criteria.
		#die "I know you selected a report";
		$reportinfo->{selected} = 1; #for templating to reselect item.
		my $sf_controller_params = { 
			for_screen => 'show_reports__' . $reportinfo->{id}, #give a unique screen name so that search params for one report dont mess with those of another.
			search_rm  => 'show_reports',
			buttons => [{
#				type => 'sf_runmode_with_params', #added a searchform version of this runmode_with_params customized button thing, just allows NOT setting the submit record_id (since the selected radio button should be the one) and also can make it check that a record is selected first.
#				display_value   => 'Send to Excel',
#				process_runmode => 'show_reports',
#				params => {'excel_output' => 1 },
				type => 'simpler_submit', #just does submit_form
				display_value   => 'SEND TO EXCEL',
				process_runmode => 'show_excel_reports',
			}],
		};
		
		#if doing excel output, override any pagination and page number request.
		if ($excel_output) {
			$sf_controller_params->{no_pagination} = 1;
			$sf_controller_params->{forced_search_params}->{current_page} = 1;
		}
		
		if ($reportinfo->{records_restrictor}) {
			$sf_controller_params->{forced_search_params}->{restrict} = $reportinfo->{records_restrictor};
		}
		if ($reportinfo->{records_restrictor_options}) {
			$sf_controller_params->{forced_search_params}->{restrict_options} = $reportinfo->{records_restrictor_options};
		}
		
		if ($args->{forced_search_params}) {
			if (!$sf_controller_params->{forced_search_params}) { $sf_controller_params->{forced_search_params} = {}; }
			#slap em in wholesale.
			$sf_controller_params->{forced_search_params} = { %{$sf_controller_params->{forced_search_params}}, %{$args->{forced_search_params}} }; #anything from the $args->{forced_search_params} will override.
		}			

		$self->ch_debug(['show_reports: going to call sf controller with this:', $sf_controller_params, 'and my args were:', $args ]);
		#die "stop and check sf_controller_params";

		my $excel_formats = {}; #not carrying this forward in perform_select, its really out of scope. going to build here based on whatever, and pass in to rendering routine.
		if ($reportinfo->{records_classname}) {
			$sf_controller_params->{data_obj} = ($reportinfo->{records_classname})->new($self);
			my $fields = $sf_controller_params->{data_obj}->searchform_spec()->{fields};
			foreach (@$fields) {
				$excel_formats->{$_->{parameter_name}} = {
					data_format => $_->{search_result_options}->{excel_format},
				};
				if ($_->{search_result_options}->{excel_value_from_disp}) {
					$excel_formats->{$_->{parameter_name}}->{value_source_override} = 'disp';
				}
			}
			
			#get the tmpl params for the searchform, with results if requested.
			$report_data = $self->generic_searchform_controller($sf_controller_params);
			$report_data->{excel_formats} = $excel_formats;
			$report_data->{suppress_standard_header} = $reportinfo->{suppress_standard_header};
			$report_data->{suppress_standard_footer} = $reportinfo->{suppress_standard_footer};
			
			#not being really happy with the capabilities of this reporting i'm throwing it out there that we might want various hooks and callbacks to get data better. gonna throw in something simple here to let us add stuff to the report data structure we got from the sf controller if we need to.
			if ($reportinfo->{data_augmentation_callback}) {
				$reportinfo->{data_augmentation_callback}->($self, { report_data => $report_data, reportinfo => $reportinfo });
			}

			#2008 09 19 experiment related_records_display type of header+detail idea.
			if ($reportinfo->{related_records_display}) {
				
				#so its a bit hackish here and wont be very efficient but we can get the related records data easily enough.
				#go over all the records (from 'records' arrayref) of the search results, and instantiate a single record version to call its relation functions on.
				#grab the relation data and stick it into a new key of the record hashref 'related_records' (related_records->[]
				#die "this report supposed to have related records!";

				my $rrd = $reportinfo->{related_records_display};
				if (ref($rrd) ne 'ARRAY') { $rrd = [ $rrd ] };

				foreach my $record (@{$report_data->{records}}) {
					my $dobj = ($reportinfo->{records_classname})->new($self, {record_id => $record->{record_id}});
				
					foreach my $relation_setup (@$rrd) {
						if ($relation_setup->{relationship}) {
							#get using a relationship
							my $sort_relations = undef;
							if ($relation_setup->{sort_relations}) {
								$sort_relations = $relation_setup->{sort_relations};
							}
							my $relationship_func = 'get_' . $relation_setup->{relationship};
							#get a proper search result hashref from the relationship, and slap it in wholesale.
							my $related_results = $dobj->$relationship_func({
								related_results       => 1, 
								record_id_param       => $relation_setup->{relation_name} . '_record_id',
								short_text            => 1,
								plaintext_html        => 1,
								sort_relations        => $sort_relations,
							});

							#add some extra stuff to the related results:
							$related_results->{relation_display_name} = $relation_setup->{relation_display_name};
							$related_results->{relation_name}         = $relation_setup->{relation_name};
							$related_results->{detail_record_colspan} = scalar(@{$record->{record_fields}}); #the purpose of this key is entirely for templating colspans for the cells which must contain the detail row's subtables.
							push(@{$record->{related_record_groups}}, $related_results);

						} else {
							#maybe other ways to do it later but not now.
							die "relationship key is required";
						}		
					}	#ends loop over all the relations we're doing	
				} #ends loop over the main set of records we needed to go over to fill related record data for.
			} #ends check of whether to do related_records_display

			$self->ch_debug(['show_reports: going to be doing related records display, here is our report data so far', $report_data]);
			
		} else {
			die "can only deal with records_classname at the moment"
		}
	
		#$report_data->{report_name}   = $reportinfo->{name};
	}

	if ($excel_output) {
		#cool, send that stuff out as excel.
		#$self->dbg_print(['show_reports: with excel_report we are sending it this data structure for reporting:', $report_data]);
		#die "stop until that is working right";

		my $reporting = SpApp::Reporting->new($self);
		my $rpt_scalar_ref = $reporting->excel_report({ report_data => $report_data, report_name => $reportinfo->{name}} );
		if ($args->{excel_data_only}) {
			#2008 09 23 adding way to just get data.
			return $rpt_scalar_ref;
		} else {
			return $reporting->send_excel_data($rpt_scalar_ref, { report_name => $reportinfo->{name} });
		}
	}

	my $tmpl_params = {
		%$report_data,
		reports_list    => $active_subset,
		selected_report => $selected_report, #trigger to show search options.
		form_label => 'Reports',
	};

	$self->ch_debug(['show_reports: having tmpl_params like: ', $tmpl_params ]);
	
	return $self->render_interface_tmpl(['general/admin_reports.tmpl'], $tmpl_params);

}

sub show_excel_reports {
	my $self = shift;
	return $self->show_reports({ excel_output => 1 }); #doing via separate rm so we dont screw ourselves up with latent cgi params to one single mode.
}

sub get_master_tmpl {
	my $self = shift;

	#this idea of using a master template for the entire application is in interesting .. will it work? 
		#sure it'll work -- just be sure to not use includes directly into it!

	my $master_tmpl_filename = "general/admin_master.tmpl"; 
	
	#anything that would change the name of master template would need to be coded here.
	#if ($gay) { $master_tmpl_filename = "now with gay.tmpl"; }

	#note that if we fail to load a master template here, our death will not be in a fancy error, because that fancy error template would not be renderable!

	my $t = $self->load_tmpl($master_tmpl_filename);
	$t->param(logged_in         => $self->get_auth()->is_logged_in());
	#$t->param(client_logo_image => $self->config('client_logo_image'));
	$t->param(client_logo_image => $self->_client_logo_image());
	
	#all admin master tmpl stuff should probably include variables for topnav menubar runmode list/active state etc stuff.
	my $menu_items = $self->_menu_items();
	$t->param(menu_items => $menu_items);
	$t->param(show_menu_bar => scalar(@$menu_items) );
	
	return $t;
}

#note, current default behavior is to NOT make use of a config option for this for admin. 
sub _client_logo_image { return undef; }
#however if you want to use it, just paste the version of the sub below into your subclass.
#sub _client_logo_image {
#	#override this in subclass (have it returning undef) if you want to have a config option for this set but for some reason suppress the using of it as the banner in the admin.
#	my $self = shift;
#	return $self->config('client_logo_image');
#}

sub _menu_items {
	my $self = shift;
	my $args = shift;

	#override this func I suppose if you need to do weird shit with active states.

	my $app_runmodes = $self->_runmode_map();
	my $userinfo = $self->get_userinfo();
	#grep for modes that actually have a userlevel set, 
	
#	my $mode_min_userlevels = { map { $_ => $app_runmodes->{$_}->{userlevel} } grep { $app_runmodes->{$_}->{userlevel} } keys(%$app_runmodes) };
#	$self->{wa}->ch_debug(['checking if authorized for runmode named $runmode, app runmodes are: ', $app_runmodes, 'mode minuserlevels is', $mode_min_userlevels]);
#die "stoppa";
#	if ($mode_min_userlevels->{$runmode} && ($userinfo->{userlevel} < $mode_min_userlevels->{$runmode})) {
#		$is_authed = 0;
#	}

	my $mm_setup = $self->_menu_setup();
	my $active_mode = $self->get_current_runmode();
	my $mm_final = [];
	foreach my $item (@$mm_setup) {
		if (!$item->{mm_name}) { $item->{mm_name} = $item->{name}; }
		if (!$item->{mm_icon}) { $item->{mm_icon} = $item->{icon}; }
		foreach my $mode (@{$item->{active_runmodes}}) {
			if ($mode eq $active_mode) { 
				$item->{active} = 1; 
				$item->{menubar_rm_text} = $item->{runmode_text}->{$active_mode};
			}
		}
		my $keep = 1;
		if ($args->{for_mm} && $item->{mm_hide}) { $keep = 0; };

		#also toss out menu items for being ineligible.
		if ($app_runmodes->{$item->{runmode}}->{userlevel} && ($userinfo->{userlevel} < $app_runmodes->{$item->{runmode}}->{userlevel})) {
			$keep = 0;
		}

		push(@$mm_final, $item) if ($keep);
	}
	return $mm_final;
}
sub _menu_setup {
	my $self = shift;
	return [];
}

sub main_menu {
	my $self = shift;
	my $args = shift;
	
	my $tmpl_params = { 'suppres_mm_link' => 1, form_label => 'Main Menu', mm_menu_items => $self->_menu_items({for_mm => 1})};
	return $self->render_interface_tmpl([$self->_main_menu_template()], $tmpl_params);
}
sub _main_menu_template {
	my $self = shift;
	return 'general/main_menu.tmpl'; #this is our automatic rendering main menu set up to work with _menu_items vars
}

1;