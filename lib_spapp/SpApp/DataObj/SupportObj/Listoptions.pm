package SpApp::DataObj::SupportObj::Listoptions;
use base SpApp::DataObj::SupportObj;
use strict;
use JSON::XS;

use vars qw {$_LISTOPTION_CACHE $_STRINGS_CACHE}; #gonna try to cache listoptions to reduce the amount of SQL that has to get run. This may end up a) not working right or b) just be a bad idea for memory usage or some other mod_perly reason.
$_LISTOPTION_CACHE = {}; #this is DEFINITELY a package var. which I truly want. no data object should have to look up list options that have already been looked up by another data object!
$_STRINGS_CACHE    = {}; #same, this is mainly added for "Please Select" in multilang .. so we dont ask db for it every damn time. Unless we are not caching listoptions either, then we'll wipe this every time too.

use constant FORMCONTROL_DB => 1;
use constant DATA_DB        => 2;

sub _complex_custom_field_edit_listoptions {
	my $self = shift;
	my $fieldref = shift;
	my $args = shift;

	#this'll default to looking at edit_value(s)
	my $inspect = 'edit';
	if ($args->{inspect}) { $inspect = $args->{inspect}; }
	my $value_attrib = $inspect . '_value';

	#2007 01 30, adding this code to deal with all the setup variables for a custom field type that I'm calling COMBO_RADIO_CONTROLLED_FIELD (err hopefully change that to REMOTE_CONTROLLED_FIELD (rcf))
	if ($fieldref->{edit_fieldtype} =~ /^COMBO_RADIO_CONTROLLED_FIELD/) {
		#control rows come from the values_table for the radio button (top level field). Its also where the radio option text comes from.
			#not sure why I did this but table structure is a little funky. "id" becomes "value" and "name" becomes "display_name". Lets just make it a _little_ smarter and say that if threre _IS_ a display name, use that.
		my $edit_options = $fieldref->{edit_options};
		if (!$edit_options) {
			die "trying to set up listoptions for a COMBO_RADIO_CONTROLLED_FIELD and its subfields, but no edit_options ... thats no good.";
		}
		my $subfields = $fieldref->{subfields};
	
		my $dbh = $self->{'do'}->_get_data_dbh();
		my $control_sql = 'SELECT * FROM ' . $edit_options->{values_table} . ' WHERE disabled != 1 ORDER BY display_order ASC';
		my $control_rows = $dbh->selectall_arrayref($control_sql, {Slice=>{}}, ());
		#note in this context sub_select means a subfield that is a select field. we have to get the options for them.
		my $sub_select_values_sql = 'SELECT * FROM ' . $subfields->{'select'}->{values_table} . ' WHERE ' . $subfields->{'select'}->{values_table_fk_field} . ' = ? AND disabled != 1 ORDER BY display_order ASC';
		my $sub_select_values_sth = $dbh->prepare($sub_select_values_sql);

		#get the selected values ... should work b/c the sql query (or retry) should have been looking at and plugging things into a subfield reference
		my $radio_selected_value  = $fieldref->{$value_attrib};
		my $select_selected_value = $fieldref->{subfields}->{'select'}->{$value_attrib};
		my $text_value            = $fieldref->{subfields}->{'text'}->{$value_attrib};
		my $control_type          = $edit_options->{control_type} ? $edit_options->{control_type} : 'radio'; #default to radio controlled. doing this because Steve wants to be able to do select-controlled now as well/instead.

		#there can be only one text value ... no matter which 'text' type controlling value is used thats just nice to know, meta for the text in that case.
		if ($text_value) { $fieldref->{'rcf_text_value_disp'} = $text_value; }

		my $multi_lang = $self->{'do'}->form_spec()->{form}->{multi_lang};
		my $app_lang = $self->{wa}->param('lang');
		my $multi_lang_strings = {};
		my $subselect_blankitem_stringname = $subfields->{'select'}->{blankitem_stringname};
#		if ($multi_lang) {
#			my $stringnames = [ map { $edit_options->{values_table} . '__' . $_->{id} } @$control_rows ];
#
#			#also if we got a blankitem_stringname, get those strings too.
#			if ($subselect_blankitem_stringname) {
#				push(@$stringnames, ('rcf_subselect_blankitem_prelabel__' . $subselect_blankitem_stringname, 'rcf_subselect_blankitem_label__' . $subselect_blankitem_stringname));
#			}
#			#blankitem for control field ... just use standard one
#			push(@$stringnames, 'std_listoption__blankitem_label');
#
#			$multi_lang_dispvals = $self->{wa}->get_strings($stringnames);
#		}

		my $preferred_disp_fld = 'display_name';
		my $fallback_disp_fld  = 'name';
		if ($multi_lang) {
			my $stringnames = ['std_listoption__blankitem_label'];
			#also if we got a blankitem_stringname, get those strings too.
			if ($subselect_blankitem_stringname) {
				push(@$stringnames, ('rcf_subselect_blankitem_prelabel__' . $subselect_blankitem_stringname, 'rcf_subselect_blankitem_label__' . $subselect_blankitem_stringname));
			}
			$multi_lang_strings = $self->{wa}->get_strings($stringnames);
			
			if ($app_lang ne 'en') {
				$preferred_disp_fld .= '_' . $app_lang;
				$fallback_disp_fld  .= '_' . $app_lang;
			}
		}
		
		foreach my $row (@$control_rows) {
			#add standardized keys for the radio button rendering if the db row did not provide them directly.
			$row->{value}           = $row->{value}        ? $row->{value}        : $row->{id};
			$row->{display_name}    = $row->{$preferred_disp_fld} ? $row->{$preferred_disp_fld} : $row->{$fallback_disp_fld};

			#establish the label for the blank select item ... so it can say "select $foo $bar ... " $foo comes from the display_name of the radio button, but here we're defining $bar ... eg: "Select Tabernac($foo) Emporium($bar)"
			$row->{blankitem_prelabel} = $row->{blankitem_prelabel} ? $row->{blankitem_prelabel} : $fieldref->{subfields}->{'select'}->{blankitem_prelabel};
			$row->{blankitem_label}    = $row->{blankitem_label}    ? $row->{blankitem_label}    : $fieldref->{subfields}->{'select'}->{blankitem_label};
			#if a stringname is provided for blankitem_prelabel (the 'Select' in 'Select bozo promotion') and/or blankitem_label (the 'promotion' in 'Select bozo promotion') then use it.
				#just look for blankitem_stringname foo .... that means look up rcf_subselect_blankitem_prelabel__foo and rcf_subselect_blankitem_label__foo ... and use any that we get or stick with what we have.
				#strings gathered above with the multi_lang_strings gathering.
			
			#override with multi-lang strings if doing that.
			if ($multi_lang) {
				#blankitem label stuff for subfield too
				if ($subselect_blankitem_stringname && $multi_lang_strings->{'rcf_subselect_blankitem_prelabel__' . $subselect_blankitem_stringname}) {
					$row->{blankitem_prelabel} = $multi_lang_strings->{'rcf_subselect_blankitem_prelabel__' . $subselect_blankitem_stringname};
				} 
				if ($subselect_blankitem_stringname && $multi_lang_strings->{'rcf_subselect_blankitem_label__' . $subselect_blankitem_stringname}) {
					$row->{blankitem_label} = $multi_lang_strings->{'rcf_subselect_blankitem_label__' . $subselect_blankitem_stringname};
				} 
			}

			if ($row->{value} eq $radio_selected_value) {	$fieldref->{'rcf_control_value_disp'} = $row->{display_name};	}
			
			if ($row->{type} eq 'select') {
				$sub_select_values_sth->execute($row->{value});
				my $select_entries = $sub_select_values_sth->fetchall_arrayref({});
				$row->{select_entries} = [ map {
					$_->{value}          = $_->{value}        ? $_->{value}        : $_->{id};
					$_->{display_name}   = $_->{$preferred_disp_fld} ? $_->{$preferred_disp_fld} : $_->{$fallback_disp_fld};
					if ($_->{value} eq $select_selected_value) { $fieldref->{'rcf_select_value_disp'} = $_->{display_name}; }
					$_;
				} @$select_entries ];

#				#subfield multi lang override.... (hack)
#				if ($multi_lang) {
#					my $subfield_stringnames = [ map { $subfields->{'select'}->{values_table} . '__' . $_->{id} } @{$row->{select_entries}} ];
#					my $multi_lang_subfield_dispvals = $self->{wa}->get_strings($subfield_stringnames);
#
#					#fix the display names for the items in the select box.
#					foreach (@{$row->{select_entries}}) {
#						$_->{display_name} = $multi_lang_subfield_dispvals->{$subfields->{'select'}->{values_table} . '__' . $_->{id}};
#						#and correct the rcf_select_value_disp ....
#						if ($_->{value} eq $select_selected_value) { $fieldref->{'rcf_select_value_disp'} = $_->{display_name}; }
#					}
#				}

			} 
		}
		#build this up for easy access to the info from the js, and in validate to know exactly what fields have to have a value.
		my $value_to_type_map = { map {$_->{value} => $_->{type}} @$control_rows };

		#also copy value from $value_attrib to the 'edit_value' key of the fieldref. 
			#no wait, I should probably be doing that in _standard_editform_field_postprocessing ... maybe just make that func loop over merged fields.
		
		$fieldref->{rcf_control} = { 
			control               => $control_rows, 
			blankitem_label       => $multi_lang ? $multi_lang_strings->{std_listoption__blankitem_label} : 'Please Select ...',
			value_to_type_map     => $value_to_type_map,

			select_parameter_name => $fieldref->{subfields}->{'select'}->{parameter_name},
			text_parameter_name   => $fieldref->{subfields}->{'text'}->{parameter_name},

			radio_selected_value  => $radio_selected_value ? $radio_selected_value : undef,
			select_selected_value => $select_selected_value ? $select_selected_value : undef,
			text_value            => $text_value ? $text_value : undef,
			
			$control_type . 'controlled' => 1, #b/c steve wants to be able to change the controlling radio buttons to a controlling select box. ugh.
			control_type                 => $control_type,
		};

		$self->ch_debug(['_complex_custom_field_edit_listoptions: control field blankitem label is like: ', $fieldref->{rcf_control}->{blankitem_label} ]);
		#$fieldref->{rcf_control_json} = JSON::Syck::Dump($fieldref->{rcf_control});
		#switching to JSON::XS b/c it is supposed to be even faster and more correct than JSON::Syck
		$fieldref->{rcf_control_json} = Encode::decode('utf8', JSON::XS::encode_json($fieldref->{rcf_control}));

	} #well, that takes care of a COMBO_RADIO_CONTROLLED_FIELD! REMOTE_CONTROLLED_FIELD would be better name.
}

sub _get_field_listoptions_from_db {
	#2007 03 06 - renamed this from just _get_field_listoptions to _get_field_listoptions_from_db ... i plan to add _get_field_listoptions_from_code shortly.
		#also, this function needs cleanup, especially in how it is called. should just call with a fieldref and args, to override parameter name via something in args or something (for the searchform query options usage) and otherwise can get everything from the fieldref (for _standard_editform_field_postprocessing usage)
	my $self = shift;
	my $sql_value_lookup = shift;
	my $selected_value   = shift; #a listoption with this value would become the selected listoption. And then mutlivalues what duh??!?! stupid. doh!
	my $other_args = shift; #for more control later. like giving us an actual field_ref or something! grr.

#	my $dbh = $self->get_dbh(); #may not even end up needing this if everything is cached this time around. methinks.
	my $listoption_source = undef;

	my $listoptions = [];
	my $listoption_sql;
	my @listoption_binds;
	my $listoptions_cached = 0;
	my $ensure_heading_entry = 1; #might one day want to have a way to turn this off. ##update: yeah that day came Nov 15 2006 when I want radio buttons that do NOT include a "please select ..." radio button (which having that is retarded)!!
	my $cache_key = undef; #so we know where to get them from or set them to.
	my $field_ref = $other_args->{field_ref};
	
	my $cache_listoptions = !$self->{wa}->config('dont_cache_db_listoptions'); #needed a quick way to disable listoption caching - so if config file caching is off, we can just quickly add this to a config file to disable listoption caching.
	my $app_id   = $self->{wa}->param('_app_id');
	my $app_lang = $self->{wa}->param('lang');
	if(!$cache_listoptions) {
		$_LISTOPTION_CACHE->{$app_id} = {};
		$_STRINGS_CACHE->{$app_id} = {};
	}
	
	#2007 09 11 adding multi language mode for listoptions (alo ones anyway). pull from display_value_XX field.
	my $multi_lang = $self->{'do'}->form_spec()->{form}->{multi_lang} ? 1 : 0; 
	my $display_value_field = 'display_value';
	if ($multi_lang) { 
		if (!$app_lang) { die "No $app_lang in multi_lang mode"; }
		$display_value_field .= '_' . $app_lang; #value field is which field of the selected lo row will be used for the final display_value (might just be display_value! or might be display_value_en or display_value_zh for example)
		
		#do we also need to get/cache the blankitem text for select dropdowns that, in non multilang, is hardcoded as 'Please Select ...' down below?
		if (!$_STRINGS_CACHE->{$app_id}->{$app_lang}->{blankitem_label}) {
			my $strings = $self->{wa}->get_strings('std_listoption__blankitem_label');
			#hrmm .. strings cache ... lang->stringname or stringname->lang? well .. change it if it seems stupid.
			$_STRINGS_CACHE->{$app_id}->{$app_lang}->{blankitem_label} = $strings->{std_listoption__blankitem_label};
		}
	}
	$self->ch_debug(['_get_field_listoptions_from_db: here to get listoptions with args:', [$sql_value_lookup, $selected_value, $other_args ] ]);
	
	if ($sql_value_lookup) {
		
		if ($sql_value_lookup =~ /^(\S*)\.(\S*)$/) {
		
			my $value_tablename = $1; #ex: location
			my $value_fieldname = $2; #ex: name

			##THIS EXAMPLE CODE HERE handles other table lookups in the _build_select_sql func ... for now I want to implement at least the basic one without sql_value_lookup_key
			###set criteria on which to do the join
			##if ($_->{sql_value_lookup_key}) {
			##	#good for many-to-many joins - or for other times when we need to be more explicit.
			##		#so that we can select this_other_table.displayvalue by doing a LEFT JOIN this_other_table ON somethingspecifc = $_->{db_field_name}
			##	$join_onclause = $_->{sql_value_lookup_key} . " = " . $_->{db_field_name}; #ex: scheduledevent_attendee.scheduledevent_id = scheduledevent.id
			##} else {
			##	$join_onclause = $value_tablename . '.id = ' . $_->{db_field_name}; #ex: location.id = scheduledevent.location_id
			##}
			
			#basic atttmpt (not handling sql_value_lookup_key yet)
				#also in future maybe do caching of these too.
				#one day this will have to be enhanced for listoption ordering by some criteria, formatting, creating a display string out of multiple fields, etc.
				#the SQL we make here has to have the end result of the string we want to SEE being called "display_value", and the value that will be STORED being called "value"

			#i have found almost immediately after implementing the ability to have lookup values from some other table, that there are records in that other table that I DO NOT want to see ... so I must have a way to code some options to the query. For starters, lets make use of the edit_options field. It is supposed to be used as an attrib formatted string ... so .. use it?
				#thinking about changing this to do the de-json-ing at the time the fields are loaded. only thinking about this because with runtime added fields via _add_editform_fields I dont want to specify field edit options in json ... i'd rather do them in perl hashrefs like what will come out of the json ... which means that db-specced fields should have their json attribs already deserialized.
				#better not do that right now though. this is one of the only places that uses it and the de-json code now being used is Syck and fast.
			#my $edit_options = $self->{'do'}->_json_attribs($other_args->{edit_options});
			my $edit_options = $field_ref->{edit_options};

			if ($other_args->{sql_value_lookup_key}) { #this is not implemented, nothing will yet pass this, and it possibly should be passed differently at that time anyways. Just coding a hook for it here so I can kind of know what I was thinking.
			} else {
				@listoption_binds = (); #nothing to bind yet for this type.

				my $lo_select = "SELECT $value_tablename.$value_fieldname AS $display_value_field, $value_tablename.id AS value FROM $value_tablename";
				my $lo_where = '';
				if ($edit_options->{lo_where}) {
					$lo_where = 'WHERE ' . $edit_options->{lo_where};
					#eventually I imagine I will handle binds as well -- allow placeholder ni the where clause and pass a bind in somehow, either defined in the same edit_options attribute list, or ... ?? well I imagine I'll need to pass some value in at some point. figure that out later.
				}
				my $lo_orderby = "ORDER BY $value_tablename.$value_fieldname ASC";
				$listoption_sql = join(' ', ($lo_select, $lo_where, $lo_orderby));
				
			}

			#going to say that table.field lookups always come from the data_db (which outside of the FormTool is probably the same db as the formcontrol_db but you never know)
			$listoption_source = DATA_DB;
			
			$self->ch_debug(['_get_field_listoptions_from_db: doing custom listoptions with SQL like:', $listoption_sql, 'edit_options were:', $edit_options]);
		
		} else {
			#alo lookup. -- $sql_value_lookup names the parameter.
			$cache_key = $sql_value_lookup;
			if ($multi_lang) { $cache_key .= '__' . $app_lang; } #cache options separately for each language in that case
			if (exists($_LISTOPTION_CACHE->{$app_id}->{$cache_key})) { 
				$listoptions_cached = 1; 
				#print STDERR "_get_field_listoptions_from_db: alo listoption lookup WONT be going to query the db for listoptions named by parameter $sql_value_lookup because that has already been done\n";
				$self->{wa}->debuglog("_get_field_listoptions_from_db: alo listoption lookup WONT be going to query the db for listoptions named by parameter $sql_value_lookup using cache key $cache_key because that has already been done");
				$self->{'do'}->ch_debug(["_get_field_listoptions_from_db: alo listoption lookup WONT be going to query the db for listoptions named by parameter $sql_value_lookup using cache key $cache_key because that has already been done"]);
			} else {
				#print STDERR "_get_field_listoptions_from_db: alo listoption lookup WILL be going to query the db for listoptions named by parameter $sql_value_lookup because that has NOT already been done\n";
				$self->{wa}->debuglog("_get_field_listoptions_from_db: alo listoption lookup WILL be going to query the db for listoptions named by parameter $sql_value_lookup using cache key $cache_key because that has NOT already been done");
				$listoption_sql = "SELECT alo.$display_value_field, alo.value, alo.`separator` FROM app_listoption alo WHERE alo.parameter_name = ? AND disabled != 1 ORDER BY alo.display_order ASC";
				@listoption_binds = ($sql_value_lookup); #### remember, we're setting the binds HERE and not below because we are going to later code for the ability (a few lines up) to have SQL and binds for some more complex, other-table listoptions.
				$self->{'do'}->ch_debug(['_get_field_listoptions_from_db: querying for listoptions with this sql and binds:', $listoption_sql, \@listoption_binds]);
			}
			
			#going to say that alo lookups always come from the formcontrol_db (which outside of the FormTool is probably the same db as the data_db but you never know)
			$listoption_source = FORMCONTROL_DB;
		}

		if (!$listoptions_cached) {

			#run the listoption query only when neccessary.
			my $dbh = ($listoption_source == FORMCONTROL_DB) ? $self->{'do'}->_get_formcontrol_dbh() : 
								($listoption_source == DATA_DB)        ? $self->{'do'}->_get_data_dbh()        : die "Bad listoption source: $listoption_source";
								
			my $listoption_sth = $dbh->prepare($listoption_sql) or die $dbh->errstr;
			$listoption_sth->execute(@listoption_binds)  or die $dbh->errstr . " with SQL of: $listoption_sql\n";
			my $listoption_row;
			my @lo_queried = ();
			my $null_value_heading_entry = 0; #i think I want list options to have a first item that says "Please select ..." (unless told not to?) .. and that way a formfield with no default value would preselect this item.
			while ($listoption_row = $listoption_sth->fetchrow_hashref) {

				if ($multi_lang) {
					#dont use the display_value field as-is when doing multi_lang ... get from the correct field.
					$listoption_row->{display_value} = $listoption_row->{$display_value_field}; 
				}					
				
				if ($listoption_row->{separator}) { 
					$listoption_row->{value} = undef; #lose any value off separator. chooseing a separator CANNOT be allowed to pass field_required validate rules.
					if (!$listoption_row->{display_value}) { #set a default display value for a separator that does not have one ... b/c I dont want to have to put a dispaly value sometimes, I just want it to be a freakin separator!!
						$listoption_row->{display_value} = "--------------------";
					}
				} 
				#2008 05 13 fixing small bug with the line below so we now check if the $listoption_row->{value} is not defined rather than just nontrue before deciding we've hit a null_value_heading_entry.
				if (!$listoption_row->{separator} && !defined($listoption_row->{value})) { $null_value_heading_entry = 1; } #that is to say, its got a null value and its not a separator. it can be the list heading item.
				#i really dont like doing this but I can't seem to get the ...notation in HTC to work to access the parameter name for radio button field that are rendered within a loop ... so I seem to have to code it in here. this feature of HTC is going to increasingly be wanted by me. ### ok not doing this gonna turn on global vars instead. docs say global vars is best for speed anyhow.
					#whoa -- whats fucked up is I tried so many ways and couldnt get the HTC functionality for ...noation OR bloodly global vars to work it just doesnt! I had some weirdness where sometims I could get the first iteration of the tmpl_loop to draw it but subsequent ones just wont. fucking gay and pisses me off. this should get the job done:
					#i tried to do a proof of concept showing the fuckup but it worked, sonofabitch! I do think that this is a serious issue that needs to be resolved and I should allocate a day to figure it out.
					# bla bla bla there was a bug in HTC which I helped point out to Tina (maintainer) and she got it fixed. Tina rox. See notes about changelog for version 0.67 if you ever care what it was -- something about global_vars not being passed around right.
				push(@lo_queried, $listoption_row);
				#print STDERR "_get_field_listoptions_from_db: got a listoption row with display value like: " . $listoption_row->{display_value} . "\n";
			}
			
			#any reasons NOT to forcibly include a heading entry of "Please Select ..." ?
				#how about its a stupid thing to have on radio buttons! (and checkboxes)
			my $no_forced_heading_entry = {
				'SINGLESELECT_RADIO'    => 1,
				'SINGLESELECT_CHECKBOX' => 1,
				'MULTISELECT_CHECKBOX'  => 1,
			};
			#if ('doh i dont have field reference here so I dont even know the type!') {}
#			if ($field_ref && $field_ref->{edit_fieldtype} eq 'SINGLESELECT_RADIO') {
			if ($field_ref && ( $no_forced_heading_entry->{$field_ref->{edit_fieldtype}} || $field_ref->{edit_options}->{no_forced_heading_entry} )) {
				$ensure_heading_entry = 0;
			}
			
			#2009 03 30 we're doing some funky custom stuff for BMG and Jay has hardcoded a 'default null item' whatever .. in the template .. so i want to be able to literally be able to just turn this off for this one.
				#ew @ having to code if ($field_ref &&  ... due to the way args in this func were handled .. also note i just change line in SearchMode.pm that calls this func to pass in field ref. yay.
			if ($field_ref && $field_ref->{search_query_options}->{skip_dropdown_null_item}) {
				$ensure_heading_entry = 0;
			}

			#$self->ch_debug(['_get_field_listoptions_from_db: stuffs:', $field_ref, $ensure_heading_entry, $null_value_heading_entry ]);
			
			if (!$null_value_heading_entry && $ensure_heading_entry) {
				my $blankitem_label = $multi_lang ? $_STRINGS_CACHE->{$app_id}->{$app_lang}->{blankitem_label} : "Please Select ...";
				$self->{wa}->ch_debug(['_get_field_listoptions_from_db: should be using blankitem lable of:', $blankitem_label, 'status of multi_lang:', $multi_lang, 'and $_STRINGS_CACHE for our app_id looks like:', $_STRINGS_CACHE->{$app_id} ]);
				unshift(@lo_queried, { display_value => $blankitem_label, value => undef } );
			}

			#$self->ch_debug(['_get_field_listoptions_from_db: @lo_queried:', \@lo_queried ]);
			#die "here - before caching it";

			$_LISTOPTION_CACHE->{$app_id}->{$cache_key} = \@lo_queried;
		}

		#at this point the listoptions WILL be in the cache regardless .. so use what is there now. using clone because I know that if I dont I'll end up with VERY fucked up problems related to shared references with mod_perl (when I start altering them to flag items as being selected for example)
		$listoptions = Clone::clone($_LISTOPTION_CACHE->{$app_id}->{$cache_key});

		#select the selected.
		$self->_select_listoptions({
			listoptions    => $listoptions,
			selected_value => $selected_value,
		});
		
	} #end check on whether we have to deal with lookup values.
	
	$self->ch_debug(['_get_field_listoptions_from_db: returning listoptions like: ', $listoptions]);

	return $listoptions;
}

sub _get_field_listoptions_from_code {
	my $self = shift;
	my $fieldref = shift;
	my $args = shift;

	#calling function should know whether to call this one (_get_field_listoptions_from_code) or the other one (_get_field_listoptions_from_db)

	#double check that there is a sub there.
  my $listoption_sub = $self->{'do'}->_field_listoptions()->{$_->{parameter_name}};
  unless (defined($listoption_sub)) { #good stuff on dynamic subs at http://www252.pair.com/comdog/mastering_perl/Chapters/09.dynamic_subroutines.html
		$self->error('_get_field_listoptions_from_code: the listoption sub was not defined. err, we shouldnt be getting here then, unless there is a key and its just returning undef.');
	}
	
	#return the listoptions from the function at the paramater name then.
		#also maybe want to one day grab some listoption_sub_args from our $args and pass 'em along ... but not right now thanks.
	my $lo = $self->{'do'}->_field_listoptions()->{$_->{parameter_name}}->($self);
	$self->ch_debug(['_get_field_listoptions_from_code: for a field like: ', $fieldref, 'got listoptions like:', $lo]);
	#die "here stop";

	#select the selected.
	$self->_select_listoptions({
		listoptions    => $lo,
		selected_value => $args->{selected_value},
	});

	return $lo;
	
}

sub _select_listoptions {
	my $self = shift;
	my $args = shift;
	
	my $listoptions    = $args->{listoptions};
	my $selected_value = $args->{selected_value};

	my $first_option_flagged = 0; #for ss_cbox controls to draw right. may end up being superfluous.

	#2007 04 16, blargh multi value selection accomodating for the goofy way we tend to load an edit_value for that and call this with that. should do it all the cgi value pickup way but then there is the h:fif stuff to accommodate .. probably easily done.
	my $selected_values = undef;
	if (!defined($selected_value)) { $selected_value = []; } #establish as empty arrayref if not present. will end up not going over for selected flag.
	if (ref($selected_value) ne 'ARRAY') {
		$selected_values = [ $selected_value ];
	} else {
		#exists as arrayref already (or was just established as one b/c it didnt exist at all)
		$selected_values = $selected_value;
	}
	
	if (scalar(@$listoptions)) {
		#also if luser chose separator after editing a record, lets re-chose the db_value for them. cuz their dumn like rocks - too stupid to live.
			#or maybe not because that causes them to go back with error flags beside good looking values! doh.
		foreach my $lo (@$listoptions) {
			
			#skip the listoption altogether if it is flagged as a separator because people CANNOT keep a separator selected. this will also mean that its the first non-separator that will get flagged as teh first_option_flagged
			if ($lo->{separator}) { next; }
			
			#set the default value if there is one (and the current row matches it!) and slam the listoption row into the listoption array ref.
			foreach my $sel_val (@$selected_values) {
				if ($lo->{value} eq $sel_val) {
					$lo->{selected} = 1;
				}
			}
			
			if (!$first_option_flagged) {
				#flagging of first option being added for singleselect checkboxes ... where only the checkbox for the first option is drawn. (so we can use a checkbox for the 'active' field of records) ... in the viewform mode though we need to know what the other options are so if it's NOT the first option (ie, its not active) we can show the 'no' (or whatever) string.
				$lo->{first_option} = 1;
				$first_option_flagged = 1;
			}
		}
	}
}

1;