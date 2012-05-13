package SpApp::DataObj::SupportObj::EditMode;
use base SpApp::DataObj::SupportObj;
use SpApp::DataObj::SupportObj::EditModeInternals;
use strict;

sub _custom_init {
	my $self = shift;
	my $objrefs = shift;
	my $data_obj_constructor_args = shift; #dont need yet, but just want to have.
	$self->{emi} = SpApp::DataObj::SupportObj::EditModeInternals->new($self->{'do'}, $data_obj_constructor_args);
	$self->{emi}->_standard_init($objrefs, {}, $data_obj_constructor_args);
	#weaken($self->{emi});
}
	
sub editform_spec {
	my $self = shift;
	my $ef_spec = shift;
	my $other_args = shift;

	#getter/setter for edit form_spec.
	if ($ef_spec) {
		#set it
		$self->{'do'}->{ef_spec} = $ef_spec;
	} else {
		#get it ... if it doesnt exist, make it.
		$ef_spec = $self->{'do'}->{ef_spec};
		if (!$ef_spec || $other_args->{'reset'}) {
	 		$ef_spec = {
				form => $self->{'do'}->{form_spec}->{form}, 
				#fields => \@{$self->{'do'}->{form_spec}->{fields}}, #that should take a copy of the list of field references.
				fields => [ @{$self->{'do'}->{form_spec}->{fields}} ], #that should take a copy of the list of field references.
			};
			$self->{'do'}->{ef_spec} = $ef_spec;
			$self->{'do'}->{ef_specced} = 1;
		}
		return $ef_spec;
	}	
}

sub get_editform {
	my $self = shift;
	my $args = shift;
	
	#get the fields for an editform representation. possibly of a particular record id. possibly retried for some specific screen.
	$self->ch_debug(['get_editform: here with args like: ', $args ]);

	if (!$self->{'do'}->{form_spec}) {
		$self->error('get_editform: please initialize or otherwise set a form_spec first.');
		return $self->{'do'};
	}
	
	#make an editform spec from the form and a clone of the fields.
		#retrying?
			#get the already-editform (better be, haha) set-up fields from the session
			#
	#establish the row selection SQL based on the standard form_spec fields we just cloned
	#prep the fields for editform display / ordering 
	#perform the SQL and plug into the searchform-prepped fields.

	my $ef_spec = $self->editform_spec(undef, {'reset'=>1});
	
	my $retry_form      = $args->{retry_form};
	my $for_screen      = $args->{for_screen};
	my $record_id_param = $args->{record_id_param} ? $args->{record_id_param} : 'record_id';
	my $record_id       = $self->{'do'}->record_id();
	my $record_error    = 0; #if we got a record_id but didnt obtain a record, thats an error.
	my $editform_error  = {}; #the report we get
	my $has_error         = 0; #the fact of the matter about errors
	my $has_error_message = 0; #the fact of the matter about error messages.

	if ($retry_form) {
		#retry a failed submission by repopulating form fields from cgi values that were saved in the session.
		#i think it would be an error to not have a screen name here.
#		$ef_spec->{fields} = $self->{emi}->_session_fields(undef, { load_for_screen => $for_screen });
		$self->{emi}->_session_fields({ load_for_screen => $for_screen }); #will load field from session into any registered fspec. (f, sf, ef).

		if ($args->{retry_revalidate}) {
			$self->ch_debug(['get_editform and going to validate field values of the ef_spec']);
			$editform_error = $self->{emi}->_validate_field_values($ef_spec->{fields}, { inspect => 'cgi' });
			if ($args->{validate_callback}) {
		
				my $callback_func = $args->{validate_callback};
				my $callback_args = {
					data_obj  => $self->{'do'},
					actions   => {}, #no actions here, we're just after setting up validation info.
					formerror => $editform_error, #able to update this
				};
				if ($args->{validate_callback_args} && (ref($args->{validate_callback_args}) eq 'HASH')) {
					$callback_args = { %{$args->{validate_callback_args}}, %$callback_args }; #let it be merged!
				}
				eval '$self->{wa}->$callback_func($callback_args)';
				die "Error executing DataObj->pickup_and_sessionize_cgi_values for the validate_callback action: $@" if $@;
				#automatic formlevel flagging. nothing prevents validate callback from doing all the work, but i think this would be handy. i dont think we'd ever want to NOT set these flags if the form has any error messages set. 
			}
			#save fields in session. I suppose we might have just done something to them in the not_ok callback, but probably not.
			#$self->{emi}->_session_formerror({ error => $editform_error, save_for_screen => $save_for }); #i have no idea what I'm doing now. just winging it. hoping to find a useful pattern out of this.
		} else {
			#not doing retry_revalidate ... so just try to load an error we might have saved when first submitting.
			$editform_error = $self->{emi}->_session_formerror({ load_for_screen => $for_screen });
		}
				
		if ($editform_error->{baddata_error_messages})  { $editform_error->{baddata_error}  = 1; $editform_error->{validated} = 0; }
		if ($editform_error->{nodupe_error_messages})   { $editform_error->{nodupe_error}   = 1; $editform_error->{validated} = 0; }
		if ($editform_error->{required_error_messages}) { $editform_error->{required_error} = 1; $editform_error->{validated} = 0; }
		
		if (exists($editform_error->{validated}) && !$editform_error->{validated}) {
			$has_error = 1;
		}
		if ($editform_error->{required_error_messages} || $editform_error->{baddata_error_messages} || $editform_error->{nodupe_error_messages}) {
			$has_error_message = 1;
		}
					
		$self->ch_debug(['here with these form errors:', $editform_error, $self->{wa}->session()->param('_data_obj_saved_formerrors')]);
		#die "jere with ereres";
			
		#experiment with session_form as well. 2007 04 12 b/c I am unsure of any better way to be able to pass around complex form error information.
			#I _think_ I only want to do this if retrying the form. and I think right now I only want to save to it in process_form_submission upon an error.
		#$ef_spec->{form}   = $self->{emi}->_session_form(undef, { load_for_screen => $for_screen });

#		$self->ch_debug(['get_editform: retrying the form -- should be loading error-flagged fields from the session -- working with this record id: ', $record_id, 'the name in the session the fields were obtained from is: (and fields follow)', $for_screen, $ef_spec->{fields} ]);
		$self->ch_debug(['get_editform: retrying the form -- should be loading error-flagged fields from the session -- working with this record id: ', $record_id, 'the name in the session the fields were obtained from is:', $for_screen, 'the efspec is', $ef_spec]);
		$self->{emi}->_standard_editform_field_postprocessing($ef_spec->{fields}, {inspect => 'cgi'}); #repopulate fields edit_value(s) from cgi_values(s), as was saved in session.
	} else {

		if ($record_id) {
			#edit an existing record by populating fields from the db
			$self->ch_debug(['get_editform: should be building sql for this record id: ', $record_id]);
			my $select_sql = $self->{sa}->_build_select_sql($ef_spec, {record_id => $record_id, for_editform => 1}); #need to use the editform sql field formatting.
			$self->{emi}->_standard_editform_fields($ef_spec->{fields});
			#$self->ch_debug(['get_editform: fields are currently like (1): ', $ef_spec->{fields} ]);
			my $select_other_args = {record_id => $record_id, output_style => 'edit' };

			#pass forward. adding 2007 05 15 for viewform to show a plaintext rendering of the html from RTE fields.
			if ($args->{plaintext_html}) { $select_other_args->{plaintext_html} = 1; }
			if ($args->{wrap_text})      { $select_other_args->{wrap_text} = 1; }
			if ($args->{output_style})   { $select_other_args->{output_style} = $args->{output_style}; }

			my $obtained_record = $self->{sa}->_perform_select($select_sql->{sql}, $select_sql->{bind_params}, $ef_spec, $select_other_args);
			#$self->ch_debug(['get_editform: fields are currently like (2): ', $ef_spec->{fields} ]);
			if ($obtained_record) { 
				$self->{do}->_augment_editmode_values({ fields => $ef_spec->{fields}, target => 'db' }); #2008 04 17 experimentally adding this so the idl checkbox for allcategory applicability which is NOT part of the record, which is really for two separate flags in the record, can get a value.
				$self->{emi}->_session_fields({ save_for_screen => $for_screen });
				$self->{emi}->_standard_editform_field_postprocessing($ef_spec->{fields}, {inspect => 'db'}); #load field edit_value(s) from db_value(s)
				#$self->ch_debug(['get_editform: fields are currently like (3): ', $ef_spec->{fields} ]);
			} else {
				$record_error = 1; 
			}
		} else {
			#create a new record. first clear away any saved session vars for the related screen.
			$self->{emi}->_session_fields({ clear_for_screen => $for_screen }); #clear anything thats there
			#$self->ch_debug(['get_editform: no record id requested. should show the editform in a new entry mode.', 'the funstack is:', $self->{wa}->session()->param('_data_obj_saved_fields')]);
			if ($args->{add_editform_fields}) {
				#adding for CMCmarketsFX USA to slam some non-db-bound CC fields into the form. Hoping this will work out ok. (and that I can process them in a process_form_submission callback!)
				$self->{emi}->_add_editform_fields($ef_spec, $args->{add_editform_fields});
			}
			$self->{emi}->_standard_editform_fields($ef_spec->{fields});
			$self->{emi}->_session_fields({ save_for_screen => $for_screen }); #then set a clean set of fields.
			#2007 04 03 experiment: I want to not reset the values to defaults because I want to use the values of a dataobj who's record I just cleared as the values for a new record presented in a designed editform.
			unless ($args->{skip_postprocessing_for_no_record_id}) {
				$self->{emi}->_standard_editform_field_postprocessing($ef_spec->{fields}, {inspect => 'edit_default'}); #so this is like the new entry thing. not retrying, dont have a record id, so just take the basic form_spec, and process to stick in the edit_default_value(s).
			}
		}

		#i think its safe to say that if we are not retrying, we dont have form errors, and in fact we're probably showing the form for the first time .. i think I want to clear any saved formerrors.
		$self->{emi}->_session_formerror({ clear_for_screen => $for_screen }); 

		#2008 11 27 captcha experiment
		if ($args->{include_captchas}) {
			$self->{emi}->_prepare_captchas($ef_spec->{fields}); 
		}

	}
	
	#return something that can just be handed off to a tmpl.
	if ($record_error) {
		$self->error("get_editform record error -- record id supplied but no matching record found in db");
		return $self->{'do'};
	} else {

		## commenting out the below since we are now using $self->editform_spec();
		# ... might want to do something with it later too .. keep it around in the object.
		##$self->{'do'}->{ef_spec} = $ef_spec;

		##ensure return hashref has a key for rte_support if any fields are type TEXTINPUT_RICH
		#my $rte_support_required = 0;
	
		#return in such a way for sending shit directly to a template.
		return {
			record_id => $record_id, #record_id could be undef.
			form_name => $ef_spec->{form}->{name}, #just to have a var with a better name than 'name'
			fields    => $ef_spec->{fields},
			retry_form => $retry_form, #adding so that if we have to retry a form we can add some error text to the form at the top or wherever.
			sql       => $self->{sa}->{last_select_sql}, #for debug
			sql_binds => $self->{sa}->{last_select_sql_binds}, #for debug
			record_id_param => $record_id_param,

			%{$ef_spec->{form}},
			%$editform_error,
			has_error => $has_error,
			has_error_message => $has_error_message,
			
			ajax_support_required      => ($ef_spec->{form}->{edit_ajax_field_validation} ? 1 : 0), #same deal as above.		
			toolman_support_required   => ($ef_spec->{form}->{edit_ajax_field_validation} ? 1 : 0), #ajax validation requires some other help from toolman libs (events stuff)
			rte_support_required       => ($ef_spec->{form}->{editform_has_rte} ? 1 : 0), #template flag to load rte support js code, should only get sent to template when actually rendering an editform (otherwise whats the point?!). Why not just use the editform_has_rte to control loading of the js? because I may very well want rte_support_required for things completely outside of editforms. editform_has_rte means something very specific in the form that happens to also mean rte_support_required. same for the other js loading flags, the fact of the matter is that the js could be required for other things and so I dont want to end up including it based on stupid and confusing names I instead want to be very direct and purposeful!
			calendar_support_required  => ($ef_spec->{form}->{editform_has_dateinput} ? 1 : 0), #template flag to load calendar support js code, should only get sent to template when actually rendering an editform (otherwise whats the point?!)
			fileinput_support_required => ($ef_spec->{form}->{editform_has_fileinput} ? 1 : 0), #mainly to be able to set the right enctype for the <form> tag when a fileupload field(s) are present. possibly do away with this and ALWAYS use that enctype, but for now just change it as needed!
		};
	}

}


#2007 02 05 I _really_ want to be able to search for a record to edit. I dont know its ID, but I know other things about it (like the activate code). So I want to basically search for it and tell it some whereclause blocks or seomthing, and use the first record I find. 
#i also might want to be able to tell it to give me searchform fields of the thing
	#nomenclature Q ... find_ or search_ ... record_for_edit ?? dunno. going with 'find' b/c I want to keep 'search' to relate to searchform modes of things.
sub find_record_for_edit {
	my $self = shift;
	my $args = shift;
	
	if (!$self->{'do'}->{form_spec}) {
		$self->error('find_record_for_edit: please initialize or otherwise set a form_spec first.');
		return $self->{'do'};
	}
	if (!$args->{criteria}) {
		$self->error('find_record_for_edit: please provide criteria by which to restrict the search results.');
		return $self->{'do'};
	}
	
	#2008 07 14, lets say that if we are here, we are setup right, and we should make sure that we dont have lingering error conditions from previous use set in here.
	$self->clear_error(); 

	my $ef_spec = $self->editform_spec(undef, {'reset'=>1});
	#$self->ch_debug(['find_record_for_edit: with ef_spec like: ', $ef_spec ]);

	my $record_error    = 0; #if we didnt find a record, thats an error. (is it?)

	#edit an existing record by populating fields from the db
#	$self->ch_debug(['find_record_for_edit: should be building sql for this search criteria (restrictions): ', $args->{criteria}]);
	my $select_sql = $self->{sa}->_build_select_sql($ef_spec, {restrict => $args->{criteria}, for_editform => 1}); #need to use the editform sql field formatting.
	$self->{emi}->_standard_editform_fields($ef_spec->{fields});
	
	#$self->{wa}->dbg_print(['something is fuxored:', $args, $select_sql ]); #what was fuxored was the stuff about return $self if $self->error() in the sql functions ... b/c not finding a record at some point set a nonfatal error condition ... and that older sql code didnt handle that properly .. fixed!
	
	my $obtained_record_id = $self->{sa}->_perform_select($select_sql->{sql}, $select_sql->{bind_params}, $ef_spec, {single_record_search => 1 });
	if ($obtained_record_id) { 
		#so if we _found_ a record (and we did this b/c we didnt know its id, otherwise we would have done load_ not find_!) then we should bloody well set the record_id!
		$self->{'do'}->record_id($obtained_record_id); #set it and forget it the popiel way.

		$self->{emi}->_standard_editform_field_postprocessing($ef_spec->{fields}, {inspect => 'db'}); #load field edit_value(s) from db_value(s)
		#$self->ch_debug(['find_record_for_edit: obtained a record. fields look like:', $ef_spec->{fields}]);
		$self->ch_debug(['find_record_for_edit: obtained a record. got record id: ', $self->{'do'}->record_id() ]);
		#$self->{wa}->dbg_print(['find_record_for_edit: obtained a record. got record id: ', $self->{'do'}->record_id(), 'ef spec', $ef_spec ]);
	} else {
		#did not find a match. this used to always be an error. then it was the first nonfatal error ever. now, i want to ability to recover by automatically creating a new record based on the SIMPLE search restrictor criteria.
		$self->ch_debug(['find_record_for_edit: did not find a record ... that might be ok.' ]);

		#the way I'm using it sometimes nowadays i should make sure there is never an old record id hanging around.
		$self->{'do'}->clear_record_id();

		if ($args->{or_new}) {
			$self->{emi}->_standard_editform_field_postprocessing($ef_spec->{fields}, {inspect => 'edit_default'});
			my $default_value_overrides = {};
			foreach (keys(%{$args->{criteria}})) {
				if (!ref($args->{criteria}->{$_})) {
					$default_value_overrides->{$_} = $args->{criteria}->{$_};
				}
			}
			$self->set_values($default_value_overrides);
			
		} else {
			#if we didnt find a record and we were not told "or_new" we wont be doing anything special other than bailing.
			
			$record_error = 1; 
			#so if we can't find a record we die? that doesnt really sound like the desired behavior. since we're "finding" a record, I think it quite reasonable that sometimes we'd come up empty-handed.
				#umm yeah no. just tried to do a CMCreg activate with a bogus code, and i died b/c of this error .. UNACCEPTABLE. sooo out it goes.
				#no no wait ... non-fatal errors. a good time to attempt a start at that now.
			$self->error("find_record_for_edit record error - criteria did not yield any matching record from db", { nonfatal => 1 });
		}
	}

	return $self->{'do'}; #for chaining operations.
}

#select a record based on the record id, and if we get it, set up the ef_spec in the object.
	#i want to call this edit_record, but I'm not really editing it I'm loading it so it can BE edited. I dont like the name select_record but its the most fitting I can come up with atm. ... bla ok changed it to load_record_for_edit .. .too long but ... apropriate.
sub load_record_for_edit {
	my $self = shift;
	my $args = shift;
	
	#2007 02 05 - I want to be able to pass an arg for the record id. just means more flexibility.
	if ($args->{record_id}) { $self->{'do'}->record_id($args->{record_id}); }

	#this is based off the get_editform -- cept its meant to be simple, getting the record and setting the fields into the object, no session or anything. 
		#wanting it so that I can quickly edit a record, by saying load_record_for_edit, doing things to it via the object, then saving it.
	#one other thing of note is that in get_editform we will NOT overwrite the form_spec fields of the object, we'll save them in a separate ef_spec. here we will actually save 
	if (!$self->{'do'}->{form_spec} || !$self->{'do'}->record_id()) {
		$self->error('load_record_for_edit: please initialize or otherwise set a form_spec AND a record_id first.');
		return $self->{'do'};
	}

	#2011 01 13, lets say that if we are here, we are setup right, and we should make sure that we dont have lingering error conditions from previous use set in here.
	$self->clear_error(); 

	my $ef_spec = $self->editform_spec(undef, {'reset'=>1});

	my $record_id       = $self->{'do'}->record_id();
	my $record_error    = 0; #if we got a record_id but didnt obtain a record, thats an error.

	#edit an existing record by populating fields from the db
#	$self->ch_debug(['load_record_for_edit: should be building sql for this record id: ', $record_id]);
	my $select_sql = $self->{sa}->_build_select_sql($ef_spec, {record_id => $record_id, for_editform => 1}); #need to use the editform sql field formatting.
	$self->{emi}->_standard_editform_fields($ef_spec->{fields});
	my $obtained_record = $self->{sa}->_perform_select($select_sql->{sql}, $select_sql->{bind_params}, $ef_spec, {record_id => $record_id });
	if ($obtained_record) { 
		$self->{emi}->_standard_editform_field_postprocessing($ef_spec->{fields}, {inspect => 'db'}); #load field edit_value(s) from db_value(s)
		#$self->ch_debug(['load_record_for_edit: obtained record. fields look like:', $ef_spec->{fields}]);
	} else {
		$record_error = 1; #yarr we dont actually do anything with this in this func heh (see 2009 04 15 note below)

		#2009 04 15 I was strongly debating putting a call to clear_record_id() in here if we didnt load one. however that would cause new behavior of actually inserting a new record if this non-loaded-record had edit_values set on it and was then saved. I think I'd like the current behavior of silently updating the non-existent record to continue. 
		#so DONT clear the record id here. also for proper reusabliity if we DID do that, we'd probably need to do some standard_editform_field_postprocessing to get listoptions set up and stuff properly.
		#2010 10 08 - side project, i dont work for SPI anymore lol. I note that the find_record_for_edit can be used to load a record by record_id (or probably by id if that field called id happens to be in the obj, code says record_id is handled specially for restrictors tho evern if the field isnt in the set) and it DOES clear record id if it doesnt load a record
				
		#$self->error("load_record_for_edit record error -- record id $record_id supplied but no matching record found in db");
	}

	return $self->{'do'}; #for chaining operations.
}

sub new_record_for_edit {
	my $self = shift;
	my $args = shift;
	
	#ripped from func above load_record_for_edit -- modding to make sure there is no record id and make sure the ef spec is set. this could be obsoleted if deemed stupid in the future for whatever reason.
	#and just like there we arent doing anything with session fields at all.
	
	#should we be preselecting a record id? maybe.
	
	if (!$self->{'do'}->{form_spec}) {
		$self->error('new_record_for_edit: please initialize or otherwise set a form_spec first.');
		return $self->{'do'};
	}

	#2011 01 13, lets say that if we are here, we are setup right, and we should make sure that we dont have lingering error conditions from previous use set in here.
	$self->clear_error(); 

	$self->{'do'}->clear_record_id();

	my $ef_spec = $self->editform_spec();

	#set up fields of a new record by populating fields from the edit_default attribs.
	$self->{emi}->_standard_editform_fields($ef_spec->{fields});
	$self->{emi}->_standard_editform_field_postprocessing($ef_spec->{fields}, {inspect => 'edit_default'});
	#$self->{wa}->dbg_print(['new_record_for_edit: form spec here1:', $ef_spec ]);

	#2007 08 29, not sure why I never did this yet ... notice how nothing else uses the $args there ... sooo .. the $args are the default edit values!
	if (ref($args) eq 'HASH') {
		$self->set_edit_values($args);
	}

	#$self->{wa}->dbg_print(['new_record_for_edit: form spec here2:', $ef_spec ]);

	return $self->{'do'}; #for chaining operations.
}

sub set_edit_values {
	my $self = shift;
	my $params = shift; #hashref of parameter_name => edit_value for us to set.
	my $other_args = shift; #any behavior to control?
	$other_args->{target} = 'edit';
	return $self->set_values($params, $other_args);
}

sub set_values {
	my $self = shift;
	my $params = shift; #hashref of parameter_name => edit_value for us to set.
	my $other_args = shift; #any behavior to control?
	
	my $target = 'edit';
	if ($other_args->{target}) { $target = $other_args->{target}; }

	my $ef_spec = $self->{'do'}->{ef_spec}; #even though we have $self->editform_spec now, I think I still want to access this like so, that way we are guaranteed to get the error condition if it hasnt been prepped already and we want to make sure that other things which happen during the allowed prepping methods do in fact take place. at least I think thats the reasoning.
	if (!$ef_spec) {
		$self->error("set_edit_values: cannot continue without an ef_spec being set already. did you call load_record_for_edit or anything first?");
		return $self->{'do'};
	}
	
	my $fields = $ef_spec->{fields};
	my $merged_fields = $self->{fp}->_get_merged_fields_and_subfields($fields);

	foreach my $field (@$merged_fields) {
#	foreach my $field (@$fields) {
		if (exists($params->{$field->{parameter_name}})) { #added exists check, b/c if it exists but is set to undef, we do in fact want to plug undef in.
			$field->{$target . '_value'} = $params->{$field->{parameter_name}};
		}
	}
	
	return $self->{'do'}; #for chaining operations.
}

#gives UNDERLYING values only.
#Only call this if you want $value_attrib in there to be "edit_value" ... first arg is hashref of params you want.
sub get_edit_values {
	my $self = shift;
	my $params = shift; #hashref of parameter_name => edit_value for us to get.
	my $other_args = shift; #any behavior to control?
	$other_args->{inspect} = 'edit';
	return $self->get_values($params, $other_args);
}

#gives DISLPLAY (looked up if able to, otherwise underlying) values only.
sub get_edit_display_values {
	#this is just for convenience because I keep fucking up calls like get_edit_values(undef, {display => 1}).
		#if I want more control, just code the request for get_values or get_edit_values properly!
	my $self = shift;
	return $self->get_edit_values(undef, {display => 1});
}

sub get_display_values {
	#this is just for convenience because I still keep fucking up calls. and dont want to write so much.
	my $self = shift;
	my $args = shift;
	if (!$args->{inspect}) {
		die "get_display_values NEEDS to be told what to inspect. If you wanted to inspect 'edit', golly you should be calling get_edit_display_values instead.";
	}
	return $self->get_values(undef, {display => 1, inspect => $args->{inspect}});
}

#Probably what you want if its not just the edit_value you want.
#IMPORTANT: First arg is the hashref of param names you want back. supply undef if you want them all.
#						Second arg is the control hashref. usually you just want {inspect=>'something'} there where 'something' is 'save' or 'cgi' or whatever. (if it was 'edit' you could have just called get_edit_values)!
sub get_values {
	my $self = shift;
	my $params = shift; #hashref of parameter_name => 1 for us to get. (the values dont matter its just the keys we'll look up) -- I decided to do this as a separate method than having a generic setter/getter because I fear that a generic setter_getter would result in bad programming style in the calling functions.
	my $other_args = shift; #any behavior to control?

	my $inspect = 'edit';
	if ($other_args->{inspect}) { $inspect = $other_args->{inspect}; }

	my $ef_spec = $self->{'do'}->{ef_spec}; #even though we have $self->editform_spec now, I think I still want to access this like so, that way we are guaranteed to get the error condition if it hasnt been prepped already and we want to make sure that other things which happen during the allowed prepping methods do in fact take place. at least I think thats the reasoning.
	if (!$ef_spec) {
		#hrm I am inadvertengly causing this error a lot -- maybe i should automatically do load_record_for_edit if theres a record id or something.
		$self->error("get_values: cannot continue without an ef_spec being set already. did you call load_record_for_edit or anything first?");
		return $self->{'do'};
	}
	
	#i want a way to ask for just one value and get a scalar back.
	my $value_attrib = $inspect . '_value';
	if ($other_args->{display}) {
		$value_attrib .= '_disp';
	}	
	
	my $return_values = {};
	#include record_id because that just feels nice 2007 03 22 (also b/c if we did a find_for_edit thing then we dont know it and just want to access it via get_edit_values without having to ask object for record id. oh on second thought asking object for record id really is same thing. hrm .well why not do it anyway here, flexible is good. these values are always derivative anyway, and setting ones with params that have no matching fieldref (which record_id never should) then it will be discarded and wont ever matter.
		#also, if that was the single value queried for (which is happening with relationships that want to use the record_id pseudofield), it probably is NOT among the actual fieldrefs, so just return it.
	if ($params && $params->{record_id} && $other_args->{'single_value'}) {
		return $self->{'do'}->record_id();
	}
	$return_values->{record_id} = $self->{'do'}->record_id();

	my $fields = $ef_spec->{fields};
	my $merged_fields = $self->{fp}->_get_merged_fields_and_subfields($fields);
	#$self->ch_debug(['data_obj get_values: fields of the ef_spec are like:', $fields]);

	foreach my $field (@$merged_fields) {
#	foreach my $field (@$fields) {
		if ($params) {
			#we were given a hashref of specific parameter names to fish out.
			if ($params->{$field->{parameter_name}}) {
				if ($other_args->{'single_value'}) {
					return $field->{$value_attrib};
				} else {
					$return_values->{$field->{parameter_name}} = $field->{$value_attrib};
				}
			}
		} else {
			#we were not told which specific parameter values to fish out, so get them all. note the single_value shit can't happen here -- which should be duh because we wouldnt know which single value to fish out. duh.
			$return_values->{$field->{parameter_name}} = $field->{$value_attrib};
		}
	}
	$self->ch_debug(["data_obj get_values: (pulling values from '$value_attrib') going to return this:", $return_values]);

	if ($other_args->{'single_value'}) {
		$self->ch_debug(['get_values: single value requested, but not found, error condition will happen, args were:', $params, $other_args ]);
		$self->error("get_values: error, was asked for a single value but didnt encounter a field with that parameter_name while looking for it.");
	}
	return $return_values;	
}

#2007 03 27 adding another get_values type function, b/c I want one which sets things up the way results_simple in search results are, with the _lkp and the _disp values all included together. actually a lot like FP::_fields_simple_values. maybe should piggy back off that since its already written.
	#in fact it gives another use to the FTP::_fields_simple_values and is relaly probably the only thing I'm going to need to call in place of get_edit_values/get_edit_display_values. 
	#can pass fields in, if you dont they'll be self-obtained from an already existing self->{ef_spec} which if not found will cause it to bail.
sub get_allvals {
	my $self = shift;
	my $args = shift; #any behavior to control? note you dont ask for params from this .. you just get allvals! _disp too! motherfucker!
	
	my $inspect = 'edit';
	if ($args->{inspect}) { 
		$inspect = $args->{inspect};
	} else {
		$args->{inspect} = $inspect; #so that we always have something to pass to _fields_simple_values.
	}

	my $fields = $args->{fields};
	if (!$fields) {
		my $ef_spec = $self->{'do'}->{ef_spec}; #even though we have $self->editform_spec now, I think I still want to access this like so, that way we are guaranteed to get the error condition if it hasnt been prepped already and we want to make sure that other things which happen during the allowed prepping methods do in fact take place. at least I think thats the reasoning.
		$self->ch_debug(["get_allvals: just pulled in a ef_spec indirectly. it is $ef_spec"]);
		if (!$ef_spec) {
			#hrm I am inadvertengly causing this error a lot -- maybe i should automatically do load_record_for_edit if theres a record id or something.
			$self->error("get_allvals: cannot continue without an ef_spec being set already. did you call load_record_for_edit or anything first?");
			return $self->{'do'};
		}
		$fields = $ef_spec->{fields};
	}

	#$self->ch_debug(["get_allvals: here, and going to fish values out of: ", $fields ]);

	my $merged_fields = $self->{fp}->_get_merged_fields_and_subfields($fields);
	#$self->ch_debug(['data_obj get_values: args were:', $args, 'I think I need to look to inspect: ', $inspect, 'and fields of the ef_spec are like:', $merged_fields,]);

	my $return_values = $self->{fp}->_fields_simple_values($merged_fields, $args);

	#include record_id because that just feels nice
	$return_values->{record_id} = $self->{'do'}->record_id();

	return $return_values;	
}

#2007 04 04 ok i promise this is the LAST values function. this one is designed as a getter/setter for a single value!
	#public access via dobj 'val' function.
sub get_set_value {
	my $self = shift;
	my @data = (@_);

	#$self->ch_debug(['get_set_value with initial data:', \@data, 'status of ]);

	my $args = {};
	if (scalar(@data) == 3 && ref($data[2]) eq 'HASH') {
		$args = pop(@data);
	} elsif (scalar(@data) == 2 && ref($data[1]) eq 'HASH') {
		$args = pop(@data);
	}
	
	my $inspect = 'edit';
	if ($args->{inspect}) { $inspect = $args->{inspect}; }
	my $value_attrib = $inspect . '_value';

	my $allvals = 0; #could return foo, foo_disp, etc in a hashref .. but not doing that yet.
	my $param = $data[0];

	my $field = $self->{'do'}->{_fieldrefs}->{$param};
	if (!$field) { $self->error("no fieldref found for param $param"); }

	#$self->ch_debug(['get_set_value with data, args, value attrib, param, field, editform_spec, of:', \@data, $args, $value_attrib, $param, $field, $self->{'do'}->editform_spec() ]);
	
	if (scalar(@data) == 2) {
		#two items passed, assume we are setting a value.
		$field->{$value_attrib} = $data[1];
		return $self->{do};
	} elsif (scalar(@data) == 1) {
		#one item passed, assume we are retrieving a value.
		if ($allvals) {
			#all the values that are used in this field. return as hashref.
			my $return_allvals = {};
			$return_allvals->{$param} = $field->{$value_attrib};
			my $disp_value_from = $value_attrib;
			if ($field->{looked_up}) {
				$return_allvals->{$param . '_lkp'} = $field->{$value_attrib . '_lkp'};
				$disp_value_from = $value_attrib . '_lkp';
			}
			if ($field->{formatted}) {
				$return_allvals->{$param . '_fmt'} = $field->{$value_attrib . '_fmt'};
				$disp_value_from = $value_attrib . '_fmt';
			}
			$return_allvals->{$param . '_disp'} = $field->{$disp_value_from};
			return $return_allvals;
		} else {
			#just the value.
			return $field->{$value_attrib};
		}
	} else {
		$self->{wa}->debuglog(['illegal usage of get_set_value with args like:', \@data, $args]);
		$self->error("illegal usage of get_set_value");
	}
}

sub get_edit_errors {
	#util func to get an easy mapping of parameter_name => {errors flags hashref}
	my $self = shift;
	my $args = shift;
	
	if (!$self->{'do'}->{form_spec}) {
		$self->error('get_editform: please initialize or otherwise set a form_spec first.');
		return $self->{'do'};
	}
	
	my $ef_spec = $self->editform_spec();

	my $return_values = {};
	foreach my $field (@{$ef_spec->{fields}}) {
		$return_values->{$field->{parameter_name}} = {};
		foreach ('field_error', 'required_error', 'field_dupe_error', 'baddata_error') {
			if ($field->{$_}) {
				$return_values->{$field->{parameter_name}}->{$_} = 1;
			}
		}
	}

	return $return_values;	
}

#this is a util function being added for CMCReg redev work. I am having a few data objects with similar fields and I just want to copy some values, and there very much is a pattern. basically:
	#the target object can give us its empty fields, then we have the list of params we want to fill.
	#we must be told what the prefix of the source/inspect fields is (so we can strip it)
	#we must be told what the prefix of the target fields is (we we can apply it to the stripped inspect param name)
	#then we just go over all the params that we are targetting, and pull from the source.
	#we will default to setting 'edit' value (edit_value) but can be given an override target attrib.
	#also thinking if parameter names are really out of whack we can be given a mapping of what goes where... but not doing that just yet.
sub set_values_from_similar {
	my $self = shift;
	my $args = shift;
	
	#$self->{wa}->dbg_print(['set_values_from_similar: 1 .. here with args like:', $args]);

	my $target = 'edit';
	if ($args->{target}) { $target = $args->{target}; }
	my $value_attrib = $target . '_value';
	
	my $ef_spec = $self->{'do'}->{ef_spec}; #even though we have $self->editform_spec now, I think I still want to access this like so, that way we are guaranteed to get the error condition if it hasnt been prepped already and we want to make sure that other things which happen during the allowed prepping methods do in fact take place. at least I think thats the reasoning.
	if (!$ef_spec) {
		#hrm I am inadvertengly causing this error a lot -- maybe i should automatically do load_record_for_edit if theres a record id or something.
		$self->error("set_values_from_similar: cannot continue without an ef_spec being set already. did you call load_record_for_edit or anything first?");
		return $self->{'do'};
	}
	
	if (!$args->{source_values}) {
		$self->error("set_values_from_similar: cannot continue without source values being provided.");
		return $self->{'do'};
	}

	#maybe we only want to override a subset of the target_values? if so, they'd be identified in a params arg.
	my ($target_params, $source_prefix, $target_prefix, $target_to_source_map) = (undef, undef, undef, undef);
	if ($args->{target_params}) {$target_params = $args->{target_params}; } #they'd need to name the target parameters to fill since we'll filter the target fields to loop over based on them.
	if ($args->{source_prefix}) {$source_prefix = $args->{source_prefix}; } #prefix on all the source parameters
	if ($args->{target_prefix}) {$target_prefix = $args->{target_prefix}; } #prefix on all the target parameters (so we can strip it off, add the source prefix, and then look for the source value)
	if ($args->{target_to_source_map}) {$target_to_source_map = $args->{target_to_source_map}; } #this would HAVE to be target_param => source_param.

	my $fields = $ef_spec->{fields};
	#if just explicitly targeting certain params, filter for those. we dont HAVE to do this and it means we'll just waste some cycles if we dont do this but have untargetted fields in the mix.
	if ($target_params) {
		$fields = [ grep { $target_params->{$_->{parameter_name}} } @$fields ];
	}

	foreach my $field (@$fields) {
		#if we were given a mapping of target_param to source_param, we can just use what was provided.
		#otherwise, we should have a prefix of the source params and the target params. then we can strip the target prefix off, add the source prefix.
		 #then look for the source value based on what we have decided is the source param using the rules above.
		my $src_param = undef;

		#a few ways to find the source parameter for where to get the value to set into this field 
		if ($target_to_source_map && $target_to_source_map->{$field->{parameter_name}}) { 
			#explicitly told?
			$src_param = $target_to_source_map->{$field->{parameter_name}}; 
		} elsif ($source_prefix && $target_prefix) {
			#source param is based on this target field's param? 
			#if (!$source_prefix || !$target_prefix) { die "set_values_from_similar: incorrect arguments. Must provide a source_prefix and target_prefix so I can find the source value based on my own parameter name."; }
			$src_param = $field->{parameter_name};
			$src_param =~ s|^$target_prefix||; #strip off target prefix which is assumed to be on this parameter name.
			$src_param = $source_prefix . $src_param; #apply source param prefix.
		}
		
		#its totally ok if we dont find a src_param, because maybe we're not sourcing _that_ value, and dont want to hardcode the list of values we're not sourcing via a target_params arg. (CMCReg 2007 03 30)
		if (!$src_param) { next; } #can't source so dont.
		
		#$self->ch_debug(['set_values_from_similar: going to copy a value from this source param to this field attrib called:', $src_param, $value_attrib]);

		#by now, we should know where to get the value to apply from. so apply it.
		$field->{$value_attrib} = $args->{source_values}->{$src_param};
	}
	
	#$self->{wa}->dbg_print(['set_values_from_similar: edit values after doing stuff: ', $self->{'do'}->get_edit_values() ]);
	#die "stop fool";
	
	return $self->{'do'};	
}

sub save_edited_record {
	my $self = shift;
	my $other_args = shift; #any behavior to control?

	my $ef_spec = $self->{'do'}->{ef_spec}; #even though we have $self->editform_spec now, I think I still want to access this like so, that way we are guaranteed to get the error condition if it hasnt been prepped already and we want to make sure that other things which happen during the allowed prepping methods do in fact take place. at least I think thats the reasoning.
	if (!$ef_spec) {
		$self->error("save_edited_record: cannot continue without an ef_spec being set already. did you call load_record_for_edit or anything first?");
		return $self->{'do'};
	}
	
	#sure we're saving 'edited' record generally speaking -- but I'ld like to be able to use this to save values from other source fields too. like from cgi.
	my $inspect = 'edit';
	if ($other_args->{inspect}) { 
		$inspect = $other_args->{inspect};
		#$self->ch_debug(['the fields:', $ef_spec->{fields}]);
		#die "inspecting other fields!";
	}

	#do any pre_save field injection right now.
	if ($other_args->{pre_save_inject_fields}) {
		$self->ch_debug(['save_edited_record: will be doing _inject_edit_fields with inject fields like:', $other_args->{pre_save_inject_fields}]);
		#$self->{emi}->_inject_edit_fields({form_spec => $ef_spec, inject_fields => $other_args->{pre_save_inject_fields}, target => $inspect});
		$self->{emi}->_save_operation_field_injection({form_spec => $ef_spec, inject_fields => $other_args->{pre_save_inject_fields}, target => $inspect});
	}

	$self->{emi}->_set_save_values($ef_spec->{fields}, { inspect => $inspect });
	#$self->{wa}->dbg_print(['save_edited_record: form spec here1:', $ef_spec ]);
	my $record_id = $self->{sa}->_save_record($ef_spec);
	$self->ch_debug(['save_edited_record: the record id of the record we just saved was: ', $record_id ]);
	
	$self->{'do'}->record_id($record_id);
	
	##### NOTE, IDEA AT 2008-09-18 - ... problem: if you have a dobj that includes the .id field in its field list .... then do a new record for edit, set values, save it (so it has an ID), and then want to do more set_edit_values on it, well, there is a problem in that the id field in the field list will not have been given a value it will be undef .... which means when save_edited_record is called again, it will set the ID to explicitly undef/NULL with unpredictable results.
	##### Proposed solution to this is that RIGHT HERE, after noting and assigning new record_id() here we should check for the db_primary_key field being listed in the dobj fieldrefs and if it is there then SET its edit_value to the record id.
	##### So .... think about that and maybe do it here ... for now I'm using the {find=>{}, or_new=>1} stuff to handle this scenario as it was catered to the usage I am trying to use.

	#returns ref to self. obtain record id on that by calling record_id() :)
	return $self->{'do'};
}

sub process_form_submission {
	my $self = shift;
	my $actions = shift;
	my $other_args = shift;
	
	#I imagine there will be a ton of customizations later for this function, surrouding behaviours for ok and not_ok return results. we'll see...

	#my $form_spec = $self->{'do'}->form_spec();

	#maybe there should be an other_arg for picking up record_id from the cgi. as it is, I have to pass it to the new() call of the dataobj that will be processing the submission.

	my $report_only = 0;
	if ($other_args->{report_only} || !defined($actions)) {
		#if explictly told to, or if we just didnt get any actions to do, then do the report only return mode.
		$report_only = 1;
		if (!defined($actions)) { $actions = {}; }
	}

	my $save_for = $actions->{not_ok}; #assume that the not_ok action runmode is the same name we should use to save the screen data ... because this should usually be the editform runmode ... provide facility to override that later.
	if ($other_args->{for_screen}) { $save_for = $other_args->{for_screen}; }
	if (!$save_for) {
		$self->error("process_form_submission needs a name under which to save fields in the session.");
		die "need better behavior for this death - must either have an not_ok action passed or an explicit other-arg for_screen passed -- either way we need to be able to guess or know what screen to save the params for";
	}
	
	#load session fields here -- maybe we want to preserve db values going forward with bad validation happening.
		#if there are no session fields, do standard editform fields on the form spec.
		### hrm .. taken one further you would think that here we should always be using some session fields because i think i went with the the idea of if you show the form you save the fields in the session. so that should mean that if we're doing this then the initialization phase that gathers fields is a complete waste of time. how to avoid that?
		### and now that I'm saving them in session and carrying forward through the whole process from db selection 
	my $ef_spec = $self->editform_spec();
	my $session_fields = $self->{emi}->_session_fields({ load_for_screen => $save_for}); #just a boolean now.

	if (!$session_fields) {
		$self->{emi}->_standard_editform_fields($ef_spec->{fields});
		$self->ch_debug(["process_form_submission using STANDARD EDITFORM (not session) fields from the start\n"]);;
	} else {
		#$self->ch_debug(['the funstack is:', $self->{wa}->session()->param('_data_obj_saved_fields')]);
		$self->ch_debug(["process_form_submission using SESSION FIELDS from the start\n"]);;
	}

	my $pickup_cgi_result = $self->{emi}->_pickup_cgi_values($ef_spec->{fields}); #should return a 0 if it fails for some reason.
#	$self->ch_debug(['process_form_submission: for record id:', 'oops record id is picked up lower down now', "after _pickup_cgi_values, fields are like: ", $ef_spec->{fields}]);
#	die "stop";

	#2007 03 13: new PRE-validate hook! w00t. The reason to implement this is I want to define a function that will decide whether certian fields are _really_ required, based on the other input. Specifically, for CMCReg, the course selection must be required if there are no offerincs, and the offerings must be required if there are no courses.
		###AND ... since all these callback hooks are basically the same, they should be abstracted into a _execute_callback or something!
	if ($actions->{pv_callback})      { $actions->{pre_validate_callback} = $actions->{pv_callback}; } #2009 04 15 lookin for a shorter name.
	if ($actions->{pv_callback_args}) { $actions->{pre_validate_callback_args} = $actions->{pv_callback_args}; } #2009 04 15 lookin for a shorter name.
	if ($actions->{pre_validate_callback}) {
		my $callback_output = undef;
		my $callback_func = $actions->{pre_validate_callback};
		my $callback_args = {
			data_obj => $self->{'do'},
			actions  => $actions, #thinking maybe want to change some not_ok_redirect_params in here or something.
		};
		if ($actions->{pre_validate_callback_args} && (ref($actions->{pre_validate_callback_args}) eq 'HASH')) {
			$callback_args = { %{$actions->{pre_validate_callback_args}}, %$callback_args }; #let it be merged!
		}
		$callback_output = eval '$self->{wa}->$callback_func($callback_args)'; #note, was calling it like eval($self->{wa}->$callback($self)) before but that would NOT let me return a string ... using eval '' or eval {} seems to work though -- apparently {} will be compiled at compile time, but i will use '' so to be sure it is compiled at runtime. honestly not sure if I _need_ to do that, but sounds safer to me since the callback function will change with each call, compiling it once could cause a problem i would imagine if the callback was to be used differently within the same request.
		die "Error executing DataObj->process_form_submission for the validate_callback action: $@" if $@;
	}
	
	$self->{emi}->_pre_validate_editform_field_processing($ef_spec); #to set/unset skip flags on fields based on field types and/or submitted values of other fields. crazy shit.

	$self->ch_debug(['process_form_submission... after _pre_validate_editform_field_processing, form spec fields looks like: ', $ef_spec->{fields}  ]);
	#die "debugging 01 in DEV area";

	my $validated_by_fieldsauto  = 1;
	my $validated_by_callback    = 1; #if we have a validate callback, it might turn false, and either way we need to ahve this and $validated_fieldsauto to be considered valid.
	#$self->ch_debug(['process_form_submission: for record id:', 'oops record id is picked up lower down now', "validated result after basic field validation:", $validated]);
	#die "stop temp";

	my $fieldsauto_formerror = $self->{emi}->_validate_field_values($ef_spec->{fields}, { inspect => 'cgi' });
	$self->ch_debug(['process_form_submission... after _validate_field_values, form spec fields looks like: ', $ef_spec->{fields}  ]);
	#die "debugging in DEV area";
	
	#$self->ch_debug(['process_form_submission... 1 .. :', $fieldsauto_formerror]);
	if (!$fieldsauto_formerror->{validated}) {
		$validated_by_fieldsauto = 0;
	}
	
	#new concept, validation callbacks. would let us alter the state of $validated, and change actions, do things to the dobj, etc, based on whatever criteria we want.
	#(inspiratinal rant: Its all well and good to know that the fields have values plugged in and they are the right format, etc, but what if we dont really know if they're valid, like we need to ask some mystic third party oracle if its valid (like for cc processing for cmcreg)? We should be able to have a hook here to further check validation by whatever freakysneaky arbitrary rules. )
		#if a validate_callback is provided, execute it, passing along the data_obj, the actions, and the current validated status (which probably doesnt really matter). the function would then return a simple boolean for validated or not, and i think it quite possible that both a thus-far-invalid-result could be turned valid, or a thus-far-valid-result could be turned invalid (especially in the cc-declined scenario where we do the actual cc processing in the callback!)
		#hrmm .. on second thought, dont do a validate callback if we were invalidated by doing auto field validation. honestly, what would be the point? if there was some scenario where it could be flipped back, then really the field that could be flipped back or cause flipping back should not be validated by the normal validate.
		#guess what 2007 04 13 ... validate callbacks now being used to set custom error messages for custom form elements .... which should be validated regardless so that complete error message sets can be given.
	my $validate_callback_output = undef;
	#if ($validated && $actions->{validate_callback}) {
	if ($actions->{validate_callback}) {

		my $callback_func = $actions->{validate_callback};
		my $callback_args = {
			data_obj  => $self->{'do'},
			actions   => $actions, #thinking maybe want to change some not_ok_redirect_params in here or something.
			formerror => $fieldsauto_formerror, #able to update this
		};
		if ($actions->{validate_callback_args} && (ref($actions->{validate_callback_args}) eq 'HASH')) {
			$callback_args = { %{$actions->{validate_callback_args}}, %$callback_args }; #let it be merged!
		}
		$validate_callback_output = eval '$self->{wa}->$callback_func($callback_args)'; #note, was calling it like eval($self->{wa}->$callback($self)) before but that would NOT let me return a string ... using eval '' or eval {} seems to work though -- apparently {} will be compiled at compile time, but i will use '' so to be sure it is compiled at runtime. honestly not sure if I _need_ to do that, but sounds safer to me since the callback function will change with each call, compiling it once could cause a problem i would imagine if the callback was to be used differently within the same request.
		die "Error executing DataObj->process_form_submission for the validate_callback action: $@" if $@;

		if (ref($validate_callback_output) eq 'HASH') {
			$validated_by_callback = $validate_callback_output->{validated} ? 1 : 0;
		} else {
			$validated_by_callback = $validate_callback_output ? 1 : 0;
		}
		
		#automatic formlevel flagging. nothing prevents validate callback from doing all the work, but i think this would be handy. i dont think we'd ever want to NOT set these flags if the form has any error messages set. 
		if ($fieldsauto_formerror->{baddata_error_messages})  { $fieldsauto_formerror->{baddata_error}  = 1; $fieldsauto_formerror->{validated} = 0; }
		if ($fieldsauto_formerror->{nodupe_error_messages})   { $fieldsauto_formerror->{nodupe_error}   = 1; $fieldsauto_formerror->{validated} = 0; }
		if ($fieldsauto_formerror->{required_error_messages}) { $fieldsauto_formerror->{required_error} = 1; $fieldsauto_formerror->{validated} = 0; }
	}
	
	my $validated = 1; #woohoo!
	if (!$validated_by_fieldsauto)  { $validated = 0; } #d'oh!
	if (!$validated_by_callback)    { $validated = 0; } #d'oh!

	#2009 04 30, moving record id pickup down here b/c i had a desire to go forth and save a record of the bmg image lib table with the image info that was literally just uploaded in a pv callback and then set the record id of the caller dobj so it would then update that record that was just created for it!
	my $record_id = $self->{'do'}->record_id();
	my $record_id_param = $other_args->{record_id_param} ? $other_args->{record_id_param} : 'record_id'; #for redirects (or templating) allowing ovverride of default 'record_id';

	#$self->ch_debug(['process_form_submission... with this $fieldsauto_formerror after being added to possibly by the callback:', $fieldsauto_formerror, 'formspec look-a-like:', $ef_spec ]);
	$self->ch_debug(['process_form_submission... with this $fieldsauto_formerror after being added to possibly by the callback:', $fieldsauto_formerror, 'wacky fields like: ', $ef_spec->{fields}  ]);
#	if (!$validated) {
#		die "Debugging. in SPI DEV area";
#	}

	$self->ch_debug(['process_form_submission: for record id:', $record_id, "validated result after validate callback was:", $validated]);
	#die "the durka";

	if (!$validated) {

		#do the not_ok callback if there was one. pass the fields in. just seems like the right thing to do. (though maybe I want to pass the whole ef_spec)
			#note I only added this so that I could die for one particular form processing runmode for a not_ok action. so this might need to be reformed to be more useful.
		my $callback_func = undef;
		my $callback_output_only = 0;
		my $callback_output = undef;
		if ($actions->{not_ok_callback}) {	
			$callback_func = $actions->{not_ok_callback};	
		}
		if ($callback_func) {
			#experiment: adding ability to call a function, to do it pass a function reference in actions->{ok_callback} -- we will just call the function and always pass a ref to the d_obj.
				#now with callback args that can be user specified, and also will ALWAYS include a dataobj key for access to this data obj!
			my $callback_args = {};
			if ($actions->{not_ok_callback_args} && (ref($actions->{not_ok_callback_args}) eq 'HASH')) {
				$callback_args = $actions->{not_ok_callback_args};
			}
			$callback_args->{data_obj} = $self->{'do'}; 
			$callback_args->{actions}  = $actions;
			$callback_args->{validate_callback_output} = $validate_callback_output; #see comment below in same line for ok_callback for notes on this.
			$callback_output = eval '$self->{wa}->$callback_func($callback_args)'; #note, was calling it like eval($self->{wa}->$callback($self)) before but that would NOT let me return a string ... using eval '' or eval {} seems to work though -- apparently {} will be compiled at compile time, but i will use '' so to be sure it is compiled at runtime. honestly not sure if I _need_ to do that, but sounds safer to me since the callback function will change with each call, compiling it once could cause a problem i would imagine if the callback was to be used differently within the same request.
			die "Error executing DataObj->process_form_submission for the not_ok_callback action: $@" if $@;
		}

		#save fields in session. I suppose we might have just done something to them in the not_ok callback, but probably not.
		$self->{emi}->_session_fields({ save_for_screen => $save_for }); #i have no idea what I'm doing now. just winging it. hoping to find a useful pattern out of this.
		$self->{emi}->_session_formerror({ error => $fieldsauto_formerror, save_for_screen => $save_for }); #i have no idea what I'm doing now. just winging it. hoping to find a useful pattern out of this.
		#experiment with session_form as well. 2007 04 12 b/c I am unsure of any better way to be able to pass around complex form error information.
			#I think I only want to save it on a bad submit, b/c the whole point I'm adding it is just to get extra information about errors back to the form when it's redisplayed. the flipside is in get_editform that will pull this back out from the session.
		#$self->{emi}->_session_form($ef_spec->{form}, { save_for_screen => $save_for });

		$self->ch_debug(['process_form_submission: validation failed -- supposed to save fields in the session under this name (field follow):', $save_for, $ef_spec->{fields}]);

		#die "stopping with a bad validation -- why isnt the form redisplaying with errors flagged?";
		my $not_ok_redirect_params = { retry_form => 1 };
		if ($record_id && !$other_args->{suppress_redirect_record_id}) { $not_ok_redirect_params->{$record_id_param} = $record_id;	} #add record id to redirect params.
		if ($actions->{not_ok_redirect_params} && (ref($actions->{not_ok_redirect_params}) eq 'HASH')) {
			$not_ok_redirect_params = { %{$actions->{not_ok_redirect_params}}, %$not_ok_redirect_params }; #merged!
			#$self->ch_debug(['about to do not_ok redirection with these actions and redirect params:', $actions, $not_ok_redirect_params]);
			#die "for stop";
		}

		if ($report_only) {
			return { result => 'not_ok', not_ok => 1, fields => $ef_spec->{fields}, redirect_params => $not_ok_redirect_params };
		} else {
			#not_ok redirection.
			return $self->{wa}->redirect_runmode($actions->{not_ok}, $not_ok_redirect_params );
		}
	} else {
		##Good validation

		#do any pre_save field injection right now.
		if ($other_args->{pre_save_inject_fields}) {
			$self->ch_debug(['process_form_submission: will be doing _inject_edit_fields with inject fields like:', $other_args->{pre_save_inject_fields}]);
			#$self->{emi}->_inject_edit_fields({form_spec => $ef_spec, inject_fields => $other_args->{pre_save_inject_fields}, target => 'cgi'});
			$self->{emi}->_save_operation_field_injection({form_spec => $ef_spec, inject_fields => $other_args->{pre_save_inject_fields}, target => 'cgi'});
		}

		#####RIGHT here is where I would want to do pre_save_callback stuff ... which I have an inkling I actually want to add for the CMCReg redev 
			### ....
		
		if (!$other_args->{defer_save}) {
			#if we are deferring save we have to set the save values elsewhere -- probably via save_edited_record having it inspect the cgi_values instead of its default edit_values
			$self->{emi}->_set_save_values($ef_spec->{fields}, { inspect => 'cgi' });
			$record_id = $self->{sa}->_save_record($ef_spec); 
			#set object record id -- ok I dont entirely think it is the right thing to do because umm, well for certain we wont have any lookup values or anything. But it shouldnt break anything and will give the info that the CALLBACK NEEDS!
			$self->{'do'}->record_id($record_id);
		}

		#Note, 20070129, I'm moving the ok_callback execution related stuff out of the !defer_save check ... I think it does not really depend on doing the save operation. 
		###can specify the callback in more than one way. -- hoping to make intuitive and smart behavior.
		#we might want to return callback output instead of doing a redirect to the ok action runmode.	
			#use callback output by default if we are doing ok_callback and there is no ok action set ... (meaning for a good save we dont want to redirect to a runmode named by the ok action, we want to show the output generated by the callback)
		my $callback_func = undef;
		my $callback_output_only = 0;
		my $callback_output = undef;

		#say there is a callback, and if no ok action is set, then the output of the callback will be sent out.
		if ($actions->{ok_callback}) {	
			$callback_func = $actions->{ok_callback};	
			#if (!$actions->{ok}) { $callback_output_only = 1; } #####dont make this decision so early. callback itself could establsh an ok action to redirect to.
		}
		#say there is a callback and no matter what other actions params are set only use the output of the callback for an ok result
		if ($actions->{ok_callback_output_only}) {	
			#thinking something cool right here would be to check that $actions->{ok_callback_output_only} actually is a function ref and use it as such only in that case ... if it WASN'T a function ref, it is probably just telling us to USE ONLY the callback output for the callback specified in the ok_callback action. But presently if ok_callback_output_only is supplied it has to be the function ref to use.
			$callback_func = $actions->{ok_callback_output_only};	
			$callback_output_only = 1;
		}
		#excecute the callback function if it was provided.		
		if ($callback_func) {
			#experiment: adding ability to call a function, to do it pass a function reference in actions->{ok_callback} -- we will just call the function and always pass a ref to the d_obj.
				#now with callback args that can be user specified, and also will ALWAYS include a dataobj key for access to this data obj!
			my $callback_args = {};
			if ($actions->{ok_callback_args} && (ref($actions->{ok_callback_args}) eq 'HASH')) {
				$callback_args = $actions->{ok_callback_args};
			}
			$callback_args->{data_obj} = $self->{'do'};
			$callback_args->{actions}  = $actions;
			$callback_args->{validate_callback_output} = $validate_callback_output; #today, 2007 04 02, I want to be able to have the result of the validate_callback available to the ok_callback. This is continuing the development of the pattern of usage for these callbacks, so hopefully soon I'll have enuogh to work with to logically abstract the callback functionality into a util function. i suspect there will be other places where callback output of earlier callbacks should be made available to later callbacks. #also I juuuust realized I could have simply set values in to the $actions datastructure to accomplish the same feat. oh well, we can be explicit about this since doing that would have been kinda cheesy/hackish.
			$callback_output = eval '$self->{wa}->$callback_func($callback_args)'; #note, was calling it like eval($self->{wa}->$callback($self)) before but that would NOT let me return a string ... using eval '' or eval {} seems to work though -- apparently {} will be compiled at compile time, but i will use '' so to be sure it is compiled at runtime. honestly not sure if I _need_ to do that, but sounds safer to me since the callback function will change with each call, compiling it once could cause a problem i would imagine if the callback was to be used differently within the same request.
			die "Error executing DataObj->process_form_submission for the ok_callback action: $@" if $@;
			
			if (!$actions->{ok}) { $callback_output_only = 1; }
		}
		
		#clear session fields for ths screen so they don't mess us up later!
			#clear them after doing any callbacks now - I'm having a problem reliably getting the values of certain form fields that are added via the add_editform_fields hook in the get_editform, and the reason I think is because I'm doing my debug in the callback, so the data is there the first time, but subsequent runs have already had the session fields cleared ... and so I can't get the values.
		#2007 06 15 - "mess us up later"? mess us up how? I messed myself up by not keeping them when i was deferring save operation until after confirming action with user, and using this func to handle all the value pickup stuff.
		#2009 04 29 - "mess us up later"? MESS US UP HOW???? Clearing them here seems to have the general effect of MESSING US UP. Lets try NOT CLEARING THEM and then decide if that messes us up and at least say how.
		#unless ($other_args->{preserve_session_fields}) {
			#die "about to clear session fields. Am I supposed to?";
			#2009 04 29 yeah lets try never clearing them. 
			#$self->{emi}->_session_fields({ clear_for_screen => $save_for }); 
		#}
		#2009 04 29 because I am not able to imagine all scenarios where we might truly actually really deeply want to clear them I'll still make it to be possible but we are not doin it by default any more.
		if ($other_args->{clear_session_fields}) {
			$self->{emi}->_session_fields({ clear_for_screen => $save_for }); 
		}
		
		$self->{emi}->_session_formerror({ clear_for_screen => $save_for });
		#$self->{emi}->_session_formstatus({ status => 'processed', save_for_screen => $save_for });

		my $ok_redirect_params = {};
		if ($actions->{ok_redirect_params} && (ref($actions->{ok_redirect_params}) eq 'HASH')) {
			$ok_redirect_params = { %{$actions->{ok_redirect_params}} };
		}
		#was always including the record id in the redirect -- but that is cuasing problems sometimes so here we can turn it off.
			#i mean honestly i really do think its a good idea to always include this. maybe what I _really_ need to be doing is figuring out the whole 'record_id_param' thing and then use THAT parameter name which would default to record_id if it was not definedered.
			#ok, now we can tell it what the record_id_param should be and use that. default is still 'record_id' of course.
			#update .. only even think about doing it if we actually have a record id, which means it should be auto-suppressed when doing defer_save for pure data capture.
		if ($record_id && !$other_args->{suppress_redirect_record_id}) {	$ok_redirect_params->{$record_id_param} = $record_id; }
		
		#define a list of special values -- this way we can be asked to include values that are not always available until this point in the function.
		my $special_values = {
			'_record_id' => $record_id,
		};
		foreach my $ok_cgi_param (keys(%{$actions->{ok_redirect_params}})) {
			if ($special_values->{$actions->{ok_redirect_params}->{$ok_cgi_param}}) {
				$ok_redirect_params->{$ok_cgi_param} = $special_values->{$actions->{ok_redirect_params}->{$ok_cgi_param}};
			}
		}
		$self->ch_debug(['about to redirect to runmode:', $actions->{ok}, 'with params like:', $ok_redirect_params]);
		#die "for nachos";
		
		if ($report_only) {
			my $rpt = { result => 'ok', ok => 1, fields => $ef_spec->{fields}, record_id => $record_id, redirect_params => $ok_redirect_params };
			if ($callback_output_only) {
				$rpt->{callback_output_only} = 1;
			}
			if (defined($callback_output)) {
				$rpt->{callback_output} = $callback_output;
			}
			return $rpt;
		} else {
			$self->ch_debug(['process_form_submission: what to return? callback output only?', $callback_output_only]);
			if ($callback_output_only) {
				#using ok_callback, and no ok action mode set, we should output the result of the callback mode.
				#$self->ch_debug(['process_form_submission: return callback output only, output like:', $callback_output]);
				$self->ch_debug(['process_form_submission: returning callback output only']);
				#die "stop now before returning callback output only.";
				return $callback_output;
			} else {
				#normal operation would be to redirect ot the ok action runmode. (how about optionally just returning the output of a runmode without a redirect, huh?! well one day maybe)
					#now with ability to have a bunch of custom params in the redirect.
					#keys will be the names to use for the cgi param, values will be literals unless those literals match a key in the special values in which case it will come from there.
						#will prefix all special values with _ to distinguish them.
				#exaple ok_redirect_params => { foo => 'bar', preselect_record_id => '_record_id' };, this will include foo=bar&preselect_record_id=[the actual record id from the special values]
				return $self->{wa}->redirect_runmode($actions->{ok}, $ok_redirect_params);
			}
		}
	}
	
}

#this was added so that we can leave a form to do something else (like pick some cmcreg signup courses and seminars) and then be able to come back to the form with retry_form on and have the values redisplay.
#so this would be called as a first thing in any non-form-processing runmode that is reached via submitting a form, so as to save the state of the form, so that it can be returned to later. used a bunch of times via _save_signup_form_params in CMCReg::User.
sub pickup_and_sessionize_cgi_values {
	my $self = shift;
	my $args = shift;

	my $save_for = $args->{for_screen};
	if (!$save_for) {
		$self->error("pickup_and_sessionize_cgi_values needs a name under which to save fields in the session.");
		return $self->{'do'};
	}

	my $ef_spec = $self->editform_spec();
	$self->{emi}->_standard_editform_fields($ef_spec->{fields});
	my $pickup_cgi_result = $self->{emi}->_pickup_cgi_values($ef_spec->{fields}); #should return a 0 if it fails for some reason.

	#want to optionally validate before saving in session and also save form too when validating. 
		#and apply callbackism if provided as well, this is basically to mimic what would happen in process_form_submission so that between form renderings we'll keep the error status up to date and so when we return to the form it should reflect the true present validation status.
		#all this rip-chopped from process_form_submission. slightly simplified.
#this seems to be just ill conceived at the moment. I thikn I still want to do this, just maybe not here.
#	if ($args->{validate}) {
#		my $fieldsauto_formerror = $self->{emi}->_validate_field_values($ef_spec->{fields}, { inspect => 'cgi' });
#		if ($args->{validate_callback}) {
#	
#			my $callback_func = $args->{validate_callback};
#			my $callback_args = {
#				data_obj  => $self->{'do'},
#				actions   => {}, #no actions here, we're just after setting up validation info.
#				formerror => $fieldsauto_formerror, #able to update this
#			};
#			if ($args->{validate_callback_args} && (ref($args->{validate_callback_args}) eq 'HASH')) {
#				$callback_args = { %{$args->{validate_callback_args}}, %$callback_args }; #let it be merged!
#			}
#			eval '$self->{wa}->$callback_func($callback_args)';
#			die "Error executing DataObj->pickup_and_sessionize_cgi_values for the validate_callback action: $@" if $@;
#			#automatic formlevel flagging. nothing prevents validate callback from doing all the work, but i think this would be handy. i dont think we'd ever want to NOT set these flags if the form has any error messages set. 
#			if ($fieldsauto_formerror->{baddata_error_messages})  { $fieldsauto_formerror->{baddata_error}  = 1; $fieldsauto_formerror->{validated} = 0; }
#			if ($fieldsauto_formerror->{nodupe_error_messages})   { $fieldsauto_formerror->{nodupe_error}   = 1; $fieldsauto_formerror->{validated} = 0; }
#			if ($fieldsauto_formerror->{required_error_messages}) { $fieldsauto_formerror->{required_error} = 1; $fieldsauto_formerror->{validated} = 0; }
#		}
#		#save fields in session. I suppose we might have just done something to them in the not_ok callback, but probably not.
#		$self->{emi}->_session_formerror({ error => $fieldsauto_formerror, save_for_screen => $save_for }); #i have no idea what I'm doing now. just winging it. hoping to find a useful pattern out of this.
#	}


	#$self->ch_debug(['process_form_submission: for record id:', $record_id, "validated result after basic field validation:", $validated]);
	#die "stop temp";

	#save fields in session.
	$self->{emi}->_session_fields({ save_for_screen => $save_for }); #I think I've found a useful pattern with this _session_fields and other stuff.

	#2007 04 19 wild ass assumuption ... we always want to lose any sessionized error shit when we do this because we are pretty much not validating shit fuck all here yet we're saving _it_ to the session.
	$self->{emi}->_session_formerror({ clear_for_screen => $save_for });  #bloh!

	return $self->{'do'};
}	

sub delete_record {
	my $self = shift;
	my $actions = shift;
	my $other_args = shift;
	
	my $form      = $self->{'do'}->form_spec()->{form};
	my $record_id = $self->{'do'}->record_id(); #should I be figuring this out from the field data? I dont believe so at the moment -- I should be told I think.
	my $sql_only  = $other_args->{sql_only}; #not like I'm taking this into consideration at the moment.

	if (!$form || !$record_id) {
		$self->error('delete_record: must have both a form and record_id');
	}
	return 0 if ($self->error());

	$self->{sa}->_delete_record({ form => $form, record_id => $record_id });
	
	$self->{'do'}->clear_record_id(); #logical I think since it was just deleted.

	if ($actions->{ok}) {
		#2007 10 22, lbg needs to call a function to rebuild the categories leftnav right after the record is deleted. so i need a hook. stick with existing naming, calling it ok_callback. doing simpler call tho, no eval shit.
		if ($actions->{ok_callback} && ref($actions->{ok_callback}) eq 'CODE') {
			my $callback_args = $actions->{ok_callback_args} ? $actions->{ok_callback_args} : {};
			#call it
			$actions->{ok_callback}->($self->{wa}, $callback_args);
		}

		#2008 06 09, idl needs to be able to redirect back with params ;)
		my $ok_redirect_params = {};
		if ($actions->{ok_redirect_params} && (ref($actions->{ok_redirect_params}) eq 'HASH')) {
			$ok_redirect_params = { %{$actions->{ok_redirect_params}} };
		}
				
		#for my tests I just want to return to the searchform. or something.
		return $self->{wa}->redirect_runmode($actions->{ok}, $ok_redirect_params);
	} else {
		return 1;
	}
}

1;