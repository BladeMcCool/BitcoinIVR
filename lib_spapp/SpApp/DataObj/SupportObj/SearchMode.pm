package SpApp::DataObj::SupportObj::SearchMode;
use base SpApp::DataObj::SupportObj;
use strict;

sub get_search_results {
	my $self = shift;
	my $args = shift;

	#I _think_ I want to clear any set record_id when doing this, because I can imagine its presence messing things up later.
	$self->{'do'}->clear_record_id();
	
	#make a searchform spec from the form and a clone of the fields.
	#establish the row selection SQL based on the standard form_spec fields we just cloned
	#prep the fields for searchform display / ordering 
	#perform the SQL and plug into the searchform-prepped fields.

	my $sf_spec_orig = $self->searchform_spec(undef, { no_query_options => 1 }); #no query options because we're gonna do that here, with stuff picked up from the cgi probably.
	#experiment: use a copy of the original sf_spec for the rest of this process, so as to preserve the original sf_spec's list of fields. we can filter each time on the copy here.
		#note, the whole take-ref-of-de-reffed-array thing like \@{$arrayref} ended up getting the same reference as the original arrayref! .. doh .. but the [ @$arrayref ] thing works to get a new arrayref with the original fieldrefs. raises question of whether similar \@$arrayref code in the formspec functions actually works as intended or not.
	my $sf_spec = {
		form   => $sf_spec_orig->{form},
		fields =>  [ @{$sf_spec_orig->{fields}} ],
	};
	
	$self->_search_field_query_options($sf_spec, $args); #this was added to set up easy field level flags for searchability options and to prepare limit_to lists for keywords and daterange, etc.
	my $select_sql    = $self->{sa}->_build_select_sql($sf_spec, $args);

	#some example args:
		#preselect_record_id => 123  #to put 'selected' => 1 in the result row that matches this value.
		#record_id => 123            # err but probably dont use this one here ## for fields_direct mode, means only 1 record should be obtained, and to put the db_value(s) right into the fields of the form_spec.
		#page_size => 20						 #example for 20 records per page. if left out, should do all records in one go.
		#show_page => 3							 #example to show page 3. should be supplied if page_size is supplied also

	$self->_standard_searchform_fields($sf_spec->{fields}); #i think this should be called just before the _perform_select (or right after will probably be fine too, just would mean extra stuff that will just be discarded would happen in _perform_select). and this should never be called before the _build_select (since the build select will need to include some extra shit)
	my $select_result = $self->{sa}->_perform_select($select_sql->{sql}, $select_sql->{bind_params}, $sf_spec, $args);
	$self->{do}->_augment_searchmode_values({ select_result => $select_result, select_args => $args }); #new hook/hack for 20080417 so that we can fudge some values for display when they are null, for IDL pricebook_category record discount_pct field to show the word 'default' (or something) when the field is undef/NULL
	##$self->{do}->param('last_search_args' => $args ); #2011 09 07 experiment ... the actual search args we dont seem to be storing in any convenient way!! (just spend 1 hr looking over code and debugging to come to this conclusion) ... so store them in the data object somewhere now! ### err wait i dont think this will work for what i want anyway because it wont come in here to set it until after it will have been needed anyway. gonna go do cgi hax then. fux.
	#additional templating things to add to select_result?
		#does this belong INSIDE _perform_select? I dont think so right now.
	my $record_id_param = $args->{record_id_param} ? $args->{record_id_param} : 'record_id'; #for templating ... to identify records with something other than record_id (because if everything was ALWAYS record_id we will have conflicts and problems!!)
	$select_result->{record_id_param} = $record_id_param;
	
	#any select results molestation hooks? what about paginations?
		#pagination is probably a controller-y thing. not sure about hooks yet. sounds good.

	#... keep the sf_spec in the object too in case we want to use it some more maybe.
	## shouldnt need to do this anymore as with new way of establishing sf_spec
	## $self->{sf_spec} = $sf_spec;

	#how about instead of just the select result, we add all those keys to the form and just return the form?
		#moved code which pulls all form keys into the results out into the controller post-search part. makes more sense.
		
	return $select_result;
	

}

sub paginate_search_results {
	my $self = shift;
	my $select_result_hash = shift;
	my $other_args = shift;
	
	#note, its pretty important that we get the F out of here if there is no page size set ... because that would imply we arent paginating.
		#and probably if theres no total pages number, there are no results, and so fuck doing pagination then too.
	if (!$select_result_hash->{page_size} || !$select_result_hash->{total_pages}) {
		return undef;
	}
	
	my $style = $other_args->{style} ? $other_args->{style} : 'google'; #default to Google style results. Would you expect any less?
	my $current_page = $select_result_hash->{current_page};
	my $total_pages  = $select_result_hash->{total_pages};
	my $page_size    = $select_result_hash->{page_size};

	if ($style eq 'google') {	
		
		#simple setup for the html template to show the list of pages with the current page de-activeated
		my $max_pages_to_show = 20; #jeeze -- Jay added 14000 customers and suddently the app is drawing links to 700 pages of customer screens! too many! lose most of em!
		my $pages_list = [];
		my $pg_start = 1; 
		my $showmax_thhreshold = 10; #if on a page higher than this we'll show links to the rest of the pages up to the maximum number of pages to show .. otherwise we'll just show up to this number of pages. also if we're on a page higher than this, then we want to make it so it shows like google.
	
		if (($current_page > $showmax_thhreshold) && ($total_pages >= $max_pages_to_show)) {
			$pg_start = ($current_page + 1) - $showmax_thhreshold;
		}
		if ((($total_pages - $pg_start) < $max_pages_to_show) && ($current_page > $max_pages_to_show)) {
			$pg_start = ($total_pages - $max_pages_to_show) + 1; #if we're near the end of the pageset, be sure to still show all the max_pages_to_show number of pages!
		}
		for (my $i = 0; $i < $max_pages_to_show; $i++) {
			$pages_list->[$i] = {};
			$pages_list->[$i]->{page_num} = $i+$pg_start;
			$pages_list->[$i]->{pages_list_current_page} = 1 if ($i+$pg_start == $current_page);
			if (($current_page < $showmax_thhreshold) && ($i + 1 == $showmax_thhreshold) && ($total_pages >= $max_pages_to_show)) {
				last; #ex, stop if next iteration would make info for a page after the max threshold when we're still looking at a page lower than the max threshold.
			}
			if (($i + $pg_start) == $total_pages) {
				last; #ex, stop if next iteration would make info for a page that does not exist.
			}
		}
	
		$select_result_hash->{first_page}        = ($current_page == 1) ? 0 : 1;                            #suppress first page link if current page is 1
		$select_result_hash->{prev_page}         = ($current_page == 1) ? 0 : $current_page - 1;            #suppress prev page link if current page is 1
		$select_result_hash->{next_page}         = ($current_page == $total_pages) ? 0 : $current_page + 1; #suppress next page link if current page is lastpage
		$select_result_hash->{last_page}         = ($current_page == $total_pages) ? 0 : $total_pages;      #suppress last page link if current page is lastpage
		$select_result_hash->{pages_list}        = $pages_list;
		$select_result_hash->{page_start_record} = (($current_page - 1) * $page_size) + 1;
		$select_result_hash->{page_end_record}   = $select_result_hash->{page_start_record} + scalar(@{$select_result_hash->{records}}) - 1;
		$select_result_hash->{multipage}         = ($total_pages > 1) ? 1 : 0

	}

	return $select_result_hash;
}


### no time right now to figure what I did wrong with this setup ... fucking shorcrap shit to do.
sub searchform_spec {
	my $self = shift;
	my $sf_spec = shift;
	my $other_args = shift;
	
	#$self->{wa}->dbg_print(['searchform_spec here with args:', $sf_spec, $other_args ]);
	
	#getter/setter for search form_spec.
	if ($sf_spec) {
		#set it
		$self->{'do'}->{sf_spec} = $sf_spec;
	} else {
		#get it ... if it doesnt exist, make it.
		$sf_spec = $self->{'do'}->{sf_spec};
		if (!$sf_spec) {
	 		$sf_spec = {
				form => $self->{'do'}->{form_spec}->{form}, 
				#fields => \@{$self->{'do'}->{form_spec}->{fields}}, #that should take a copy of the list of field references.
				fields => [ @{$self->{'do'}->{form_spec}->{fields}} ], #that should take a copy of the list of field references.
			};
			$self->{'do'}->{sf_spec} = $sf_spec;
			if (!$other_args->{no_query_options}) {
				#do the query options too .. without any args, but this is important for just showing a searchform. -- and a time we dont want query options is when we are searching a form and it will build the query options with args .. why do it twice right?
				$self->_search_field_query_options($sf_spec);
			}
			$self->{'do'}->{sf_specced} = 1;
			### can't call this here since if for example the pk field is not set as search_show_field that would cause it to be filtered out and then not included in the select statement, which would be like bad.
			### $self->_standard_searchform_fields($sf_spec->{fields});
		}
		return $sf_spec;
	}
}


sub _search_field_query_options {
	my $self = shift;
	my $form_spec = shift;
	my $other_args = shift;
	
	my $form   = $form_spec->{form};
	my $fields = $form_spec->{fields};

	#$self->ch_debug(['_search_field_query_options, with other_args like:', $other_args]);
	
	my $keyword_limiter = []; #to be a tmpl compatible list of param => dislpay name
	my $firstletter_limiter = []; #same idea as others
	my $daterange_limiter = []; #to be a tmpl compatible list of param => dislpay name
	my $dropdown_searches = [];
	foreach (@$fields) {
		#set up searchability flags

		#dont set up query options for fields that arent to be shown. (I think this makes sense)
			#actually this is cuasing me difficulty. turn off for now.
		#next if (!$_->{search_show_field});

		if ($_->{search_query_options}) {
#			my $query_options = $self->{'do'}->_json_attribs($_->{search_query_options});
			my $query_options = $_->{search_query_options};
			if ($query_options->{keyword}) { 
				$_->{search_keyword} = 1; 
				my $limiter_entry = { parameter_name => $_->{parameter_name}, display_name => $_->{search_display_name}};
				if ($other_args->{limit_keywords_to_field} && $other_args->{limit_keywords_to_field} eq $_->{parameter_name}) {
					$limiter_entry->{selected} = 1;
				}
				push(@$keyword_limiter, $limiter_entry);
				$form->{keyword_searchable} = 1;
			}
			if ($query_options->{daterange}) { 
				$_->{search_daterange} = 1; 
				### #what else do we need to do for limiter setup here for dateranges. ?? ##assuming shit as for keywords.
				my $limiter_entry = { parameter_name => $_->{parameter_name}, display_name => $_->{search_display_name}};
				if ($other_args->{limit_daterange_to_field} && $other_args->{limit_daterange_to_field} eq $_->{parameter_name}) {
					$limiter_entry->{selected} = 1;
				}
				push(@$daterange_limiter, $limiter_entry);
				$form->{daterange_searchable} = 1;
			}
			
			if ($query_options->{dropdown}) { 
				$_->{search_dropdown} = 1; 
				#this field can be searched by a dropdown. establish the listoptions.
				#add the result to a form level loop var called dropdown_searches as { parameter_name => param, display_name => search display name, listoptions => [ { standard listoption formatted arrayref of hashrefs } ] }
				#we're just doing the super-basic app_listoption limiters here, and the code is ripped and hacked from the _standard_editform_field_postprocessing -- so if and when advacned other-table listoptioning is conceived and implemented, could make similar coding over here.	
					#actually cuz I hate copy-pasting code so much I cleaned it up and broke it out. so that should make future coding better/easier.
				my $listoptions = [];
				my $lo_source = 'db';
				if (exists($self->{'do'}->_field_listoptions()->{$_->{parameter_name}})) { $lo_source = 'code'; } #if theres a key in the hashref we get...
				if ($lo_source eq 'db') {
					$listoptions = $self->{lo}->_get_field_listoptions_from_db($_->{sql_value_lookup}, $other_args->{dropdown_searches}->{$_->{parameter_name}}, { field_ref => $_ } ),
				} else {
					$listoptions = $self->{lo}->_get_field_listoptions_from_code($_, { selected_value => $other_args->{dropdown_searches}->{$_->{parameter_name}} });
				}

				my $dropdown_entry = {
					parameter_name => $_->{parameter_name},
					display_name   => $_->{search_display_name},
					listoptions    => $listoptions,
				};
				push(@$dropdown_searches, $dropdown_entry);
				$form->{dropdown_searchable} = 1;
			}

			if ($query_options->{firstletter}) { 
				$_->{search_firstletter} = 1; 
				my $limiter_entry = { parameter_name => $_->{parameter_name}, display_name => $_->{search_display_name}};
				if ($other_args->{limit_firstletter_to_field} && $other_args->{limit_firstletter_to_field} eq $_->{parameter_name}) {
					$limiter_entry->{selected} = 1;
				}
				push(@$firstletter_limiter, $limiter_entry);
				$form->{firstletter_searchable} = 1;
				if (!$form->{firstletter_letters}) {
					$form->{firstletter_letters} = [ map {{'letter' => $_}} ('A'..'Z') ];
				}
			}
			
		}
	}
	
	#if needed, save everything we did into the form. it will probably need to be carried forward to tmpl from there.
		#keyword and daterange limiters would only get shown if there was more than one of that type of searchable field in the form.
	if (scalar(@$keyword_limiter) > 1) {
		unshift(@$keyword_limiter, { parameter_name => undef, display_name => 'Please select ...'}); #stick an unselected item.
		$form->{keyword_limiter} = $keyword_limiter;
	}
	if (scalar(@$daterange_limiter) > 1) {
		unshift(@$daterange_limiter, { parameter_name => undef, display_name => 'Please select ...'}); #stick an unselected item.
		$form->{daterange_limiter} = $daterange_limiter;
	}
	if (scalar(@$firstletter_limiter) > 1) {
		unshift(@$firstletter_limiter, { parameter_name => undef, display_name => 'Please select ...'}); #stick an unselected item.
		$form->{firstletter_limiter} = $firstletter_limiter;
	}
	#dropdown searches are not like the keyword/daterange limiters -- show them if there are any of them at all. Also the null/please select entry would be handled in the _get_field_listoptions_from_db code.
	if (scalar(@$dropdown_searches)) {
		$form->{dropdown_searches} = $dropdown_searches;
		#also provide keys at top level for custom templates:
		foreach (@$dropdown_searches) {
			$form->{'dropdown_search_' . $_->{parameter_name}} = $_;
		}
	}

}

sub _standard_searchform_fields {
	my $self = shift;
	my $fields = shift;
	my $other_args = shift;
	
	#refer to comments in standard_editform_field_preprocessing to get an idea -- this version is for searchforms.
	
	$self->{fp}->_filter_fields($fields, {search_show_field => 1 });
## 2008 11 27 I think I want to only include fields in SEARCH FORMS that actually have a db_field_name.
##	$self->{fp}->_filter_fields($fields, {search_show_field => 1, db_field_name => 1});
## meh not ready to force this though. will continue to do search_show_field => 0 on those kinds of fields for now.

	foreach (@$fields) {
		if (!$_->{search_display_order} && $_->{sql_query_order}) { $_->{search_display_order} = $_->{sql_query_order}; }
	}

	@$fields = sort {
		$a->{search_display_order} <=> $b->{search_display_order}
	} @$fields;

	return 1;
}

1;