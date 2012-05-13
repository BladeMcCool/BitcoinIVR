package SpApp::DataObj::SupportObj::SQLAbstraction;
use base SpApp::DataObj::SupportObj;
use strict;
use HTML::Entities; #adding for entification of HTML from search results (as required)
use HTML::Strip;    #adding for stripification of HTML from search results (as required)
use HTML::FormatText::WithLinks;    #adding for stripification of HTML from search results (as required)
use Encode; #adding so I can force everythging that _perform_select gets out of the db into utf-8 via decode_utf8.

#would like the rowdata selection code (sql abstraction based on fields specs) to be here
sub _build_select_sql {
	my $self = shift;
	my $form_spec = shift;
	my $other_args = shift;
	
	my $form   = $form_spec->{form};
	my $fields = $form_spec->{fields};

	#I want to make sql based on the fields and search options passed in. 
		#All fields should be available in unformatted (_unf) versions. 
		#And if any formatting is to be applied to the values, it should be included as a formatted versions (_fmt). 
		#Every field and table should get aliased so that there is no confusion.
		#Groupby must be specified if functions requiring it is used.

	if (!$fields || !$form) {
		$self->error('build_select_sql requires some fields and a form_spec');
	}
	#return $self if ($self->error());
	
	my @fl_blocks   = (); #fields list
	my @tl_blocks   = ($form->{base_table}); #tables list
	my @wc_blocks   = (); #whereclause
	my @hc_blocks   = (); #havingclause
	my @bind_params = ();
	my %join_order  = ();
	my %join_cond   = (); #join conditions. will get tablenames as keys, and joinconditions as values ;)
	#my %join_resolv = (); #doing this with a parameter_name to alias map. same idea i think.
	my $groupby     = undef;
	my $orderby     = undef;
	my $alias_ctr   = 0;
	my $join_ctr    = 0;
	my $pk_field    = $form->{pk_field};
	my $pk_field_found_in_fields = 0;

	#obtain merged fields list .. fields and their subfields all as a flat list.
	my $sql_fields = $self->{fp}->_get_merged_fields_and_subfields($fields);
	my $join_table_working_aliases = {};
	
	#$self->ch_debug(['_build_select_sql: starting with these sql fields:', $sql_fields ]);
	#build tables and fields lists.
#	foreach (@$fields) {
	foreach (@$sql_fields) {
		#ensure field actually has a db_field_name -- if not, then I dont think there is anything we should be doing with it	
			#this situation arose after adding a no-db_field_name field for the purpose of "retype email address" on a CMC form.
		if (!$_->{db_field_name}) { next; }
		
		#check if the field is marked as using a groupby func .. if so we'll have to add the groupby clause
		if ($_->{sql_groupby_func}) {
			#add group by to make COUNT/SUM/etc. work properly when joining with other tables.
			$groupby = $pk_field; #is this always right? if not when should it be different?
		}

		my $tablename_part = undef;
		my $fieldname_part = undef;
		my $db_field_name  = undef;
		my $join_onclause  = undef;

		#extract the tablename and fieldname portion for use below, and also define the main_select_table if this field is defined as the pk field in the field definition.
		if ($_->{db_field_name} =~ /^(\S*)\.(\S*)$/ ) {
			$tablename_part = $1;
			$fieldname_part = $2;
		}
		#assign a revised db_field_name based on whether we're working with a joined table requiring table name aliasing.
		$_->{db_field_name_revised} = ($join_table_working_aliases->{$tablename_part} ? $join_table_working_aliases->{$tablename_part} : $tablename_part) . '.' . $fieldname_part;

		#2007 05 22 experiment for groupby, have a query that is generating same company name under mulitple categories, we dont show the category info, so we should only show the company name one time. so i want to allow doing a groupby explicitly for that field.
		if ($_->{sql_groupby}) { #just a boolean - for groupby func's, see above. this is separate/distinct/conflicting usage which might mean we need to support multiple group-by, assuming thats even possible.
			$groupby = $_->{db_field_name_revised};
		}

		$alias_ctr++;
		my $alias = 'f' . $alias_ctr . '_' . $_->{parameter_name};
		$_->{db_field_alias} = $alias;

		if ($_->{sql_value_lookup}) {
			$join_ctr++;
			
			#establish a means to resolve each field to its field alias, based on its parameter name.
				#except i do that elsewhere.
			#$join_resolv{$_->{parameter_name}} = $alias;
			$_->{looked_up} = 1;
				
			if ($_->{sql_value_lookup} =~ /^(\S*)\.(\S*)$/) {
				#if the value_lookup_key is in tablename.fieldname notation then ASSUME it means we are to find the display value in the specified table.fieldname where field id matches the id of this row.

				my $join_to_table_name = $1; #ex: location
				my $value_fieldname = $2;#ex: name

				my $join_to_table_alias = 'std_lkp_' . $join_ctr;
				my $join_to_table_finished = "$join_to_table_name $join_to_table_alias";

				#set the field name to be added to the list of fields to select
				#$db_field_name = $_->{sql_value_lookup};
				$db_field_name = $join_to_table_alias . '.' . $value_fieldname;

				#take note of what would be considered the 'looked_up' db field name -- because generally for whereclauses we want to match against what was looked up. i think.
				$_->{looked_up_db_field_name} = $db_field_name;
				
				#set criteria on which to do the join
				my $joinfield = 'id';
				if ($_->{sql_value_lookup_key}) {
					#2007 05 15, as part of enhancement in this general area to alias all tables we are doing sql_value_lookup with, I also want to improve how we specify more explicit join condition ... sql_value_lookup should always define the table to use, sql_value_lookup_key can give that same tablename with a non-id field to use for the join, or just specify the non-id field. if it specifies a table other than the one we are expecting, then blow up.
					if ($_->{sql_value_lookup_key} =~ /^(\S*)\.(\S*)$/) {
						#tablename.fieldname, we just ensure the tablename is what we expect and then go with the field.
						my ($table, $field) = ($1, $2);
						if ($table ne $join_to_table_name) { die "sql_value_lookup_key should use same table as sql_value_lookup, but can specify a custom field by which to join other than id."; }
						$joinfield = $field;
					} else {
						#or assume we just got the field name
						$joinfield = $_->{sql_value_lookup_key};
					}
				}
				
				$join_onclause = $_->{db_field_name_revised} . ' = ' . $join_to_table_alias . '.' . $joinfield; #ex: scheduledevent.id = scheduledevent_attendee.scheduledevent_id
				$join_order{$join_ctr} = $join_to_table_finished; #set the join order. important because we'll need to join in the order the fields are specified (usu. by sql_query_order) when joining across an intermediary table. (as is the case for the viewform details searchform result for the attendee scheduledevents ). note, doing it this way means we'll only save the ordering info once, the first time we encounter the tablename.
				$join_cond{$join_to_table_finished} = $join_onclause;
				#$self->ch_debug(['_build_select_sql: setting up for a table join, join_onclause is:', $join_onclause, 'join_to_table_finished is:', $join_to_table_finished, 'the full set of join conds right now is:', \%join_cond ]);

				#each time we set up a join to another table, make note of the table alias we're using. if we join to the same table multiple times, each time we do we'll make note of the working alias for that table. so that as we list fields of that table after doing the join, they will pull from the correct join.
				$join_table_working_aliases->{$join_to_table_name} = $join_to_table_alias;

			} else {
				#otherwise, look up the value in the app_form_field_listoption table, and it is possible that we may need to suck multiple lookup values from the standard name=>value lookup table called app_form_field_listoption. Of course, if I remember my SQL, to do this each separate join will need to use a different table name/alias, so lets beware of that and alias the table accordingly. 
				my $join_to_table_name = "app_listoption";
				my $join_to_table_alias = 'alo_' . $join_ctr;
				my $join_to_table_finished = "$join_to_table_name $join_to_table_alias";
				#set the field name to be added to the list of fields to select
				$db_field_name = $join_to_table_alias . '.display_value';
				#take note of what would be considered the 'looked_up' db field name -- because generally for whereclauses we want to match against what was looked up. i think.
				$_->{looked_up_db_field_name} = $db_field_name;

				#set criteria on which to do the join
					##Having a weird problem where I have a separator as a listitem with no VALUE (well its NOT NULL since its part of the index, so leaving no value yields a empty string in there) and also with another value under the same parameter name with a zero for the value, well when a record that has to look up the display value uses the 0, it is actually getting two records because apparently with a char field for the value in the paramter_name/value keypair in the alo table, '' and '0' are both equal to 0. however, '' and '0' are NOT both equal to a character '0', so since I am always going to be comparing agains a CHAR type value for alo.value, I think a sensible solution to this weird double-record on the join problem will be to always CAST whatever value I am checking against alo.value as a CHAR. and so the experiment begins. -- heres hoping that this doesnt make all my queries take forever tho! in that case I dunno what the F I'll do to solve it!!
				#$join_onclause = "(" . $join_to_table_alias . '.parameter_name = ? AND ' . $join_to_table_alias . '.value = ' . $_->{db_field_name} . ")";;
				#$join_onclause = "(" . $join_to_table_alias . '.parameter_name = ? AND ' . $join_to_table_alias . '.value = CAST(' . $_->{db_field_name_revised} . " AS CHAR))";;
				#since (2008 04 11) I'm allowing NULL listoption values in the db in some cases I need to use a null-safe comparison in this join condition.
				$join_onclause = "(" . $join_to_table_alias . '.parameter_name = ? AND ' . $join_to_table_alias . '.value <=> CAST(' . $_->{db_field_name_revised} . " AS CHAR))";;
				push(@bind_params, $_->{sql_value_lookup});

				#add the table name key and join condition clause to the join_conditions hash which will be required for every single alo lookup.
				$join_order{$join_ctr} = $join_to_table_finished; #set the join order. important because we'll need to join in the order the fields are specified (by display_order) when joining across an intermediary table. (as is the case for the viewform details searchform result for the attendee scheduledevents ). note, doing it this way means we'll only save the ordering info once, the first time we encounter the tablename.
				$join_cond{$join_to_table_finished} = $join_onclause;
			}		
		} else {
			#no sql_value_lookup at all -- just show the field. maybe have some formatting handled below.
				#but remember, we may have to take into consideration that the tablename we're referring to has been aliased, which it WILL be if we are dealing with fields from a join table.
				#so pull it out of the revised one. if we didnt revise then it'll be the same as db_field_name original value anyway.
			$db_field_name = $_->{db_field_name_revised};
		}
		
		#$self->ch_debug(['_build_select_sql: current db_field_name shaped up to be: ', $db_field_name ]);

		my $db_field_name_unaliased = $db_field_name;
		##take groupby sql func's into account, and then wrap around any formatting sql func.
		if ($_->{sql_groupby_func}) {
			#if applying a GROUPBY type sql function to the field, select it like "FUNC(table.fieldname) AS alias"
				#http://dev.mysql.com/doc/refman/4.1/en/group-by-functions.html -- for a list of the groupby (aggregate) functions.
				#and I may need to support multiple notations. for now I just want to be able to code the function name in the sql_groupby_func attribute, but i might want to be able to say COUNT(DISTINCT <%fieldname%>) in the future.
			if ($_->{sql_groupby_func} =~ /<%fieldname%>/) {
				#support a more complex notation
				$db_field_name_unaliased =~ s/<%fieldname%>/$db_field_name/g;
			} else {
				#but happily use something simpler
				$db_field_name_unaliased = $_->{sql_groupby_func} . '(' . $db_field_name . ')';
			}
		}
		
		#if applying an sql formatting function to the field, select it like "SQL_FUNC(table.fieldname, func_options...) AS fieldnamepart"
			#i'd also like to support perl based postprocessing formatting functions (which would be applied to the query results after they're gotten duh)
			#and if applying sql formatting, then keep unformatted values around too
		#we could be formatting for search or edit displays.. If not told anything, go with search. If told to use the edit version, use it and fallback to search format if there is not edit format. Can override that behaviour by passing editmode_format_fallback => 'none' in the args.
		my $format_source = 'search';
		my $format_requested = $format_source; #this is for my own self interest - so I can see if i requested edit but search was used because search format fallback was done.
		if ($other_args->{for_editform}) {
			$format_source = 'edit';
			$format_requested = $format_source;
			if ((!$_->{edit_output_format} && $_->{search_output_format}) && $other_args->{editmode_format_fallback} ne 'none') {
				#hrm .. told to use editformat, but theres only a search format -- since we've been allowed to use search as fallback, do so.
				$format_source = 'search';
			}
		}

		#my $format_attrib = $_->{$format_source . '_output_format'};
		#my $sql_format = $self->{'do'}->_json_attribs($format_attrib);
		my $sql_format = $_->{$format_source . '_output_format'};

		if ($sql_format->{sql}) {
			#note that I want to support perl formatting functions as well, but those will need to be handled AFTER the results are gathered.
				#and for now the only notation supported by these sql functions will be the embedded <%fieldname%> method.
			my $fld_tmp = $db_field_name_unaliased;
			my $db_fld_fmt = $sql_format->{sql};
			$db_fld_fmt =~ s/<%fieldname%>/$fld_tmp/g;
			$_->{db_field_formatting_sql} = $db_fld_fmt; #adding this at the moment entirely so we can restrict against formatted values in a WHERE clause. (probably could do HAVING against the alias, but I dont want to code for mixing up WHERE and HAVING at the moment)
			push(@fl_blocks, $db_fld_fmt . ' AS ' . $alias . '_fmt');
			$_->{formatted} = 1;
			$_->{'formatted_for_' . $format_requested . '_with_format_from'} = $format_source; #I would imagine that most of the time format_requested and format_source and  will be the same. -- but I want to track it in case something fucks up and so I dont get confused.
		}

		#if the value is to be a looked up value, then alias it as _lkp and keep the source field value as the plain alias.
		my $db_field_name_aliased = $db_field_name_unaliased . ' AS ' . $alias;
		if ($_->{looked_up}) {
			#the value is to be looked up ... alias it as _lkp and keep the underlying value as the plain alias.
			$db_field_name_aliased .= '_lkp';
			my $source_field_aliased = $_->{db_field_name_revised} . ' AS ' . $alias;
			push(@fl_blocks, $source_field_aliased);				
		}			
		push(@fl_blocks, $db_field_name_aliased);				

		$form->{parameter_to_alias_map}->{$_->{parameter_name}} = $alias;
#		$form->{parameter_to_fieldref}->{$_->{parameter_name}} = $_; #doing this early now, called in _initialize.
		if (!$self->{'do'}->{_fieldrefs}->{$_->{parameter_name}}) {
			$self->ch_debug(['form spec:', $form_spec]);
				die "here";
			 $self->error("in _build_select_sql with no parameter_to_fieldref mapping for a parameter name of '$_->{parameter_name}'"); 
		}
		if ($db_field_name eq $pk_field) { 
			$form->{pk_field_alias} = $alias;
			$pk_field_found_in_fields = 1;
		}
	} #end loop over fields.
	
	#$self->ch_debug(['_build_select_sql: fieldlist blocks shaped up like: ', \@fl_blocks]);
	
	##I am having a bug/issue where re-using a dobj that has already been used for a search will have hit the code below and set a pk_field_alias and added to the fields list of the sql to be sure to include something about that .... and it works the first time, but then there is a pk_field_alias set in the form the next use, but the field is still not in the fields and so my sql is not including the pk field on subsequent runs! thats no good! so the plan is to set a flag when we realize we dont have the pk field amongst the fields, and then we can use THAT to trigger needing to slap it in here.
		#and really this just comes down to being explicit instead of inferring shit.
	if (!$pk_field_found_in_fields) {
		#this would mean that the pk_field was not among the form fields used. But we will need to include a field for which the record ID will be included.
			#so we will include it now aliased simply as record_id ... that _SHOULD_ be ok! bloody hope so.
		if (!$pk_field) { die 'Cannot include primary key field without $form->{pk_field} being defined. This should not happen.'; }
		push(@fl_blocks, "$pk_field AS record_id");
		$form->{pk_field_alias} = 'record_id';
		#$self->ch_debug(['_build_select_sql: s.b. adding to fl_blocks for the pk_field_alias']);
	}
	#$self->ch_debug(['_build_select_sql: here with pk_field_alias of: ', $form->{pk_field_alias}]);

	###EXTRACT table list and join condition list, ording the joins as specified in the join_condition_order hash (ordernumber => tablename pairs.) 
	foreach my $join_order (sort { $a <=> $b} keys(%join_order)) { #go through the numeric slots in a specific order ;)
		my $tablename = $join_order{$join_order}; #get tablename out of the numeric slot in the ordering hash, and use it to add the join info to the 
		push(@tl_blocks, $tablename . " ON " . $join_cond{$tablename});
	}		
	
	#I've left out the major WHERE clause stuff thus far which would be 
#		- keyword matching (on all keyword searchable fields or on just 1 of them)
#		- daterange matching (on all daterange searchable fields or on just 1 of them)
#		- listoption matching (on all listoption searchable fields or on just 1 of them) (this should be made to work with options from alo table or from another table -- i need to get that figured out in editing mode first I think)
#		- restrictor matching (i had a whole system for this ... I think there were some good ideas in it, but it was cumbersome to define them ... probably want to define them as perl structures instead of db. maybe at the DataObject subclass level.
	
	#for now a whereclause to focus on is matching against the primary key to select one specific record
	if ($other_args->{record_id}) {
		#means we only want this record where the pk matches $args->{record_id}.
		my $match_field = $pk_field;
		#if ($form->{pk_field_alias}) { $match_field = $form->{pk_field_alias}; } #i would imagine we'd do this most of the time ... or not because you can't use field aliases in the where clause(??)
#		push(@wc_blocks, $match_field . ' = ' . $other_args->{record_id});
		#2007 03 24: do this with bind param.
		push(@wc_blocks, $match_field . ' = ?');
		push(@bind_params, $other_args->{record_id});
	} else {
		#if not asked for a specific record then maybe there is other WHERE clause criteria, or sorting or some other shit.

		#keyword matching:
		#my @keywords = split(/\s+/, $other_args->{keywords});
		my @keywords = @{ $self->_split_keywords({ kw => $other_args->{keywords} }) };
		$self->ch_debug(['here1 with kw array like:', \@keywords, 'based on', $other_args->{keywords} ]);
		if (scalar(@keywords)) {
			#$self->ch_debug(['here2']);
			#to match, all keywords must match something. means we want to check all keyword searchable fields if they match any of the keywords.
				#note, keywords have to match THE CORRECT db_field_name ... CANNOT match against aliases (MySQL just doesnt seem to handle that)
				#for lookup value fields, I want to match against, eg, the name of the color as looked up, not the ID of the color saved in the base query table.
			my @kw_wc_blocks;
			foreach my $kw (@keywords) {
				$kw = '%' . $kw . '%';
				#$self->ch_debug(['here3 for keyword', $kw]);
				if ($other_args->{limit_keywords_to_field}) {
					my $fld = $self->{'do'}->{_fieldrefs}->{$other_args->{limit_keywords_to_field}};
					my $db_field_name = $fld->{looked_up_db_field_name} ? $fld->{looked_up_db_field_name} : $fld->{db_field_name_revised};
					push(@kw_wc_blocks, $db_field_name . ' LIKE ?');
					push(@bind_params, $kw);
					#$self->ch_debug(['here4 with limit_keywords_to_field:', $kw, $other_args->{limit_keywords_to_field}]);
				} else {
					my @kw_fieldmatch_blocks;
					foreach my $fld (@$fields) {
						#$self->ch_debug(['here3.9']);
						## lets turn this one off ## next if (!$fld->{search_show_field});
						next if (!$fld->{search_keyword});
						my $db_field_name = $fld->{looked_up_db_field_name} ? $fld->{looked_up_db_field_name} : $fld->{db_field_name_revised};
						#$self->ch_debug(['here3.9.1 to match against db_field_name:', $db_field_name]);
						push(@kw_fieldmatch_blocks, $db_field_name . ' LIKE ?');
						push(@bind_params, $kw);
					}
					#join the kw fieldmatch blocks with OR because we need THIS kw to match any one (but at least one) of the fields.
					#$self->ch_debug(['here4 (no keyword limiter)']);
					if (scalar(@kw_fieldmatch_blocks)) {
						my $kw_fieldmatch = '(' . join(' OR ', @kw_fieldmatch_blocks) . ')';
						push(@kw_wc_blocks, $kw_fieldmatch);
						#$self->ch_debug(['here4.1 (the kw and kw_fieldmatch):', $kw, $kw_fieldmatch]);
					}
				}
			}
			#join the kw blocs with AND because all keyword matches must be satisfied.
			my $kw_wc = undef;
			if (scalar(@kw_wc_blocks)) {
				$kw_wc = '(' . join(' AND ', @kw_wc_blocks) . ')';
				push(@wc_blocks, $kw_wc); #2009 04 17 I believe this line really belongs here.
			}
			#push(@wc_blocks, $kw_wc); #2009 04 17 I believe this line really belongs up inside the check for whether we have kw_wc_blocks to deal with.
			#$self->ch_debug(['here5, kw wc is now like:', $kw_wc]);
		}		
		#$self->ch_debug(['here6, after kw, wc_blocks is like:', \@wc_blocks ]);

		#firstletter matchin (new for 2007 05 22, though theres nothing really special about it and we might have used it earlier if we had had it).
		#$self->ch_debug(['_build_select_sql: with other args of:', $other_args ]);
		#die "stop to inspect other args";
		if ($other_args->{firstletter_search}) {
			my @fl_wc_blocks;
			my $fl = $other_args->{firstletter_search} . '%';
			if ($other_args->{limit_firstletter_to_field}) {
				my $fld = $self->{'do'}->{_fieldrefs}->{$other_args->{limit_firstletter_to_field}};
				my $db_field_name = $fld->{looked_up_db_field_name} ? $fld->{looked_up_db_field_name} : $fld->{db_field_name_revised};
				push(@fl_wc_blocks, $db_field_name . ' LIKE ?');
				push(@bind_params, $fl);
			} else {
				my @fl_fieldmatch_blocks;
				foreach my $fld (@$fields) {
					next if (!$fld->{search_firstletter});
					my $db_field_name = $fld->{looked_up_db_field_name} ? $fld->{looked_up_db_field_name} : $fld->{db_field_name_revised};
					push(@fl_fieldmatch_blocks, $db_field_name . ' LIKE ?');
					push(@bind_params, $fl);
				}
				if (scalar(@fl_fieldmatch_blocks)) {
					my $fl_fieldmatch = '(' . join(' OR ', @fl_fieldmatch_blocks) . ')';
					push(@fl_wc_blocks, $fl_fieldmatch);
				}
			}
			#join the fl blocs with AND because all firstletter matches must be satisfied.
			my $fl_wc = undef;
			if (scalar(@fl_wc_blocks)) {
				$fl_wc = '(' . join(' AND ', @fl_wc_blocks) . ')';
			}
			push(@wc_blocks, $fl_wc);
			$self->ch_debug(['_build_select_sql: firstletter matching with these wc_blocks: ', \@fl_wc_blocks ]);
		}		

		#daterange matching:
		if ($other_args->{daterange_start} || $other_args->{daterange_end}) {
			my @dr_fieldmatch_blocks;
			#unlike stupid old way of doing it we can get two already-separate pieces of the daterange, already formatted properly for mysql date queries.
			my $start_date = $other_args->{daterange_start};
			my $end_date = $other_args->{daterange_end} ? ($other_args->{daterange_end} . ' 23:59:59') : undef; #if provided, put time up till end-of-day on the end date.

			my $match_fields = [];;
			if ($other_args->{limit_daterange_to_field}) {
				$match_fields = [ $self->{'do'}->{_fieldrefs}->{$other_args->{limit_daterange_to_field}} ];
			} else {
				$match_fields = $fields;
			}
			foreach my $fld (@$match_fields) {
				## lets turn this one off ## next if (!$fld->{search_show_field});
				next if (!$fld->{search_daterange});
				my $db_field_name = $fld->{looked_up_db_field_name} ? $fld->{looked_up_db_field_name} : $fld->{db_field_name_revised};
				my $field_compare = $db_field_name;
				if ($start_date && $end_date) {
					$field_compare .= " >= ? AND $db_field_name <= ?";
					push(@bind_params, ($start_date, $end_date));
				} elsif ($start_date) {
					$field_compare .= " >= ?";
					push(@bind_params, $start_date);
				} elsif ($end_date) {
					$field_compare .= " <= ?";
					push(@bind_params, $end_date);
				}
				push(@dr_fieldmatch_blocks, $field_compare);
			}
			if (scalar(@dr_fieldmatch_blocks)) {
				my $dr_fieldmatch = '(' . join(' OR ', @dr_fieldmatch_blocks) . ')';
				push(@wc_blocks, $dr_fieldmatch);
				#$self->ch_debug(['here4.1 (the kw and kw_fieldmatch):', $kw, $kw_fieldmatch]);
			}
		}		

		#dropdown matching.
		if ($other_args->{dropdown_searches} && scalar(keys(%{$other_args->{dropdown_searches}}))) {
			#build the dropdown fields part of the where clause.
				#note that nasty scalar keys check makse sure its not a fucking EMPTY hashref before we get in here and build a fucked ass useless query breakin whereclause if it WAS empty hashrefh.
			my @dd_wc_blocks;
			foreach (keys(%{$other_args->{dropdown_searches}})) { #keys will be the parameter name, values will be the submitted value to match.
				my $fld_ref = $self->{'do'}->{_fieldrefs}->{$_};
				my $db_field_name = $fld_ref->{db_field_name_revised};
				push(@dd_wc_blocks, "$db_field_name = ?");
				push(@bind_params, $other_args->{dropdown_searches}->{$_});
			}
			
			#surround this whereclause block with parenthesis
			my $dropdown_whereclause = '(' . join (' AND ', @dd_wc_blocks) . ')';
			push(@wc_blocks, $dropdown_whereclause);
		}

		#arbitrary result restriction (I've got the key, I've got the secret)
		if ($other_args->{restrict}) {
			#experimentally we're just going to accept a hashref with parameter names for keys and values to match as values. its up to the caller to pass in the right value. 
				#if the field the param refers to is a group_by func field then we have to restrict with having clause blocks.
				#are we restricting based on plain values, looked up values, or formatted values? I really am not sure!
				#going to support two types of restrictor: super simple and hardass complex, although I suspect there will be simple ways to do hardass complex restrictions. hopefully.

				### Restrictors must be specified as an argument to this func called restrict, as a hashref of parameter_name => restriction ... the restriction part can be simply a value to match against, or a set of conditions, match strings, and bind parameters. The example below should illustrate quite well how to use it!
				#
				#Here is an example of setting a restriction, mixing complex and simple restrictors in thus far the most complex use of them
					#2007 04 02 added some more to the example showing how to match IN (list, of, items) and against IS NOT NULL/IS NULL kind of thing.
				#restrict => {
				#	'ilc_month' => [
				#		{	match_cond => '>=', match_str => '?', bind_params => $month . '-01'},
				#		{ match_cond => '<',  match_str => 'DATE_ADD(?, INTERVAL 1 MONTH)', bind_params => $month . '-01'},
				#		{ match_cond => 'IN',  match_str => '(?, ?, ?)', bind_params => ['foo', 'bar', 'baz']},
				#		{ match_cond => 'IS',  match_str => 'NOT NULL'},
				#	],
				#	'ilc_type' => $type,
				#}
			
			#experimental enhancement for 2007 05 09, I want to be able to do some conditions with OR. The current pattern of use seems to want to have 2 groups of records essentailly returned in the same result set, each group being based on a bunch of AND'ed where clause blocks, OR'ing the two groups of whereclause blocks together. The simplest way to do this I can imagine is to allow arrayref for restrictor at top level, and then go over each and do with OR.
			if (ref($other_args->{restrict}) ne 'ARRAY') {
				$other_args->{restrict} = [ $other_args->{restrict} ];
			}
			my $restrictor_group_count = 0;
			my @all_restrictor_groups_wc_blocks = (); #will be joined with OR then added to main wc_blocks. each one inside will be pre joined with AND
			foreach my $restrictor_group (@{$other_args->{restrict}}) {
				$restrictor_group_count++;
				my @cur_restrictor_group_wc_blocks = (); #for all the wc blocks of _this_ restrictor group. these go together with AND.

				foreach my $parameter_name (keys(%{$restrictor_group})) {
					####NEED TO BE ABLE TO ACCOMMODATE RESTRICTING THE VALUE BASED ON IS NULL/IS NOT NULL .. thinking how to do that without being lame ... ok, the BEST way I can think of right now is magic interpretation of literals "IS NULL" and "IS NOT NULL", those would be magic values. wanting to actually match against those strings in the db is both highly unlikely, and would require some ability to override the "magic" behaviour. if that ever arose, I think I would have to do a "complex" restrictor for it that would allow passing of a "literal" flag or something.
						#oh .. well, me be stupid. i can already do IS NULL and IS NOT NULL with complex restrictors. yay.
						#ok, so gonna go with that until the day i/someone REALLY REALLY wants to do IS NULL / IS NOT NULL in a simple one, then have to add and test that support
					my $restrictor = $restrictor_group->{$parameter_name};
					my $field = $self->{'do'}->{_fieldrefs}->{$parameter_name};
					
					#2007 04 02 experiment: if restricting a special param called 'record_id' which may not exist in the fields but which should always refer to the pk field, we can try to fake it. just to play with this idea, b/c i want to be able to write restrict => { record_id => foo } and not worry about if I have actually set up a parameterized field name for the record_id (since a ton of other stuff about pk_field/record_id is automated throughout this shit already anyways it seems to make sense)
					if (!$field && $parameter_name eq 'record_id') {
						$field = { db_field_name => $form->{pk_field}, db_field_name_revised => $form->{pk_field} }; #probably will only look to the _revised now with the mods that have been made throughout.
					}
					
					if (!$field) { $self->error("_build_select_sql: failed to obtain a field with a parameter name of '$parameter_name'"); }
					#$self->{wa}->dbg_print(['the field shit:', $field ]);
					my $match_field = undef;
					my $match_cond = undef;
					my $match_value = undef;
					my $match_looked_up_values = 1; #I may some day need to be able to turn this off ... i imagine it would be for a complex restrictor.
					my $match_formatted_values = 1; #I may some day need to be able to turn this off ... i imagine it would be for a complex restrictor.
					my $use_where = undef; #turns false if we have to do HAVING, true if we are to do WHERE.
					
					if ($other_args->{restrict_options}->{dont_match_looked_up_values}) {
						#this is really just a hack until complex restrictors are implemented. see this will mean if there is more than one restrictor then none of them will go against looked up values. really for complex restrictors i might want some to match underlying and others to match looked up vlaues. but this will solve my immediate problem.
						$match_looked_up_values = 0;
					}
					
					#Determine the field we are comparing some value to. the field that we are restricting the results based on the value of. Rules for that are below:
					#is it groupby?
					#	is it looked up and we want to match against the looked up value?
					#		use HAVING db_field_alias . '_lkp'
					#	else
					#		just use HAVING db_field_alias
					#else not groupby (for vast majority)?
					#	is it looked up and we want to match against the looked up value?
					#		use WHERE looked_up_db_field_name
					#	else
					#		just use WHERE db_field_name
					if ($field->{sql_groupby_func}) {
						$use_where = 0;
						$match_field = $field->{db_field_alias};
						if ($field->{looked_up} && $match_looked_up_values) { $match_field .= '_lkp'; }
					} else {
						$use_where = 1;
						$match_field = $field->{db_field_name_revised};
						if ($field->{looked_up} && $match_looked_up_values) { $match_field = $field->{looked_up_db_field_name}; }
						#k for formatted value matching, cannot seem to reference the alias for the formatted value in the WHERE clause. Going to replicate the excact same sql for the formatting then in the where clause and it should work.
						#if ($field->{formatted} && $match_formatted_values) { $match_field = $field->{db_field_alias} . '_fmt'; }
						if ($field->{formatted} && $match_formatted_values) { $match_field = $field->{db_field_formatting_sql}; }
					}
	
					my $restrictor_string;
					if (!ref($restrictor)) {
						#simple mode
						$match_cond = '=';
						$match_value = '?';
						push(@bind_params, $restrictor); #in this case $restrictor will contain the actual value to match against.
						$restrictor_string = "$match_field $match_cond $match_value";
					} else {
						#complex mode
							#so we could have been given just a hash to define a single value restriction. Or we might have been given a list of things that the field for the specified parameter name has to match.
	#					#need to be able to set the condition to something other than equals.
	#					#need to be able to use another db field as the match value. -- #not really implemented yet 
						if (ref($restrictor) ne 'ARRAY') {
							#lets put everything into the multi-condition mode, just so we can code easier.
							$restrictor = [$restrictor];
						}
						
						#now we should have an array of hashrefs for the restrictor.
						my @restrictor_blocks = ();
						foreach my $restrict_params (@$restrictor) {
							$match_cond = $restrict_params->{match_cond};
							$match_value = $restrict_params->{match_str};
							
							####### !!!! might want to figure out a way of including other fields by parameter name in the match_value .. and specifying whether that is against lookup/formatted value or whatever. that will be VERY hairy and for now determinging the exact name of the field to match against will be required and that name will have to be put into the restrictor for it to work.
							
							my $restrictor_binds = defined($restrict_params->{bind_params}) ? $restrict_params->{bind_params} : []; #default to empty arrayref if there was nothing to bind. prevents us from constructing an array ref with 1 undef element if there was no bind param at all.
							if (ref($restrictor_binds) ne 'ARRAY') {
								$restrictor_binds = [ $restrictor_binds ];
							}
							my $bindcount = scalar(my @count = $match_value =~ m|\?|g);
							my $required_bindcount = scalar(@$restrictor_binds);
							if ($bindcount != $required_bindcount) {
								die "Error processing restrictors: match string contained $bindcount bind placeholders when $required_bindcount were required.";
							}
							
							if ($required_bindcount) {
								push(@bind_params, @$restrictor_binds); #in this case $restrictor will contain the actual value to match against.
							}
							push(@restrictor_blocks, "$match_field $match_cond $match_value");
						}
						$restrictor_string = '(' . join(' AND ', @restrictor_blocks) . ')';
					}
					
					#we've set our match_field, cond, and match_value and added any bind params so now just add the clauseblocks to the apropriate clauseblocks.
					if ($use_where) {
						push(@cur_restrictor_group_wc_blocks, $restrictor_string);
					} else {
						#I know that this multiple restrictor group thing will not work right if we have to play with having clauses - so I want to die if we need to do a HAVING block and are using more than one restrictor group, so that I dont cause the weird problems with record matching that I thing will probably result.
						if ($restrictor_group_count > 1) {
							die "While using multiple restrictor groups, a HAVING clause was determined to be required. How will that affect the results? Carefully check to see it will do what you want. I believe it probably will do something weird/wrong. Comment this out to try and see.";
						}
						push(@hc_blocks, $restrictor_string);
					}
	
					#$self->ch_debug(["build_select_sql: restricting for param $parameter_name with a matching field def like:", $field, "WHERE (1) or HAVING (0/undef): '$use_where', with restrictor_string of $restrictor_string", "with a (simple restrictor otherwise you'll see the detailed info) bind param like", $restrictor]);
				} #end loop over restrictor-group field-restrictions.

				if (scalar(@cur_restrictor_group_wc_blocks)) {
					#only time we shouldnt have any cur_restrictor_group_wc_blocks is if there was just one restrictor group and all it used was a HAVING clause block.
					my $cur_group_string = '(' . join(' AND ', @cur_restrictor_group_wc_blocks) . ')';
					push(@all_restrictor_groups_wc_blocks, $cur_group_string);
				}
				#$self->ch_debug(["build_select_sql: just added these cur_restrictor_group_wc_blocks:", \@cur_restrictor_group_wc_blocks, 'to the all_restrictors_wc_blocks (which is shaping up like:)', \@all_restrictor_groups_wc_blocks ]);

			} #end loop over restrictor groups. they will be OR'ed together.
			
			#complete the 2007 05 09 experiment for multiple restrictor groups (each of which can have multiple simple or complex restrictions joined with AND) to be joined with OR. The primary motiviator of adding this was for LBG (and cmc probably) admin to be able to query DB for related rows and also include some other rows that were just valuesearched, based on some related record id's that are only set in the session.
			if (scalar(@all_restrictor_groups_wc_blocks)) {
				#only time we shouldnt have any all_restrictors_wc_blocks is if there was just one restrictor group and all it used was a HAVING clause block.
				my $all_restrictors_string = '(' . join(' OR ', @all_restrictor_groups_wc_blocks) . ')';
				push(@wc_blocks, $all_restrictors_string);
			}
			
		} #end check condition for doing estrictors or not.


		###Sorting. rewritten 2007 06 04
		my @orderby_blocks = ();
		my $sortfield_count = 0;
		my $user_sort = $other_args->{user_sort};
		
		#no user sort specified, try to set up a default
			#also 2009 03 18, I need to correct a MISTAKE that I made waaaay back with this sorting setup stuff with this JSON crap. it should NOT be json. it might be if the object was being defined in the DB ... but we dont really do that. and then it should be decoded in the code that pulls it from the db anyway and placed at the thing. so I'm gonna go now and FIX this .. and say that if there is a STRING (not a reference) at this property of default_sort, then we have to de-json it. at some point, that will become deprecated and it will DIE if it has to do that shit.
		my $default_sort = $form->{default_sort};
		if ($default_sort && !ref($default_sort)) {
			#oh noes, its a json encoded string. it shouldnt really be tho, b/c we want to deprecate that MISTAKE of allowing/requiring that at some earlier time.
			#but for now I guess lets decode it.
			#die "Error: use of deprecated means of specifying default sort (probably used a JSON string when a hashref should have been used)";
			$default_sort = $self->{'do'}->_json_attribs($default_sort);
		}		
		
		if ($default_sort && !$user_sort) {
			$user_sort = $default_sort;
		}
		if (!$user_sort) { $user_sort = []; }

		#$self->{wa}->debuglog(['_build_select_sql: doing sorting with user_sort like: ', $user_sort ]);
		#make it arrayref if it isnt already.
		if (ref($user_sort) ne 'ARRAY') {
			$user_sort = [ $user_sort ];
		}
		#go over each sorting and set up orderby_blocks for them.
		foreach my $sorting (@$user_sort) {
			$sortfield_count++;
			if (!$sorting->{dir}) {
				$sorting->{dir} = 'ASC';
			} else {
				$sorting->{dir} = uc($sorting->{dir}); #uppercase it for consistency.
			}
			my $sort_field_param = $sorting->{parameter_name};
			if (!$sort_field_param) { 
				$self->{wa}->debuglog(['_build_select_sql: about to error out over broken sort we had these: ', $user_sort, 'and the current item:', $sorting ]);
				$self->error('_build_select_sql: will not be able to set up the desired user sort because no parameter_name was specified in the user_sort.');
			}
			my $sort_dir         = $sorting->{dir};

			#figure out what fieldname alias to reference in the sort.
			my $sort_field_alias = $form->{parameter_to_alias_map}->{$sort_field_param};
			if ($sort_field_param && !$sort_field_alias) { $self->error("SQLAbstraction, sorting setup, did not find a field alias for the requested sort field param '$sort_field_param' - its possible you requested this sort but the sort field is not amongst the fields. Note that meta fields are NOT automatically included!", { parameter_to_alias_map => $form->{parameter_to_alias_map} }); }
			my $sfa_finished = $sort_field_alias;
			my $sort_field_ref = $self->{'do'}->{_fieldrefs}->{$sort_field_param};
			if ($sort_field_ref->{looked_up}) { $sfa_finished = $sort_field_alias . '_lkp'; }
			## this is the part where sorting by formatted value is not implemented.
			my $ob_block = undef;
			if ($sort_field_alias && $sort_dir) {
				###line below needs to be revised, not sure where this info gets used, so just commenting out for now.
					#we'd want to be pushing a hashref into an array if we need to do it
					##ahhhh ok, this is so that record-field level sorting flags get set in the perform_select code, so that the sorting arrows show up in the output.
				if (!$form->{sorting}) { $form->{sorting} = []; }
				push(@{$form->{sorting}}, { parameter_name => $sort_field_param, dir => lc($sort_dir), sort_num => $sortfield_count }); #sort_num tells us if it is the 1st sort, 2nd sort, etc. not really useful just yet, but will be when we support multiple-levels of sorting as being selectable by the user. then we'll be able to indicate what sorting level each arrow we show is for.
				###$form->{sorting} = { parameter_name => $sort_field_param, dir => lc($sort_dir)};
				$ob_block = $sfa_finished . ' ' . $sort_dir;
			}
			
			#add to the list of orderby's
			push(@orderby_blocks, $ob_block);	
		}
		#join orderby blocks into our official ORDER BY clause
		$orderby = join(', ', @orderby_blocks);

	}	#end check of have-record_id-or-not.
	
	#ALL the blocks of the query are prepared. Polish it off and return the built SQL statement.
	my $fieldlist    = join(", ",          @fl_blocks); 
	my $tablelist    = join(" LEFT JOIN ", @tl_blocks); 
	my $whereclause  = join(" AND ", @wc_blocks); 
	my $havingclause = join(" AND ", @hc_blocks); 
	
	#prepare the main select SQL.
	my $sql = "SELECT $fieldlist FROM $tablelist";
	if ($whereclause) {
		$sql .= " WHERE $whereclause";
	}
	if ($groupby) {
		$sql .= " GROUP BY $groupby";
		if ($havingclause) {
			$sql .= " HAVING $havingclause";
		}
	}
	if ($orderby) {
		$sql .=  " ORDER BY $orderby";
	}

	$self->ch_debug(['_build_select_sql: build this sql and will use these bind params:', $sql, \@bind_params ]);
	
	$self->{last_select_sql} = $sql; #mainly for debug
	$self->{last_select_sql_binds} = \@bind_params; #mainly for debug
	return { sql => $sql, bind_params => \@bind_params };
#	return { sql => $sql, bind_params => \@bind_params, form_spec => $form_spec };
	
}

sub _perform_select {
	my $self       = shift;
	my $sql        = shift;
	my $sql_binds  = shift;
	my $form_spec  = shift;
	my $other_args = shift;
	
	#this will be the do-the-query-paginate-the-results function.
	my $page_size    = $other_args->{page_size};
	my $current_page = $other_args->{current_page} ? $other_args->{current_page} : 1;
	my @bind_params  = @$sql_binds;

	my $num_records  = $other_args->{num_records} ? $other_args->{num_records} : 0; #experimental behaviour to cut out one of the statement executions .... lose the row counting one if we already did that and are now being told how many rows there are
	my $total_pages  = 0;
#	my $dbh          = $self->get_dbh();
	my $dbh          = $self->{'do'}->_get_data_dbh();

	if (!$form_spec) { $self->error('perform_select needs a form_spec (with its form and fields attribs)'); }
	#return $self if ($self->error());	

	$self->ch_debug(['perform_select, with sql, sql_binds, and other args like:', $sql, $sql_binds, $other_args]);
	#$self->{wa}->dbg_print(['perform_select, with sql, sql_binds, and other args like:', $sql, $sql_binds, $other_args]);
	
	#get number of rows to be returned by the query.
	#just messing with this prepare_cached stuff ... doesnt really seem to do too much meh.
	#my $dbi_cache_id = JSON::Syck::Dump([ @bind_params, $self->{_data_db}, $self->{_formcontrol_db} ] ); #not sure I need formcontrol db in there ... but we'll be really clear then!
	
	if ($page_size) {
		#my $sth = $dbh->prepare($sql); 

		if (!$num_records) {
			#we didnt tell ourselves how many records (first run of search, or inefficient usage) so we will go find out first.
			#this started to not work reliably all of a sudden 2011 01 07 not sure why, too many records, damaged table, or what.
			#SELECT SQL_CALC_FOUND_ROWS should be the answer.
			#note repairing the table fixed the ->rows thing but i think doing it a better way might be prudent anyway.

			#do it like Phpmyadmin does, which seems to be more reliable:
			(my $count_sql = $sql) =~ s|^SELECT\s|SELECT SQL_CALC_FOUND_ROWS |i;
			$count_sql .= ' LIMIT 1';
			my $sth = $dbh->prepare($count_sql); 
			$sth->execute(@bind_params) or die "DBI Error on Select: $DBI::errstr, SQL USED: $sql";
			$num_records = $dbh->selectrow_arrayref('SELECT FOUND_ROWS()', undef, ())->[0];

			#or the old way I used to do it, ....
				#which worked up until it didnt. (a large table got damaged, which I only discovredb by manually executing the query the way phpmyadmin would do, thru phpmyadmin. repairing the table made this old way work again however since the above way was working via phpmyadmin even with damaged table, lets try to use it regularly.
			#my $sth = $dbh->prepare($sql); 
			#$sth->execute(@bind_params) or die "DBI Error on Select: $DBI::errstr, SQL USED: $sql";
			#$num_records = $sth->rows;

			$self->{wa}->ch_debug(['query had this many records:', $num_records ]);
		}
		
		#calculate important paging status/setup info, but only if a page_size is actually specified (otherwise there should be NO limit clause and all results should show on one page!)
		$total_pages = int($num_records / $page_size);
		if (($num_records % $page_size) != 0) { $total_pages++ }

		#if the real total number of pages is less that what we think the current page is (because user deleted the only row on the last result page) then set the current page to be the last page that there is (tota;_pages)
		if ($total_pages < $current_page) { $current_page = $total_pages; }	
	} else {
		#no page size? use these then:
		$total_pages = 1;
		$current_page = 1;
	}

	#add the LIMIT clause to the data collecting query if there is a page size specified
	my $offset = 0;
	if ($page_size && $num_records) {
		$offset = ($current_page - 1) * $page_size; #should be correct unless user is trying to view a page which no longer exists due to user deleting the only row of that page.
		$sql .= " LIMIT ?, ?";
		push(@bind_params, ($offset, $page_size));
	}

	#Query the db for the actual data ... send it back in a way that isnt useless.
	$self->ch_debug(['_perform_select: will be querying with this sql and bind params:', $sql, \@bind_params]);
	#die "stop";
	#$self->{wa}->dbg_print(['_perform_select: will be querying with this sql and bind params:', $sql, \@bind_params]);
	#my $sth = $dbh->prepare_cached($sql, { dbi_cache_id => $dbi_cache_id }); #dummy attrs, to identify the handle correctly (hopefully) in the cache.
	my $sth = $dbh->prepare($sql); 
	$sth->execute(@bind_params) or die "DBI Error on Select: $DBI::errstr. SQL: $sql";

	my $row_ctr = $offset; #should start at the paging offset if one is supplied. will be 0 if one is not.
	my $page_row_ctr = 0;
	my @results;
	my @results_simple;
	#my $pmap           = $form_spec->{form}->{parameter_to_alias_map};
	my $pk_field_alias = $form_spec->{form}->{pk_field_alias};
  my $dispval_maxchars = 32; #totally arbitrary default. possibly we would pick up a config option up above somewhere and use that instead.
	
	#I think what I want is multi-modal operation. For classic search results I'll want to build the records array. For editing a single record, I'll want to add db_values to the fields directly. 
	my $result_mode = 'list';
	my $record_id = $other_args->{record_id};
	my $single_record_search = $other_args->{single_record_search};
#	if ($record_id || $args->{single_record_fields_direct}) {
		#ok the above was an idea for asking for a single record from a search, without neccessarily asking for a specific record id. I dont like how it would be implemented though. What i really want is a way to get like an editform display values out of a search result ... not sure on how to approach that at the moment, but I want the call to be easy!
	if ($record_id || $single_record_search) {
		#if we were asked for a single record id, plug values into the fields of the sf spec.
		$result_mode = 'fields_direct'; #this mode means that we're going to be putting a db_value and possibly a db_value_fmt right into the fields of the form_spec, and returning right after that.
	}
	
	my $sorting = $form_spec->{form}->{sorting};
	my @field_headings = ();
	my $html_formatter = undef; #will instantiate only once if we need to use one.
	#$self->ch_debug(['_perform_select: the sorting setup is like: ', $sorting ]);

	if ($result_mode eq 'list') {
		#$self->ch_debug('_perform_select: list mode');

		#field headings. do once. using first row. this is just to make templating less stupid in some cases.
			#note this is NOT the usual way we've drawn field headings, usually we just loop over the results and do them on the first run, but in some cases (LBG User side for example) we want to ALWAYS have these available.
		foreach my $fld (@{$form_spec->{fields}}) {
			my $heading = {	
				parameter_name => $fld->{parameter_name}, 
				display_name   => $fld->{search_display_name}, 
				display_width  => $fld->{search_display_width},
			};
			if ($sorting) {
				foreach my $current_sort (@$sorting) {
					if ($fld->{parameter_name} eq $current_sort->{parameter_name}) {
						$heading->{'sort_' . $current_sort->{dir}} = 1;
					}
				}
			}
			push(@field_headings, $heading);
		}

		while (my $row = $sth->fetchrow_hashref()) {
			my %row_hash;
			$row_hash{record_fields} = []; #record_fields is array ref.
	
			#set the row number for HTML id'ing and javascript highlighting. -- update: use the uid as the row number! (meaning uids MUST be unique!)
			$row_ctr++;
			$page_row_ctr++;
			$row_hash{record_num} = $row_ctr;
			$row_hash{page_record_num} = $page_row_ctr;

			#establish record id in the row_hash and the simple_row_hash.
			#should we be taking into account the record_id param for the search results? I am not sure right now. maybe. if so, this might help:
				#my $record_id_param = $args->{record_id_param} ? $args->{record_id_param} : 'record_id';
				#BUUUUT ... what I probably want to do wrt record_id_param is rename it $record_id_cgi_param ... though these field params are intended to be cgi param. oh I dunno now what to do.
			$row_hash{record_id} = $row->{$pk_field_alias};
			my $simple_row_hash  = {record_id => $row->{$pk_field_alias}};

			#we need to go over all the fields of the form spec to build the current row hash in a HTML::Template way.
			foreach my $fld (@{$form_spec->{fields}}) {

				my $fieldname_part = $fld->{db_field_alias};
				my $field_hash = {
					db_value          => $row->{$fld->{db_field_alias}}, #and of course we want the field_value key of the field_hash pointing to the value of the current db_fieldname
					parameter_name    => $fld->{parameter_name},
					search_show_field => $fld->{search_show_field},      #copy the show_field attribute for this field so if it not to be displayed it does not show up in the output!
					display_name      => $fld->{search_display_name}, 
					display_width     => $fld->{search_display_width},   #2007 05 14, adding so as to be able to hardcode an output width for columns in LBG User-side company search results.
					###specifying excel format is out of scope. it should be obtained from a fieldref and should fall under search_result_options.
					##excel_format      => $fld->{excel_format},           # added so we can specify the correct format for each field in an excel spreadsheet.
				};
				$simple_row_hash->{$fld->{parameter_name}} = $row->{$fld->{db_field_alias}};

				#do sorting setup .. only needs to be added to the sort field in the first row.
					#we will only do it when processin the first row (page_row_ctr == 1) and if there is a sorting setup in the first place.
				if (($page_row_ctr == 1) && $sorting) {
					foreach my $current_sort (@$sorting) {
						if ($fld->{parameter_name} eq $current_sort->{parameter_name}) {
							$field_hash->{'sort_' . $current_sort->{dir}} = 1;
						}
					}
				}
				
				my $disp_value_from = 'db_value';
				if ($fld->{looked_up}) { #this would be the unformatted looked-up value. fmt above would have the formatting applied to it.
					$field_hash->{db_value_lkp} = $row->{$fld->{db_field_alias} . '_lkp'};
					$simple_row_hash->{$fld->{parameter_name} . '_lkp'} = $row->{$fld->{db_field_alias} . '_lkp'};
					$disp_value_from = 'db_value_lkp';
				}
				if ($fld->{formatted}) { 
					$field_hash->{db_value_fmt} = $row->{$fld->{db_field_alias} . '_fmt'};
					$simple_row_hash->{$fld->{parameter_name} . '_fmt'} = $row->{$fld->{db_field_alias} . '_fmt'};
					$disp_value_from = 'db_value_fmt';
				}
		
				#get display value out
				my $disp_value = $field_hash->{$disp_value_from};
				
				#I'm torn as to whether any of this seeming postprocessing actually belongs here. I dont think it really does. Especially the fields-direct versions.
				#entify embedded html if required to. #also experimental.
					#going to do this (and any other style of html manipulation) only for fields that are TEXTINPUT_RICH
				if ($fld->{edit_fieldtype} eq 'TEXTINPUT_RICH') {
					if ($other_args->{plaintext_html}) {
						if (!$html_formatter) { $html_formatter = HTML::Strip->new(emit_spaces => 0, decode_entities => 0); } #so we instantiate it once, and only if we actually need to use it.

						#ok, HTML::Strip is written in XS, which means that perl utf8 flag on input is probably(or surely!) gonna get lost during the processing. so ensure that the utf8 flag is set back on the result.
						#$disp_value = $html_formatter->parse($disp_value);
						$disp_value = Encode::decode('utf8', $html_formatter->parse($disp_value));
						$html_formatter->eof();
					}
					if ($other_args->{entify_html}) {
						$disp_value = encode_entities($disp_value); #just using default settings. mainly want to turn <p> into &lt;p&gt; kind of thing.
					}
				}
									
				#chop display value down if required to (do it after any formatting of html that could alter the length of the disp_value)
					#i think i might want to revise it so that it will apply a default maxchars length to everythign if short_text is turned on, and always make use of a search_result_options-specified 
				my $fld_dispval_maxchars = undef;
				if ($other_args->{short_text}) {
					#this is experiment for searchform controller outputted display values to not be insanely huge and make it easy to show rows that do not each take up the whole screen with giant columns of squished text.
					$fld_dispval_maxchars = $dispval_maxchars;
					if ($fld->{search_result_options}->{short_text_maxchars}) {
						$fld_dispval_maxchars = $fld->{search_result_options}->{short_text_maxchars};
					}
				} else {
					#and a way to limit field lengths regardless of whether short_text mode is turned on.
						#allowing a specific length to be coded, or a flag to use the default short_text length!
					if ($fld->{search_result_options}->{maxchars}) {
						$fld_dispval_maxchars = $fld->{search_result_options}->{maxchars};
					} elsif ($fld->{search_result_options}->{short_text}) {
						$fld_dispval_maxchars = $dispval_maxchars;
					}
				}		
					
				#2007 07 10: do length and substr operations as if the data is utf-8 (via decode_utf8 to set the utf flag on the resulting string), and then take the utf flag back off it (encode_utf8). This is to keep everything without the utf8 flag on it in the end. The reason to do that is that we may have utf8 data in other strings that are NOT utf8 flagged, and we do not want those strings to be double-encoded when they are concatenated. If nothing has utf8 flags on it, then there is no chance of a string with utf8 data in it being double-encoded by perl during a concatenation operation like what happens when we output a template.
					#the proper solution is to ensure that all strings that contain utf8 data are flagged as such. doing that will be expensive at the moment.
				##if ($fld_dispval_maxchars && (length(decode_utf8($disp_value)) > $fld_dispval_maxchars)) {
				if ($fld_dispval_maxchars && (length($disp_value) > $fld_dispval_maxchars)) {
					###Wondering why the short text appears shorter than it should? Well, look at the source of the outputted short text .... we are keeping entities in place so, for example, a single &nbsp; at the beginning of the string will be treated as 5 chars. Of course it would be great if the length chopping code below could treat each entity as a single char... not sure on how that'd work. maybe if we decoded entities, chopped it, and then re-encoded with entities? hrm. would that really be hard?
					#$self->{wa}->debuglog(['_perform_select: adjusting display value from:', $disp_value, 'which is clearly this many chars long:', length($disp_value) ]);
					##$disp_value = encode_utf8(substr(decode_utf8($disp_value), 0, $fld_dispval_maxchars)) . '...';
					$disp_value = substr($disp_value, 0, $fld_dispval_maxchars) . '...';
					#$self->{wa}->debuglog(['_perform_select: adjusting display value to:', $disp_value, 'which by definition should be 32 chars long plus the ... which should make it 35.']);
				}
								
				#slap display value in 
				$field_hash->{db_value_disp} = $disp_value;
				$simple_row_hash->{$fld->{parameter_name} . '_disp'} = $disp_value;
				
				#2007 05 04 I want to know for search result rendering if the field is an imageinput field and if it is and there is a so I probably want to show a thumbnail image
				if ($fld->{edit_fieldtype} eq 'IMAGEINPUT' && $fld->{search_result_options}->{show_thumbnail}) {
					$field_hash->{show_thumbnail} = 1;
					$field_hash->{image_directory} = $fld->{image_directory};
					#give a way to specify that some other size be used for thumbnail, in case its needed (i can see 'thumb' being used for something else, and wanting to show super-micro-thumb in the search list or something) -- but we're guaranteed to have a 'thumb' size at any rate.
					$field_hash->{image_thumbnail_sizetag} = $fld->{search_result_options}->{thumbnail_sizetag} ? $fld->{search_result_options}->{thumbnail_sizetag} : 'thumb';
					
					$simple_row_hash->{$fld->{parameter_name} . '_image_directory'} = $fld->{image_directory};
				}

				if ($other_args->{preselect_record_id} && $row_hash{record_id} eq $other_args->{preselect_record_id}) { $row_hash{selected} = 1; }
				
				#$self->ch_debug(['perform_select, looking at a row like this:', $row, 'and my field hash for jamming into the result fields arrayref is looking like', $field_hash]);
				push(@{$row_hash{record_fields}}, $field_hash); #jam that hash of field data into the array of field data hashes for this row!.
			}
			push(@results, \%row_hash); #jam that hash of row data into the big 'ol results array. A big 'ol happy HTML::Template compatible results array.
			push(@results_simple, $simple_row_hash); #also save an unmolested copy of the row (using parameters as fieldnames) for use in custom searchform result templates designed to match the specific fields of the result set.
		}
	} elsif ($result_mode eq 'fields_direct') {
#		$self->ch_debug('_perform_select: fields_direct mode');
		my $row = $sth->fetchrow_hashref(); #like the highlander, there can be only one.
		#$self->ch_debug(['_perform_select, fields_direct, got a row like: ', $row ]);
		if (!$row) { return 0; } #what should I _really_ be returning if there was no row in this case?

		###going to need to code for the subfields of a COMBO_RADIO_CONTROLLED_FIELD shit here.
			#obtain merged fields list .. fields and their subfields all as a flat list.
		my $sql_fields = $self->{fp}->_get_merged_fields_and_subfields($form_spec->{fields});
		
		foreach (@$sql_fields) {
#		foreach (@{$form_spec->{fields}}) {
			
			#2007 06 23 experiment: if there is no db_field_alias then do not overwrite whatever is in db_value. there would be no reason to do so, and by not doing so we will allow hardcoded "db_value" in custom objects like the monthdoc editor for blumont (which we prepopulate db_value for the cms fields we slap in)
			my $has_db_field = $_->{db_field_alias};
			$_->{db_value} = $has_db_field ? $row->{$_->{db_field_alias}} : $_->{db_value}; #so preserve whatever is in db_value if this object field doesnt have a db field.

			#2007 03 26 experiment: if field is flagged as "save_json_encoded" then we will dump to JSON before save, and load from JSON upon edit.
				#this might be a bad idea. but i thought it would be interesting to toy with
			if ($_->{save_json_encoded}) { $_->{db_value} = JSON::Syck::Load($_->{db_value}); }

			my $disp_value_from = 'db_value';
			if ($_->{looked_up}) { 
				$_->{db_value_lkp} = $row->{$_->{db_field_alias} . '_lkp'};
				$disp_value_from = 'db_value_lkp';
			}
			if ($_->{formatted}) { 
				$_->{db_value_fmt} = $row->{$_->{db_field_alias} . '_fmt'};
				$disp_value_from = 'db_value_fmt';
			}
			$_->{db_value_disp} = $_->{$disp_value_from};
			
			#none of this shit belongs here. it should all be in postprocessing. and we need viewform postprocessing and a viewform func.
			#2007 05 15, making viewform concept, which is really (currently) just a stripped down, non-editable version of an editform that cares about a whole lot less stuff, just got through hammering out a useful stripped-html-plaintext version for searchresults output of RTE fields, doing something similar for viewform, but in this case I think I want the underlining and other coolness that FormatText::WithLinks will do. but no left margin. lolz.
				#2007 06 08, improving this, giving more reasons, including very explicit instruction, to do plaintext_html.
			my $output_style = $other_args->{output_style};
			my $plaintext_html = 0;
			my $wrap_text      = 0;

			if ($other_args->{plaintext_html} && $_->{edit_fieldtype} eq 'TEXTINPUT_RICH') { $plaintext_html = 1; }
			if ($other_args->{wrap_text}      && ($_->{edit_fieldtype} =~ /^TEXTINPUT_/ || $_->{edit_fieldtype} =~ /^DISPLAY_/)) { $wrap_text = 1; }
			if ($output_style && $_->{$output_style . '_options'}->{plaintext_html}) {	$plaintext_html = 1; }
			if ($output_style && $_->{$output_style . '_options'}->{wrap_text})      {	$wrap_text      = 1; }

			if ($plaintext_html) {
				#neither html::strip nor html::formattext::withlinks is really giving me what I want here. going to probably have to do a html parser like was done for flagging custom form errors for designed editforms ... but instead for this to pull text content only but enforce line breaks after certain things.
				#another way, using the HTML::FormatText::WithLinks, and replacing newline chars with <br/>. should be semi-ok. Jay wont like the styling. I wont like the giving a shit.
					#also, we CANNOT re-use the same instance of the object, since somehow something is getting left behind and subsequent runs are producing fucked up output with extra leading and trailing newlines. Pissing me the fuck off too. So the easy thing is to just make a new instance for every usage. I wish I could figure this out as making a new one every time is lame.
				$html_formatter = HTML::FormatText::WithLinks->new(leftmargin => 0, rightmargin => 0);
				$_->{db_value_disp} = $html_formatter->parse($_->{db_value_disp});
				$_->{db_value_disp} =~ s|\n|<br/>|g;
			}
			
			#2007 06 16 wrap text (to indroduce html whitespace), because viewforms need to not have long map_url's blowing up their admin screen layout.
			if ($wrap_text) {
				local($Text::Wrap::columns) = 80;
				my $orig = $_->{db_value_disp}; #just for debug.
				$_->{db_value_disp} = Text::Wrap::wrap('', '', $_->{db_value_disp});
				$self->ch_debug(['_perform_select: wrapping text from this to that', $orig, $_->{db_value_disp}]);
			}
		}

		#debating whether to directly set the record id here or not. For now, I think i will set it somewhere that can be handled separately. Up until now, this was not an issue b/c before now the only way to be in this fields_direct mode was to have set a reocrd_id already and done load_record_for_edit ... but now there is find_record_for_edit b/c we dont KNOW the record id.
			#or hell, maybe we should just be returning the record id here.
		if ($single_record_search) {
			#$self->{srs_obtained_record_id} = $row->{$pk_field_alias};
			$self->ch_debug(["_perform_select, will be sending back pk field alias '$pk_field_alias' value of: ", $row->{$pk_field_alias} ]);
			return $row->{$pk_field_alias};
		}	else {
			return 1;
		}
	}

	my $result_hash = {};

	#eventually need to do something for these items here:
	#$result_hash->{fieldlist} = $fieldlist;
	#$result_hash->{tablelist} = $tablelist;
	#$result_hash->{whereclause} = $whereclause;
	#$result_hash->{db_order_by_asc}   = $db_order_by_asc;  #to let the template carry the override sort field info forwards
	#$result_hash->{db_order_by_desc}  = $db_order_by_desc;

	$result_hash->{sql}             = $sql;
	$result_hash->{sql_binds}       = \@bind_params;
	$result_hash->{num_records}     = $page_size ? $num_records : $row_ctr; #again, if not paging use the $row_ctr as the number of rows (because just about the only time we arent paging is when we're doing weird joins for viewform details results that cause the count query to return the WRONG number of rows!).
	$result_hash->{page_size}       = $page_size;
	$result_hash->{current_page}    = $current_page;
	$result_hash->{total_pages}     = $total_pages;
	$result_hash->{records}         = \@results;
	$result_hash->{records_simple}  = \@results_simple;
	$result_hash->{field_headings}  = \@field_headings;

	#$sth->finish();
	#$self->{wa}->dbg_print("finished calling finish on handle $sth");

	return $result_hash;
}

#would like the rowdata insertion/update code to be in here too.
	#a func like my old generalized spapp::save_record function except that was easier to call and .... actually worked right .. all the time. ha. 
sub _save_record {
	my $self = shift;
	my $form_spec = shift;
	my $args = shift;
	
	my $form      = $form_spec->{form};
	my $fields    = $form_spec->{fields};

	#$self->ch_debug(['_save_record: form_spec:', $form_spec]);

	my $record_id = $self->{'do'}->record_id(); #changing this so that if the object has a record id set we'll use it.
	my $sql_only  = $args->{sql_only};

	#so this is to become what the old dataobj::save_record should have been ... not-shitty.
		#which means basically chopping out anything to do with the bloody where-do-i-get-my-value-from shit that ALWAYS caused the problems and just sticking with the solidly always-fucking-worked-right insert/update sql statement building code.
#	my $dbh = $self->get_dbh();
	my $dbh = $self->{'do'}->_get_data_dbh();
	my $session = $self->{wa}->session();
	#at this point we'll just assume everything is good (because we got here) and do the insert.

	my $sql;
	my $sth;

	#the $form->{base_table} will identify the tablename.
		#so we should probably just skip over any field that is from another table entirely (probably in the fields list for display purposes in edit/search modes)
	#always add .modified, .created_admin_id and .modified_admin_id fields (binding NOW(), ?, ?) to the list. If there is no corresponding value, use 0 -- the rest of the program will know this means the system generated the action, not some admin.
	#determine pk field in the exact same way as build_sql_query -- and if there is a value defined in the fields then we're in update mode, otherwise we're in insert mode.
	my @field_list;
	my @value_list;
	my $admin_id = $session->param('_admin_id') ? $session->param('_admin_id') : 0; #use 0 if none.
	my $insert_mode = $record_id ? 0 : 1; #so we're in insert_mode if $record_id is NOT defined OOOOPPS sorry, if $record_id has no value. (... it will probably always be defined!) . otherwise its update_mode.
	my $main_table  = $form->{base_table};
	my $pk_field    = $form->{pk_field};
	my @bind_params = ();
	my $meta_included = { #take a note of any meta fields like created, modified, created_admin_id and modified_admin_id and do NOT automatically include them in the sql if for some reason they were actually editable parts of the form (which normally they should NOT be but hey, its just happened to me in the mptest app and I dont like shit breaking)
		$main_table . '.created' => 0,
		$main_table . '.modified' => 0,
		$main_table . '.created_admin_id' => 0,
		$main_table . '.modified_admin_id' => 0,			
	}; 

	###going to need to code for the subfields of a COMBO_RADIO_CONTROLLED_FIELD shit here.
		#obtain merged fields list .. fields and their subfields all as a flat list.
	my $sql_fields = $self->{fp}->_get_merged_fields_and_subfields($fields);
	
	#now get the field list and value list (value list will be mostly ? of MD5(?), etc.)
	foreach my $field (@$sql_fields) {
#	foreach my $field (@$fields) {
		#DETERMINE if we are to skip over the field and NOT use it in our insert/update.
			#skip any field that:
				#a) s flagged as skip_field already for whatever reason,  (changing to skip_save nov 15 2006)
 				#b) is the pk field (we'll not be setting the value under any circumstances at this point) (and exactly fucking why not? I need to do this today April 30 2007.)
					#I'm removing this requirement b) because it is preventing me from doing something I want to do, and I dont know why it was included. I hope doing this does not break a bunch of other things I cannot think of.
					#perhaps I should revise b) to say if its the pk field and it has no value then skip it ... but if its the pk field and it does have a value, leave it alone.
					#skip it also if we are in update mode and the field value matches the pk_value already, so it stays out of the sql.
				#c) has no field name or is from a table other than base table, 
				#d) is a blank password field in update mode (this should remain handy -- it has in the past.)
				#e) or is ?? (what else)
		if ($field->{skip_save}) { next; }                                                                      #a)

#		if ($field->{db_field_name} eq $pk_field) { next; }                                                     #b) (not too helpful)
 		if ($field->{db_field_name} eq $pk_field) {                                                             #b) (revised experimental)
 			if ($insert_mode && !$field->{save_value}) {
 				#insert mode for the pk field, but it doesnt have a value. skip it to use auto_id (normal operation!)
 				next;
 			} elsif (!$insert_mode && $field->{save_value} eq $record_id) {
 				#update mode for the pk field, but its value matches the existing record id, skip it to keep it out of the sql (no need to update it to set the pk value to be the existing pk value, and that sql would be kind of dirty)
 					#this should let us CHANGE the record_id/pk if we want to provide a value other than the things original record id for the pk field, in a different way than loading a record for edit and then clearing the record id and then saving the reocrd. if the pk field was in the fields, we could load it, set a new editvalue for the pk field, and then save it. pretty much the same thing anyway.
					#2007 07 24 - buut if you create one, save it, and then do some more stuff with it, and save it again, and your pk field is in your fields, then you HAVE to carry the pk forward manually (or do edit_show_field=>0). doh. what to do about that? not sure.
				next;
			}
			#being here means we're not skipping this pk field, we're going to use the value that is set for the field.	
 		}
 		
		if (!$field->{db_field_name} || $field->{db_field_name} !~ /^$main_table\./) { next; }                    #c)
		if (!$insert_mode && (($field->{edit_fieldtype} =~ /_PASSWORD$/) && (!$field->{save_value}))) {	next; } #d)
	
		#2007 03 26 experiment: if field is flagged as "save_json_encoded" then we will dump to JSON before save, and load from JSON upon edit.
		if ($field->{save_json_encoded}) { $field->{save_value} = JSON::Syck::Dump($field->{save_value}); }
	
		#not skipping? (still here!?) then do something with the field data:
		#but only work with the field if there is a field name specified (case added to prevent working with the password2 field which is only used for its validation rule, not the submitted value.)
	
		my $bind_str = '?';
		#for any included password fields, use the digest of the password if the save_as_digest flag is set. (which may be unset for a password field that normally would be saved as a digest in the case that the value already IS a digest, or maybe we just want to store plaintext passwords so lusers can request gay 'password reminders'!)
			#except that this was among the shit that was causing problems ... think harder about automatic password encryption behavior. maybe a field-level-always-explicit flag. Yeah .. actually, go with that.
		if ($field->{edit_fieldtype} =~ /_PASSWORD$/) {
			if ($field->{save_as_digest}) {
				$bind_str = 'SHA(?)'; #field to store it in should be char40 
			} elsif ($field->{save_as_md5digest}) {
				$bind_str = 'MD5(?)'; #field to store it in should be char32 (2011 01 013 for om->mc stuff, drupal uses md5.
			}
		}
		push (@value_list, $bind_str);
#		push (@field_list, $field->{db_field_name});
		push (@field_list, join('.', map {'`' . $_ . '`'} split(/\./, $field->{db_field_name})));
		
		#2011 01 13 how could this bit anything other than a mistake? seriuosly why woud we bind undef for empty string ''? how the fuck would we do a empty string then? how bout just bind what we got. period. no gayness.
		#if (!defined($field->{save_value}) || ($field->{save_value} eq '')) {
		#	push (@bind_params, undef);
		#} else {
		#	push (@bind_params, $field->{save_value});
		#}
		push (@bind_params, $field->{save_value});
		
		if (exists($meta_included->{$field->{db_field_name}})) {
			$meta_included->{$field->{db_field_name}} = 1;
		}
	}

	#$self->{wa}->dbg_print(['SQLAbstraction::_save_record: working with a field list like: ', \@field_list ]);
	#die "stop since its fooked";

	#define insert vs update meta infos
	my %meta;
	if ($insert_mode) {
		%meta = (
			"$main_table.created" => { value => 'NOW()'},
			"$main_table.created_admin_id" => { value => '?', bind_param => $admin_id },
			"$main_table.modified_admin_id" => { value => '?', bind_param => $admin_id },
		);
	} else {
		%meta = (
			"$main_table.modified_admin_id" => { value => '?', bind_param => $admin_id },
			#"$main_table.modified"          => { value => '?', bind_param => undef }, #trying to get these 'modified' timestamp fields to update ... not sure how to do it right. ... ok update: this line worked, but was only needed b/c the fields didn't/don't have ON UPDATE CURRENT_DATETIME attribute set. app_log in cmcredev is fixed, as is the formtool code that adds these fields.
		);
	}
	#prepare meta infos
	###look and see a million debug statments all just because i forgot to wrap defined() around my check for existence of bind param ... mother fucker!
	#$self->ch_debug(['meta fields ... be sure to include these: ', \%meta, 'and note that we we are already including these (any tagged with 1):', $meta_included]);
	#$self->{wa}->dbg_print(['meta fields ... be sure to include these: ', \%meta, 'and note that we we are already including these (any tagged with 1):', $meta_included]);
	unless ($form_spec->{form}->{skip_meta_fields}) {
		foreach my $metafld (keys(%meta)) {
			#$self->ch_debug(['meta fields ... will we do one like this?: ', $metafld]);
			if ($meta_included->{$metafld}) { next; } #dont include it twice. (some forms might have them as editable elements even though thats not a good idea, it should not blow shit up!)
			#$self->ch_debug(['meta fields ... yes we should include info for one like: ', $metafld]);
			#print STDERR "meta fields ... yes we should include info for one like: $metafld\n";
			push (@field_list, $metafld);
			push (@value_list, $meta{$metafld}->{value});
	#err, if checking for defined'ness how the F would I bind a NULL (undef) ??? changing to exists() ... 
	#		if (defined($meta{$metafld}->{bind_param})) { 
			if (exists($meta{$metafld}->{bind_param})) {
				#eg why we might NOT be here: .created will not have a bind param ... the string NOW() will just be included in the sql.
				#$self->ch_debug(["there is a bind for meta $metafld like:", $meta{$metafld}->{bind_param}]);
				push (@bind_params, $meta{$metafld}->{bind_param});
			}# else {
				#$self->ch_debug(["there is NO bind for meta $metafld -- ", \%meta]);
			#}			
			#$self->ch_debug(['after adding meta to field_list, value_list, and bind_params we have them like:', \@field_list, \@value_list, \@bind_params]);
		}
	}

#	#clean up field list to make sure all field names are quoted
	#errr ... should be doing this higher up.
#	@field_list = map {
#		split('.', $_);
#	} @field_list;
		
	#now prepare the actual query (insert or update) and run it.
	if ($insert_mode) {
		my $field_list = join(", ", @field_list);
		my $value_list = join(", ", @value_list);

		$sql = "INSERT INTO $main_table ($field_list) VALUES ($value_list)";

		if ($sql_only) {
			return { insert_sql => $sql, binds => \@bind_params };
		}

		#$self->{wa}->dbg_print(['save_record: about to do insert with this sql and binds', { insert_sql => $sql, binds => \@bind_params }]);
		#$self->ch_debug(['save_record: about to do insert with this sql and binds', { insert_sql => $sql, binds => \@bind_params }]);
		$sth = $dbh->prepare($sql) or die $dbh->errstr;
		$sth->execute(@bind_params) or die $dbh->errstr . " with SQL of: $sql\n";
		#return $new_or_edit_pk ? $new_or_edit_pk : $dbh->{mysql_insertid}; #return the pk that was used (the one passed in if present, or the one generated by the db if not).
			#the above no longer makes sense since I'm explicitly sayign that the only way to do insert mode is to NOT provide the record_id.
		return $dbh->{mysql_insertid}; #return the pk that was used (the one passed in if present, or the one generated by the db if not).

	} else {

		#yeah so if this bit doesnt work just uncomment the shit below it that works or the shit below that which, although gay, has always worked fine.
#A super cool one liner way
		my $field_list = join(', ', map { $field_list[$_-1] . ' = ' . $value_list[$_-1]; } (1..scalar(@field_list)));
#A good way
#		my $i = 0;
#		my $field_list = join(', ', map { $_ . ' = ' . $value_list[$i++]; } @field_list);
#A lame way
#		for (my $i = 0; $i < scalar(@field_list); $i++) {
#			$field_list .= $field_list[$i] . " = " . $value_list[$i] . ", ";
#		}
#		$field_list = substr($field_list, 0, -2); #shave 2 chars, (that last ", ") off the end. I couldnt figure out how to easily use map and join to accomplsh the above because its dealing with the 2 separate arrays and I really do want to keep the 2 separate arrays.

		$sql = "UPDATE $main_table SET $field_list WHERE $pk_field = ?";
		push (@bind_params, $record_id);

		if ($sql_only) {
			return { update_sql => $sql, binds => \@bind_params };
		}
		#$self->{wa}->debuglog(['save_record: about to do UPDATE with this sql and binds', { update_sql => $sql, binds => \@bind_params }]);
		#$self->ch_debug(['save_record: about to do update with this sql and binds', { update_sql => $sql, binds => \@bind_params }]);
		
		$sth = $dbh->prepare($sql) or die $dbh->errstr;
		$sth->execute(@bind_params) or die $dbh->errstr . " with SQL of: $sql\n";
		return $record_id;
	}
}

sub _delete_record {
	my $self = shift;
	my $args = shift;

	my $form      = $args->{form};
	my $record_id = $args->{record_id};
	if (!$form) { $self->error('_delete_record: no form. cannot delete a record if we cant find out the base table.'); }

	my $main_table  = $form->{base_table};
	my $pk_field    = $form->{pk_field};
	my @bind_params = ($record_id);

#	my $dbh = $self->get_dbh();
	my $dbh = $self->{'do'}->_get_data_dbh();

	#### What I want here is code that will just flag record as deleted and then the regular perform select isnt allowed to match deleted records. hows that eh? that'd be super swell. would that mean any join table should have a deleted field as well? and we're to always match on deleted = 0 ?

	my $sql = "DELETE FROM $main_table WHERE $pk_field = ?";
	$dbh->do($sql, undef, @bind_params) or die $dbh->errstr . " with SQL of: $sql\n";
	
}

### sub _add_table_fields {} #you know you'll need it. #and it should go over a dobj fields and create any fields that are missing, including the meta fields.

sub _empty_table {
	my $self = shift;
	my $form_spec = shift;
	my $args = shift;
	
	my $fields = $form_spec->{fields};
	my $tablename = $form_spec->{form}->{base_table};
	
	my $dbh = $self->{'do'}->_get_data_dbh();
	$dbh->do("TRUNCATE TABLE `$tablename`");
	return 1;
}

#this bitch dog will accept the long end of a set of field definitions and then, sorta create a mysql table for it. it umm ... will be automatic, you will make a data object, and write code for it, and forget about it. and the first time you go to use it ... well ... you get a new table. i suppose i'll get annoyed at it one day and maybe make it not automatic, but now that feels like the wicked-bad thing to do. cache tablenames so we 
	#well, I would _like_ it to be automaticalish, but I will settle right now for being able to manually call this and have it do something useful :)
sub _create_table {
	my $self = shift;
	my $args = shift;
	
	my $form_spec = $self->{'do'}->form_spec();
	if (!$form_spec) { die "Did not obtain a formspec."; }

	my $fields = $form_spec->{fields};
	my $tablename = $form_spec->{form}->{base_table};
	my $alter_table = $args->{alter}; #maybe alter instead of create?
	
	$self->ch_debug(['_create_table: with a formspec and args like:', $form_spec, $args]);
	
	my $dbh = $self->{'do'}->_get_data_dbh();
	#check if table exists before attempting to create it! ... optionally we can drop it if it exists, and recreate from formspec.
		#ripped from FormTool::Admin
	my $sql = 'SHOW TABLES';
	my $sth = $dbh->prepare($sql);
	$sth->execute() or die $dbh->errstr . " with SQL of: $sql\n";
	my $table_exists = 0;
	while (my $row = $sth->fetchrow_arrayref()) {
		if ($row->[0] eq $tablename) {
			$table_exists = 1;
			last;
		}
	}
	if ($table_exists) {
		if ($args->{drop}) {
			$dbh->do("DROP TABLE $tablename") or die "DB Error: " . $dbh->errstr();
		} else {
			if (!$alter_table) {
				die "Table $tablename exists already. If you want to drop it first so it can be re-created, pass the {drop => 1} option.";
			}
		}
	} else {
		$alter_table = 0; #can't alter tables that dont exist. (so just create them!)
	}

	my $fld_ctr = 0; #do i need it?
	#this skip fld types thing probably doesnt make sense. commenting out. instead, just going to skip it if the tablename of the field is not the tablename of the base table for the form.
	#my $skip_fld_types = $self->{em}->{emi}->_skip_fld_types(); #standard set of non-db-bound field types that if set we should avoid doing anything.

	my $fld_types = {
		date    => 'date',
		datetime => 'datetime',
#replacing the vc and text ones with ones that will set utf8 charset! since utf8 rocks my world.
#		vc      => 'varchar(255)',
#		text    => 'text',
		vc      => 'varchar(255) character set utf8',
		text    => 'text character set utf8',
		mediumtext=> 'mediumtext character set utf8',
		bit     => 'bit',
		'int'   => 'int(10)',
		tinyint => 'tinyint(3)',
		decimal => 'decimal(12,4)', #total length 12, 4 digits after the decimal.
		tb      => 'tinyblob', #256 bytes max, 
		b       => 'blob', #2^16 bytes max (64kb), 
		mb      => 'mediumblob', #2^24 bytes max (16MB??), 
		lb      => 'longblob', #2^32 bytes max (???BIG???), 
		enum    => 'enum',
		#was doing some other decimal formats but I think I'll just parse a decimal for \d+,\d+
		#'decimal16,9'  => 'decimal(16,9)',  #total length 16, 9 digits after the decimal.
		#'decimal16,14' => 'decimal(16,14)', #total length 16, 14 digits after the decimal.
		#'decimal17,16' => 'decimal(17,16)', #total length 17, 16 digits after the decimal.
		#ALTER TABLE `jest_privateproxy` ADD `testenum` ENUM( 'taco', 'sexparty' ) NOT NULL DEFAULT 'taco'
	};
	my $fld_opts = {
		'n'         => 'default NULL',
		'us_n'      => 'unsigned default NULL',
		'nn_0'      => "NOT NULL default '0'",
		'nn_0.0'    => "NOT NULL default '0.00'",
		'nn_b'      => "NOT NULL default ''",
		'us_nn_0'   => "unsigned NOT NULL default '0'",
	 	'us_nn_0.0' => "unsigned NOT NULL default '0.00'",
		'nn_first'  => "NOT NULL default ", #ONLY for enum, needs and must fish first option out of enum options.
	};
	my $fld_opts_special = {
		'datetime_nn_0' => "NOT NULL default '0000-00-00 00:00:00'",
	};
		
	my $meta_fields = {
		'id'                => 1,
		'modified'          => 1,
		'modified_admin_id' => 1,
		'created'           => 1,
		'created_admin_id'  => 1,
	};
	my $create_fields = {}; #keep track of the fields we are going to create so we only try to do them once each ... (because sometimes dobjs specify the same field more than once and we only care about the first occurrence.)
		
	my $fields_sql = ["id int(10) unsigned NOT NULL auto_increment"]; #join with ,
	my $indexes_sql = ['PRIMARY KEY  (id)'];

	my $field_order = 1;
	my $field_sqls = { 'id' => { sql => $fields_sql->[0], field_order => $field_order }}; #2009 09 04 want to keep track of more things for alter table stuff.
	my $last_field_seen = 'id';
	my $index_sqls = { 'id' => $indexes_sql->[0] }; #2009 09 04 want to keep track of more things for alter table stuff.

	foreach my $field (@$fields) {
		#next if $skip_fld_types->{$field->{edit_fieldtype}}; #skip it.
		next if (!$field->{db_field_name}); #not much to do if it doesnt have a fieldname (perhaps its just a retype_email address field like today 2007 04 13 CMCEduFree)
		

		#fieldname type type-options
		my ($field_tablename, $fieldname) = ($field->{db_field_name} =~ /^(\S*)\.(\S*)$/) && ($1, $2);
		#$self->ch_debug(['_create_table: the tablename and fieldname are:', $field_tablename, $fieldname, 'based on', $field->{db_field_name} ]);
		#die "did that code work?";
		next if ($field_tablename ne $tablename); #skip it if it refers to a table other than our base table.
		next if $meta_fields->{$fieldname}; #shouldnt be making any of these in here.
		next if $create_fields->{$fieldname}; #or maybe we already set up for this one.
		$create_fields->{$fieldname} = 1; #so we know we did it and dont try to do it again for this field if it appears again.
		$field_order++;
		
		#2007 08 20, create indexes on specified fields too. woo.
		if ($field->{db_index}) {
			my $index_sql = "KEY $fieldname ($fieldname)";
			push(@$indexes_sql, $index_sql);
			$index_sqls->{$fieldname} = $index_sql;
		}

		my $field_type_opt_sql = undef;
		if ($field->{db_field_custom_type}) {
			#custom type and options coded in the fieldref?
			$field_type_opt_sql = $field->{db_field_custom_type};
		} else {
			#a field type and options descriptor for pre-defined type and option sets. (classic, simple way)
			my ($fld_type, $fld_opt) = (undef, undef);
			if ($field->{db_field_type} =~ m|(.*?)_(.*)|) {
				$fld_type = $1;
				$fld_opt = $2;
			} else {
				$fld_type = $field->{db_field_type};
			}
			#$self->{wa}->dbg_print([$field->{db_field_type}, $fld_type, $fld_opt]);
			if (!$field->{db_field_type} || !$fld_type) {
				#die "no field type for field param $field->{parameter_name} -- or maybe varchar(255) default NULL is a good default.";
				$fld_type = 'vc';
			}			
			#if no field opts, and its not a text field, try to put the 'default NULL' shit on there.
			if (!$fld_opt && ($fld_type ne 'text')) { 
				$fld_opt = 'n';
			}

			#determine field type string, handling any custom ones first (like decimal with custom non-default precisions)
			my $fld_type_str = undef;
			if ($fld_type =~ /decimal(\d+,\d+)/) {
				$fld_type_str = "decimal($1)";
			} elsif ($fld_type =~ /vc(\d+)/) {
				$fld_type_str = "varchar($1) character set utf8";
			} elsif ($fld_type eq 'enum') {
				if (!$field->{enum}) { die "enum fields should have an enum key with an arrayref of allowed values."; }
				$fld_type_str = 'enum(' . join(',', map {"'" . $_ . "'"} @{$field->{enum}} ) . ') character set utf8';
			} else {
				$fld_type_str = $fld_types->{$fld_type};
			}

			#$self->{wa}->dbg_print(["_create_table: I think '$fld_type', '$fld_opt', '$fld_type_str' is stupid for param $field->{parameter_name}"]);
			my $fld_opt_str = $fld_opts->{$fld_opt};
			if ($fld_opts_special->{$fld_type . '_' . $fld_opt}) {
				$fld_opt_str = $fld_opts_special->{$fld_type . '_' . $fld_opt}; #overrides of field options, mainly so that (2011 05 12) datetime_nn_0 works to set a date formatty default value.
			}
			if (($fld_opt eq 'nn_first') && ($fld_type eq 'enum')) {
				#nn_first is only for enum types, being added 2011 06 07, my birthday, I'm 32, I'm still fucking using this old code because it still fucking works wonderfully to save me from dealing with shit all the time :)
				$fld_opt_str .= "'" . $field->{enum}->[0] . "'";
			}

			if (!$fld_type_str)              { die "invalid field type $fld_type"; }
			if ($fld_opt && !$fld_opt_str)   { die "invalid field opt  $fld_opt"; }

			$field_type_opt_sql = $fld_type_str . ' ' . $fld_opt_str;
		}

		my $field_sql = '`' . $fieldname . '` ' . $field_type_opt_sql;

		push(@$fields_sql, $field_sql);	
		$field_sqls->{$fieldname} = { sql => $field_sql, after => $last_field_seen, field_order => $field_order }; #2009 09 04 track some more detailed stuffs for alter table code.
		$last_field_seen = $fieldname;
	}
	#finialize sql and add in a long string of meta fields and closing shit to finish it off.

	if (!$alter_table) {
		my $sql = "CREATE TABLE `$tablename` (" . join(', ', @$fields_sql) . ", created datetime NOT NULL default '0000-00-00 00:00:00', modified timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP, created_admin_id int(10) unsigned NOT NULL default '0', modified_admin_id int(10) unsigned NOT NULL default '0', " . join(', ', @$indexes_sql) . ") ENGINE=MyISAM DEFAULT CHARSET=latin1";
		$self->ch_debug(['going to create table with sql like: ', $sql]);
		#die "stop before doing sql!";
		$dbh->do($sql) or die "SQL error: " . $dbh->errstr();
		return 1;
	} else {
		#this alter table stuff is VERY PRELIMINARY it should be improved. i just want some basic add/drop/update non-meta fields stuff for now.

		my $sql = "DESC $tablename";
		my $sth = $dbh->prepare($sql);
		$sth->execute() or die $dbh->errstr . " with SQL of: $sql\n";
		my $found_fields = {};
		my $drop_fields  = {};
		my $add_fields   = {};
		while (my $row = $sth->fetchrow_hashref()) {
			my $found_fieldname = $row->{'Field'};
			
			next if $meta_fields->{$found_fieldname}; #i'm not prepared to be dealing with meta fields at all here in the alter table stuff yet. if they are missing then the table is a fuckshow to begin with just rebuild it with drop=>1.
			
			$self->ch_debug(['desced table row like:', $row ]);
			if (!$field_sqls->{$found_fieldname}) {
				$drop_fields->{$found_fieldname} = 1; #this field is not part of the data object any longer.
			} else {
				$found_fields->{$found_fieldname} = 1;
			}
		}
		#check our fields list now to make sure we found all of those, if not we have to add them.
		foreach my $fieldname (keys(%$field_sqls)) {
			next if $meta_fields->{$fieldname}; #i'm not prepared to be dealing with meta fields at all here in the alter table stuff yet. if they are missing then the table is a fuckshow to begin with just rebuild it with drop=>1.
			if (!$found_fields->{$fieldname}) {
				$add_fields->{$fieldname} = 1;
			}
		}

		$self->ch_debug(['_create_table in alter_table mode, here is fields sql:', $field_sqls, 'and indexes sql', $indexes_sql, 'kill fields:', $drop_fields, 'add fields:', $add_fields, ]);

		#a brute force kind of way would be to alter all exisitng fields, drop all fields that shouldnt exist and add all new fields at the end.
		my $drop_fields_sql = "ALTER TABLE `$tablename` " . join (', ', map { "DROP `$_`" } keys(%$drop_fields) );
		if (scalar(keys(%$drop_fields))) {
			$self->ch_debug(['_create_table for alter table, would drop fields with:', $drop_fields_sql ]);
			$dbh->do($drop_fields_sql) or die $dbh->errstr . " with SQL of: $drop_fields_sql\n";
		}
		#line below is fairly hairy. have to do them in the right order so they go AFTER the right stuff (and chain AFTER things that will be created before them), so sort keys of the add_fields list by their proper field order, then pull out the actual field create sql and finally determine what field this would would go AFTER (or FIRST if none, but I think id will always be first).
		my $add_fields_sql = "ALTER TABLE `$tablename` " .  join (', ', map { "ADD " . $field_sqls->{$_}->{sql} . ' ' . ($field_sqls->{$_}->{after} ? 'AFTER ' . $field_sqls->{$_}->{after} : 'FIRST') } sort {$field_sqls->{$a}->{field_order} <=> $field_sqls->{$b}->{field_order}} keys(%$add_fields) );
		if (scalar(keys(%$add_fields))) {
			$dbh->do($add_fields_sql) or die $dbh->errstr . " with SQL of: $add_fields_sql\n";
			$self->ch_debug(['_create_table for alter table, would add fields with:', $add_fields_sql ]);
			#die "stop";
		}
		##IDEA THAT JUST OCCURRED FOR RENAMING FIELDS ... right now with this code, renaming a field will cause it to be dropped and added agian under new name. But that will lose the data of the field. I would like to perhaps be able to pick up on a field property like field_renamed_from that would cause some different behavior here. but not doing that now. so dont rename fields!
		my $change_fields_sql = "ALTER TABLE `$tablename` " . join (', ', map { "CHANGE `$_` " . $field_sqls->{$_}->{sql}} keys(%$found_fields) );
		if (scalar(keys(%$found_fields))) {
			$dbh->do($change_fields_sql) or die $dbh->errstr . " with SQL of: $change_fields_sql\n";
			$self->ch_debug(['_create_table for alter table, would change fields with:', $change_fields_sql ]);
		}
		return 1;
	}
}
#On a related note ... see CMCReg::User::debug_explore for more oldies but goodies.
#	##Want to add some meta fields.
#	my $table_name = 'app_cookie_verification';
#	my $meta_fields = [
#		'ALTER TABLE `<%tbl%>` ADD `created` DATETIME NOT NULL',
#		'ALTER TABLE `<%tbl%>` ADD `modified` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP',
#		'ALTER TABLE `<%tbl%>` ADD `created_admin_id` INT NOT NULL',
#		'ALTER TABLE `<%tbl%>` ADD `modified_admin_id` INT NOT NULL',
#	];


#  
#  cmcreg_client_signup_id int(10) unsigned NOT NULL default '0',
#  address1 varchar(255) default NULL,
#  address2 varchar(255) default NULL,
#  address3 varchar(255) default NULL,
#  phone varchar(255) default NULL,
#  fax varchar(255) default NULL,
#  city varchar(255) default NULL,
#  state_id int(10) unsigned default NULL,
#  country_id int(10) unsigned NOT NULL default '0',
#  postal varchar(10) default NULL,
#
#}

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

sub _alter_table {
	my $self = shift;
	
	#would be nice to be able to go look at the table in the db, and find any fields in that table that 
		#DONT BELONG and remove them,
		#NEED TO BE ADDED and add them
		#FORMAT DIFFERS, change it.
}

1;
