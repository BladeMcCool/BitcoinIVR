package SpApp::DataObj::SupportObj::EditModeInternals;
use base SpApp::DataObj::SupportObj;
use strict;
use Encode;
use Captcha::reCAPTCHA;

#would like a func to pick up cgi parameters and put them as cgi_value into each of the fields
sub _pickup_cgi_values {
	my $self = shift;
	#my $form_spec = shift;
	my $fields = shift;
	my $other_args = shift;

	#the rest of this ... 
	my $cgi = $self->{wa}->query();
	#my $fields = $form_spec->{fields};
	#my $do_simple_values = 0;
	#if ($other_args->{include_simple_values}) { $do_simple_values = 1; }

	#do merged fields to get values of subfields plugged in as well.
	my $cgi_fields = $self->{fp}->_get_merged_fields_and_subfields($fields);

#	foreach my $field (@$fields) {
	foreach my $field (@$cgi_fields) {

#		#ones that we pretty much just skip
#		if ($field->{edit_fieldtype} eq 'IMAGEINPUT') {
#			#not handling imageinput field type here - not at the moment and maybe never.
#			next; 
#		}

#		if ($field->{edit_fieldtype} eq 'SINGLESELECT_CHECKBOX' && !defined($cgi->param($field->{parameter_name}))) {
#			#special case for singleselect checkbox where the value of the field isnt defined we HAVE to put a zero in it. case where it is defined will be picked up below in standard pickup.
#			$field->{cgi_value} = 0;
#			###wait dont skip to next just yet, we need to do the _display_value_from_listoptions stuff down below.
#			###next;
#		}
		
		#special handling for the different field types.
		if ($field->{edit_fieldtype} =~ /^MULTISELECT_/) {
			#multiselect values into a pipe delimited list, err JSON dump.
			my @multi = $cgi->param($field->{parameter_name});
			$field->{cgi_value} = scalar(@multi) ? JSON::Syck::Dump(\@multi) : undef;
			$field->{cgi_value__multi_values} = \@multi; #and unmodified in case somewhere its needed -- thinking of doing display values for these cgi things based on listoptions and so we'd need it in a normal way.
		} elsif ($field->{edit_fieldtype} eq 'IMAGEINPUT') {

			#handling of the uploaded image...

			my $upload_result = $self->{fp}->_image_upload($field); #will add image_info to the field record if it can process the uploaded image.
			if ($upload_result->{uploaded}) {
				#so if the user actually posted a file with the form submission use this:
					#2009 04 15 I have just decided that we are switching from the notion of storing a filename that exists in a filesystem directly, to more abstract image id (which was the part of the filename before .jpg before). this opens many doors that storing a filename had kept closed. the code right below will now stick the returned image_id into the cgi_value field instead.
				#$field->{cgi_value} = $upload_result->{image_info}->{orig_size_fname}; #2009 04 15 not storing this any more.
				$field->{cgi_value} = $upload_result->{image_info}->{app_image_id};
				$field->{_image_upload_result} = $upload_result; #2009 01 30, needing to access some more info about the image that was just uploaded, thinking i can just stick the info into the fieldref.
				
				$self->ch_debug(['_pickup_cgi_values: just handled an image upload, the info we got back was: ', $upload_result ]);
				#die "stop after uploading an image";

			} elsif ($cgi->param($field->{parameter_name})) {
				#user didnt post a file, but they might have done so before and passed forward the filename in a related cgi param.
				$field->{cgi_value} = $cgi->param($field->{parameter_name});
				#also, dont go killing _image_upload_result here just because we didnt upload an image RIGHT NOW ... we could very well be retrying form on subsequent attempts after having browse...'d the image and submitted first attempt. user isnt gonna be expected to browse/send file again and so we better keep the _image_upload_result info around!
					#yarr thinking more ... BUT WAIT why do we want to keep it around? it was because the final OK action was still needing to pick it up ... well we need to do shit before then anyway. we need to do it before we retry. and so when we do retry this should probably not be still in the fieldref that will be comin back from the session.
				$field->{_image_upload_result} = undef;
			}
			
		} elsif ($field->{edit_fieldtype} eq 'FILEINPUT') {

			#2009 08 11 file upload handling, copied from image upload handling and chopped/hacked as needed.
			#handling of the uploaded file (should be a lot simpler than image!) ...

			my $upload_result = $self->{fp}->_file_upload($field); #will add image_info to the field record if it can process the uploaded image.
			if ($upload_result->{uploaded}) {
				$field->{cgi_value} = $upload_result->{file_info}->{app_file_id};
				$field->{_file_upload_result} = $upload_result; 
				$self->ch_debug(['_pickup_cgi_values: just handled a file upload, the info we got back was: ', $upload_result ]);
				#die "stop after uploading an image";
			} elsif ($cgi->param($field->{parameter_name})) {
				#user didnt post a file, but they might have done so before and passed forward the filename (id rather?!) in a related cgi param.
				$field->{cgi_value} = $cgi->param($field->{parameter_name});
				#also, dont go killing _image_upload_result here just because we didnt upload an image RIGHT NOW ... we could very well be retrying form on subsequent attempts after having browse...'d the image and submitted first attempt. user isnt gonna be expected to browse/send file again and so we better keep the _image_upload_result info around!
					#yarr thinking more ... BUT WAIT why do we want to keep it around? it was because the final OK action was still needing to pick it up ... well we need to do shit before then anyway. we need to do it before we retry. and so when we do retry this should probably not be still in the fieldref that will be comin back from the session.
				$field->{_file_upload_result} = undef;
			}
			
#		} elsif ($field->{edit_fieldtype} eq 'DISPLAY_ONLY_SIMPLE') {
#			#display only fields dont actually submit a cgi value. should they? Right now I'm still thinking 'no'. Although, if they did, it probably would just solve this problem and then those cgi values
#			#hrmm ok gonna try that ... let them submit a value. the only point is so that when we retry we can have the vals for display_only fields on screen.
#     #if I _was_ gonna code something here, it would be something about sourcing a 'cgi' value from some other field, like db_value, edit_value or something that is specified as an arg for display_values_from_attrib.

		} elsif ($field->{edit_fieldtype} eq 'SINGLESELECT_CHECKBOX' && !defined($cgi->param($field->{parameter_name}))) {
			#special case for singleselect checkbox where the value of the field isnt defined we HAVE to put a zero in it. case where it is defined will be picked up below in standard pickup.
			$field->{cgi_value} = 0;
		} elsif ($field->{edit_fieldtype} eq 'CAPTCHA_RECAPTCHA') {
			my $captcha = {
				challenge => $cgi->param('recaptcha_challenge_field'),
				response  => $cgi->param('recaptcha_response_field'),
			};
			$field->{cgi_value} = JSON::XS::encode_json($captcha); #cgi_value should always be something that can be shoved into a db field ... so encode it - although with this experiment the field of the form doensnt even have a db_field_name.
			$field->{cgi_value__captcha} = $captcha; #store the hashref here where we can find it later.
			$self->ch_debug(['_pickup_cgi_values: for a recaptcha we picked up these challenge and response vars', $captcha, 'and field is looking like this now:', $field ]);
		} else {
			$field->{cgi_value} = Encode::decode('utf8', $cgi->param($field->{parameter_name}));
			$self->ch_debug(['_pickup_cgi_values: should have got a regular old cgi value for field like (and that should be in the field now):', $field ]);
		}
		
		#2007 03 09 Experimental _display_value_from_listoptions ... might also be used elsewhere some day.
		$self->{fp}->_display_value_from_listoptions($field, { inspect => 'cgi' });
	}
	
	return 1;
}

sub _pre_validate_editform_field_processing {
	my $self = shift;
	my $ef_spec = shift;
	
	##REMEMBER THIS IS FOR THE CMCEDUSIGNUP MAGICALLY NOT-REQUIRED CREDIT CARD FIELDS as set up by field spec. I could probably do it now with a pre-validate callback hook.
		##and also a few other things that are somewhat related and relatively pre-existing.
	#at this point cgi params will already be picked and plugged but that wont be bad instead it helps us 
	#adding this for one purpose: to remove certain fields from the editform spec fields list so that they are not validated and are not saved.
		#this must happen AFTER cgi values are picked up because cgi values and field edit_options will determine which fields are being removed.
		#and the client indirectly asking for this is CMC who need a radio button on a form to show/hide certain fields from the form and have the processing of the form be different based on what is submitted. specifically, if the luser asks for a little-bitch-booklet instead of the course, the CC fields should go away and also not be processed and they should be saved with a flag saying they are a little-bitch not a real customer. or something like that.
		#HRMM ... just had a thought -- if i remove fields here ... they will be saved in session ... luser will fuck the form up and retry it and then the fields wont even be part of the form for them to decide they want to fill out now ... see that would be a problem.
		#so maybe the best thing to do is just flag the fields as skip_save (existing save routine checks for a skip_field which is not used anywhere, so I can rename this to be specific for skipping save operation.
			#and also add skip_validate so that no validation happens either. 
		#another thing is that we must UNFLAG skip_save and skip_validate from fields if a previous submission had flagged them to be skipped but the current submission has us with options that should have them be included. Thats also super important.

	#going to attempt this with simple logic -- 
		#coniditional field skipping: if condition satisfied, make sure skip_* flags are set. if condition NOT satisfied, make sure skip_* flags are NOT set.
			#though we may have to eventually have more complex logic for figuring out if the condition is actually satisfied or not, like what if more than one field could control the same tagged groups? I dunno. that would be hairy and I'm not doing that right now.

	#yeah theres a bit of a naming issue here ... skip vs hide ... logically we are skipping the fields, but for the user the point of this is about hiding them on the form. hope not to become confused!
	my $fields = $ef_spec->{fields};
	my $hidefields = []; #parameter names of fields that MUST be skip_* flagged.
	my $showfields = []; #parameter names of fields that must NOT be skip_* flagged.

#	$self->ch_debug(['_pre_validate_editform_field_processing: going to see about flagging fields for skip_save and skip_validate']);
	#map out parameter names to de-json-ified field options. prep this first to make the rest easier and more efficient.
		#also, over in _build_select_sql I have a mapping of parameter names to field references (it actually gets stuck to the form in the ef_spec, which iirc is shared data across ef and sf specs .... it might make sense to code for this mapping right in the field gathering ... of course it also might make sense to provide de-jsonified (but leave json strings in tact) keys for json-ified things right there too .... 
#	my %field_mapping = map { $_->{parameter_name} => { edit_options => $_->{edit_options_decoded}, field_ref => $_} } @$fields;
#	my %field_mapping = map { $_->{parameter_name} => $_} } @$fields; #moved down.
#	####bigtime shit b/c of the edit_options/edit_options_decoded stupidity.
#		#coded this in TEST libraries on 20070319 to get TEST code to work with all required PROD apps and then get those into PROD so that I can update all prod templates and install latest HTC module. ugh.
#	foreach my $fld (@$fields) {
#		if ($fld->{edit_options}) {
#			#decode edit options. and make sure every fucking one is represented in the edit options. this is a fix for some weird shit that i dont know or have time to get to the bottom of right now but which is undoubtedly related to the stupidity with encoded and decoded edit options ad adding fields in the middle with encoded optinos that are not getting decoded or decoding is happening at the wrong time or i dont fucking know.
#			my $eo_decoded = JSON::Syck::Load($fld->{edit_options});
#			foreach (keys(%$eo_decoded)) {
#				$field_mapping{$fld->{parameter_name}}->{edit_options}->{$_} = $eo_decoded->{$_};
#			}
#		}
#	}

	#### THERE IS ONE CLASS OF FIELDS TO SKIP VALIDATION AND THAT IS ONES THAT THE VALUE MEANS SOME OTHER FIELDS DONT APPLY. SO THERE ARE TAGS FOR THOSE ... HIDEFIELDS TO HIDE(/SKIP) FIELDS (IDENTIFIED BY TAGS) FOR CERTAIN VALUES. See all the code to figure it out. CMCEduSignup USA mode.
		
	foreach my $field (@$fields) {
#		my $edit_options = $field_mapping{$field->{parameter_name}}->{edit_options};
		my $edit_options = $field->{edit_options};
#		$self->ch_debug(['_pre_validate_editform_field_processing: looking at a field with edit_options like:', $edit_options, 'presently interested in finding an option like "hidefields".']);
		if ($edit_options->{'hidefields'}) {
			#we might have to skip some other fields based on the value of this field. 
			#which ones might those be?
			my $hidefield_tags = $edit_options->{'hidefields'}->{tags};
			#so then are we hiding or showing the, (hide condition satisfied or not?)
			my $hide = 0; #assume we'll be unsetting skip options for the target fields.
			my $hide_for_values = $edit_options->{'hidefields'}->{for_values};
#			$self->ch_debug(['_pre_validate_editform_field_processing: found one with a hidefield option, param name:', $field->{parameter_name}, 'if hiding fields, should be for ones tagged like:', $hidefield_tags, 'and should do it for cgi_values like:', $hide_for_values, 'this field we are examining looks like', $field]);
			foreach my $value (keys(%$hide_for_values)) {
				if ($field->{cgi_value} eq $value) { $hide = 1; }
			}
#			$self->ch_debug(['_pre_validate_editform_field_processing: found one with a hidefield option, param name:', $field->{parameter_name}, 'if hiding fields, should be for ones tagged like:', $hidefield_tags, 'and should do it for cgi_values like:', $hide_for_values, 'based on examining the cgi value for our hide_values, our hide action status is:', $hide]);
			
			#now we think we know what to do -- hide or not hide (aka show).
			if ($hide) {
				#we think we have to skip fields identified by $hidefield_tags. lets find those fields, for each tag.
				$self->ch_debug(['_pre_validate_editform_field_processing: doing HIDE for fields controlled by this field:', $field->{parameter_name}]);
				foreach my $hide_for_tag (keys(%$hidefield_tags)) {
					$self->ch_debug(['_pre_validate_editform_field_processing: must find all fields tagged by:', $hide_for_tag, 'and add them to the hide list']);
#					push(@$hidefields, grep { $field_mapping{$_}->{edit_options}->{tags}->{$hide_for_tag} } keys %field_mapping);
					push(@$hidefields, grep { $_->{edit_options}->{tags}->{$hide_for_tag} } @$fields);
				}
			} else {
				#we think we have to ensure fields identified by $hidefield_tags are NOT flagged for skippage.
				foreach my $show_for_tag (keys(%$hidefield_tags)) {
#					push(@$showfields, grep { $field_mapping{$_}->{edit_options}->{tags}->{$show_for_tag} } keys %field_mapping);
					push(@$showfields, grep { $_->{edit_options}->{tags}->{$show_for_tag} } @$fields);
				}
			}
		}

#		#2007 03 19 edit, why not just do this here. add to hidefields.
		#This can't be here. its a logical error. the field could be set as a showfield after this fact if it was tagged such that it would qualify. really there are certain fields that MUST NEVER be validated/saved.
#		if ($skip_fld_types->{$field->{edit_fieldtype}}) {
#			$self->ch_debug(['should be skipping a field with param and type of:', $field->{parameter_name}, $field->{edit_fieldtype}, "$field"]);
#			push(@$hidefields, $field);
#		}

		#k now for showfields, the flipside of the above thing ... this should be able to be combined into the above.
	}
	
	#great, now we should know which fields need to be flagged for skip and which ones need to be NOT flagged for skip.
#	my %field_mapping = map { $_->{parameter_name} => $_} } @$fields; #but still dont need it bc now the arrays have fieldrefs in them.
#	foreach my $param (@$hidefields) {
	foreach my $field_ref (@$hidefields) {
		#my $field_ref = $field_mapping{$param}->{field_ref};
		$field_ref->{skip_save} = 1;
		$field_ref->{skip_validate} = 1;
		$self->ch_debug(['have set skip flags on a field like: ', $field_ref, "$field_ref" ]);
	}
#	foreach my $param (@$showfields) {
	foreach my $field_ref (@$showfields) {
		#my $field_ref = $field_mapping{$param}->{field_ref};
		$field_ref->{skip_save} = 0;
		$field_ref->{skip_validate} = 0;
		$self->ch_debug(['have set UNskip flags on a field like: ', $field_ref, "$field_ref" ]);
	}

	#### THERE IS A WHOLE OTHER CLASS OF FIELDS THAT SHOULD BE HANDLED HERE -- ANYTHING THAT THE FIELDTYPE MEANS NO VALIDATE OR SAVE OPERATION SHOULD HAPPEN WITH THE FIELD...
		##This list of skip field types is ripped right out of validate. Because the concept they are used for there is literally automatic flagging of skip fields and then we have this function here who's sole purpose is about flagging fields for skippage, well lets just do that flagging here now!
	my $skip_fld_types = $self->_skip_fld_types();

	
#	$self->ch_debug(['_pre_validate_editform_field_processing: in the end we should have flagged these for skip:', $hidefields, 'and these for no-skip', $showfields, 'you can see the flags in the fields!:', $ef_spec->{fields}]);
#	die "to stop";	
	
	#### THERE IS A WHOLE OTHER CLASS OF FIELDS THAT SHOULD BE HANDLED HERE -- ANYTHING THAT THE FIELDTYPE MEANS NO VALIDATE OR SAVE OPERATION SHOULD HAPPEN WITH THE FIELD...
		##This list of skip field types is ripped right out of validate. Because the concept they are used for there is literally automatic flagging of skip fields and then we have this function here who's sole purpose is about flagging fields for skippage, well lets just do that flagging here now!
#	my $skip_fld_types = {
#		SPACER => 1,
#		HEADING => 1,
#		DISPLAY_ONLY_SIMPLE => 1, 
#		DISPLAY_ONLY_COMPLEX => 1,
#		FORWARDFILL_CHECKBOX  => 1,
#	};
	foreach my $field (@$fields) {
		if ($skip_fld_types->{$field->{edit_fieldtype}}) {
			$field->{skip_save} = 1;
			$field->{skip_validate} = 1;
		} #now these field types will be set for skip_validate earlier in my presently brand new _pre_validate_editform_field_processing function.
	}
#	
	return $self;
}

sub _skip_fld_types {
	my $self = shift;

	return {
		SPACER => 1,
		HEADING => 1,
		DISPLAY_ONLY_SIMPLE => 1, 
		DISPLAY_ONLY_COMPLEX => 1,
		FORWARDFILL_CHECKBOX  => 1,
	};
}

#would like a func to validate each of the fields based on its rules against cgi_values by default and set any and all error flags.
sub _validate_field_values {
	my $self = shift;
	my $fields = shift;
	my $other_args = shift;
	
	#going to assume right now that I might want to be inspecting something other than the cgi_value attribute. For now, if not told what to do though, assume cgi.
	my $inspect = 'cgi';
	if ($other_args->{inspect}) { $inspect = $other_args->{inspect}; }
 	my $value_attrib = $inspect . '_value';
 
 	my $formerror = {};
 
	my $simple_values = $self->{fp}->_fields_simple_values($fields, { inspect => $inspect });	
	
	#lets define the field types that we would NEVER bother checking...
###now these field types will be set for skip_validate earlier in my presently brand new _pre_validate_editform_field_processing function.
#	my $skip_fld_types = {
#		SPACER => 1,
#		HEADING => 1,
#		DISPLAY_ONLY_SIMPLE => 1, 
#		DISPLAY_ONLY_COMPLEX => 1,
#		FORWARDFILL_CHECKBOX  => 1,
#	};

	#add more regexps as needed .... these should be a great start. maybe there should be a way for applications to define their own sets of these ... but for now lets keep one master(batory) list.
	my $validate_regex = {
		#EMAIL_ADDRESS	  => '^[\w.-]+\@([\w-]+\.)+\w+$',
		EMAIL_ADDRESS	  => '^[\w.-]+\@([a-zA-Z0-9]+\.)+[a-zA-Z0-9]+$',  #2009 08 21 having to rewrite this to disallow underscores in the domain part. Note we are NOT going for RFC822 compliance we are going for what I'm going to call "2009 defacto web app email standard". the main thing is complying with salesforce.com's unpublished email validation rule. which apparently does not allow underscore in the domain part. i also hear it does not allow apostrophe at all, which means if we were going for rfc822 we would be allowing stuff that would break salesforce. 
		NUMBER          => '^\d+$',
		CONTAINS_NUMBER => '^.*\d+.*$',
		NO_WHITESPACE   => '^\S+$',
	};

	my $error = 0;	
	my $record_id = $self->{'do'}->record_id(); #We want to know if there is a record id or not to know if we are validating based on us doing an insert or an update operation. Note i just changed this to pick up object's record id instead of having to be told.
	
	#now, how are these field validation rules defined?
	#$self->ch_debug(['validate_field_values: for record id:', $record_id, 'looking at this value attribute:', $value_attrib]);
	foreach my $field (@$fields) {
		#$self->ch_debug(['validate_field_values: for a field like:', $field]);
		
		my $skip_validate = 0;
		#if ($skip_fld_types->{$field->{edit_fieldtype}}) { $skip_validate = 1; } #now these field types will be set for skip_validate earlier in my presently brand new _pre_validate_editform_field_processing function.
		if ($field->{skip_validate}) { $skip_validate = 1; }

		if ($skip_validate) { 
			#ensure that there are no errors flagged on skip fields -- fields we arent validating cannot be allowed to have errors, but the fields might be displayed again so they must not be in an error state!
			$field->{required_error} = 0;
			$field->{field_dupe_error} = 0;
			$field->{baddata_error} = 0;
			$field->{field_error} = 0;
			next;
		}

		#3 main types of errors: missing, baddata, and dupe.
		my $field_error          = 0; #general unspecific error flag
		my $field_required_error = 0;
		my $field_dupe_error     = 0;
		my $field_baddata_error  = 0;
		my $field_value          = $field->{$value_attrib};
		
		my $field_value_present  = 1; #assume its present
		if ($field_value =~ /^\s*$/) {
			$field_value_present = 0; #unless its not.
		}
		
		my $rules        = $field->{edit_validate_rules};
		my $edit_options = $field->{edit_options};
		
		#$self->ch_debug(['going to apply these rules to the field:', $rules, 'the field value we must check against is', $field_value]);
		
		#required
		if ($rules->{required}) {

			if ((!$field_value_present) && !($record_id && ($field->{edit_fieldtype} eq 'TEXTINPUT_PASSWORD'))) {
				#if BLANK and NOT -->EDITING a PASSWORD field<--:
				#that is, if the field is required and the cgi param bearing the parameter name of the field has only whitespace
				$field_required_error = 1;
			}
			if (($field->{edit_fieldtype} eq 'SINGLESELECT_CHECKBOX') && (!$field_value)) {
				$field_required_error = 1;
			}
			
			if ($field->{edit_fieldtype} eq 'COMBO_RADIO_CONTROLLED_FIELD') {
				$field_required_error = 0; #reset this since the rules are a little more complex for this bad boy.
				#if either of the values are not present we have a required error.
				my $vtm = $field->{rcf_control}->{value_to_type_map};
				#firstly, if we didnt get a value for the radio, then we can error out and skip the rest.
				if ($field_value =~ /^\s*$/) {
					$field_required_error = 1;
				} else {
					#so, we got a value for the radio. do we need antyhig else to not error out?
					if (($vtm->{$field_value} eq 'text') && ($field->{subfields}->{text}->{$value_attrib} =~ /^\s*$/)) {
						$field_required_error = 1;
					} elsif (($vtm->{$field_value} eq 'select') && ($field->{subfields}->{'select'}->{$value_attrib} =~ /^\s*$/)) {
						$field_required_error = 1;
					}
				}

				#$self->ch_debug(['to validate a COMBO_RADIO_CONTROLLED_FIELD field like this:', $field, 'presently we think field required error is:', $field_required_error]);
			}
			
			###super simple error reporting. come up with something better as its needed.
			if ($field_required_error && ($edit_options->{required_error_message} || $edit_options->{required_error_stringsuffix}) ) {
				my $message = $edit_options->{required_error_stringsuffix} ? $self->{wa}->get_strings('field_required_error__' . $edit_options->{required_error_stringsuffix})->{'field_required_error__' . $edit_options->{required_error_stringsuffix}} : $edit_options->{required_error_message};
				push(@{$formerror->{required_error_messages}}, { message => $message } );
			}
		}
		
		#$self->ch_debug(['going to apply these rules to the field:', $rules]);

		
		#conditionally required (not going to do the password field thing here) -- also doing a required_unless probably wouldnt be hard.
		if ($rules->{required_if}) {
			#to make it required if some field has a SPECIFIC value, going to add to the notation with a colon. -- equals sign is waaaay used already.
			my ($check_param, $check_value) = split(/\:/, $rules->{required_if});
			if ($check_value && ($simple_values->{$check_param} eq $check_value) && !$field_value_present) { 
				#need to check that some other param got some SPECIFIC value to know if this field is actually required.
				$field_required_error = 1; #should probably be more complex tho and indicate WHY the required error occurred. whatev.
			} elsif ($simple_values->{$check_param} && !$field_value_present) { 
				#need to check that some other param got SOME KIND OF value to know if this field is actually required.
				$field_required_error = 1; #should probably be more complex tho and indicate WHY the required error occurred. whatev.
			}
		}
					
		#nodupe
			#check that the nodupe field doesnt collide with a record that exists (unless EDITING and the occurence is that of the row we're EDITING) .. get the table and field name from the form field defintion.
		if ($rules->{nodupe}) {
			#if the nodupe flag is just a simple truth then we need to be simply checking that the value doesnt already exist in the form's base table.
			#if the nodupe flag is a tablename.fieldname then we have to make sure that the value doesnt exist in THAT table.field
			my ($db_table,$db_field) = split(/\./, $field->{db_field_name});
			if ($rules->{nodupe} ne '1') {
				#more complex nodupe matching when nodupe is something other than a plain truth.
				if ($rules->{nodupe} =~ /^(\S*)\.(\S*)$/) {
					#table.field to match against
					($db_table,$db_field) = ($1, $2);
				} else {
					#just field name to match against -- assume same table .... maybe signup_username must not dupe the real_username field .. for example.
					$db_field = $rules->{nodupe};
				}
			}

#			my $dbh = $self->get_dbh();
			my $dbh = $self->{'do'}->_get_data_dbh();
			my $sql = "SELECT id FROM $db_table WHERE $db_field = ?"; ##ASSUME there is an id field
			#$self->ch_debug(["nodupe rule like:",$rules->{nodupe}, $rules, $sql, $field_value]); 
			#die "doing a nodupe check - what re the args";
			my $row = $dbh->selectrow_hashref($sql, undef, $field_value);
			#if we get a row here (and if we're editing and the id from this query is different than the id we're editing), it means theres a dupe that we need to flag as an error
			if ($record_id && ($row && ($row->{id} ne $record_id))) {
				$field_dupe_error = 1; #because we're EDITING and theres a DUPE and the ID of the dupe is NOT the RECORD we're EDITING
			} elsif (!$record_id && $row) {
				$field_dupe_error = 1; #because we're CREATING and there was a row returned meaning a match/dupe was found.
			}

			###super simple error reporting. come up with something better as its needed.
			if ($field_dupe_error && ($edit_options->{nodupe_error_message} || $edit_options->{nodupe_error_stringsuffix}) ) {
				my $message = $edit_options->{nodupe_error_stringsuffix} ? $self->{wa}->get_strings('field_nodupe_error__' . $edit_options->{nodupe_error_stringsuffix})->{'field_nodupe_error__' . $edit_options->{nodupe_error_stringsuffix}} : $edit_options->{nodupe_error_message};
				push(@{$formerror->{nodupe_error_messages}}, { message => $message });
			}
		}

		#the rest of the rules only operate if the field has a value. .. i had it to just run the next iteration before ... but now I really want it to get to the bottom and do the flags down there.
		if ($field_value_present) {

			#a little sanity check ... if we're to be checking against some other value, make sure that other value EXISTS ... die otherwise. b/c if it doesnt, we probably coded the wrong 'check-against' param name in the rule.
			foreach ('eq', 'gt', 'lt') {
				if ($rules->{$_} && !exists($simple_values->{$rules->{$_}})) { die "Can't compare $_ for a param '$rules->{$_}' that does not appear in the simple values. Did you define the comparison parameter correctly?"; }
			}
			
			#equals, greater than, less than
			if ($rules->{eq} && $field_value ne $simple_values->{$rules->{eq}})    { $field_baddata_error = 1;	}
			if ($rules->{gt} && !($field_value gt $simple_values->{$rules->{gt}})) { $field_baddata_error = 1;	}
			if ($rules->{lt} && !($field_value gt $simple_values->{$rules->{lt}})) { $field_baddata_error = 1;	}
			
			#regex
			if ($rules->{regex}) {
				if (ref($rules->{regex}) ne 'ARRAY') { $rules->{regex} = [ $rules->{regex} ]; }
				$self->ch_debug(["regex rules coded:", $rules->{regex}]);
				foreach my $regex (@{$rules->{regex}}) {
					#remember I said I wanted an arrayref for these. 
						#what happens if a non-existent named regex is used? My guess? nothing, it will match and not cause the error.
					if ($field_value !~ /$validate_regex->{$regex}/) { 
						$field_baddata_error = 1; 
						last; 
					} #but if we fail in even one of these, we suck and must stop.
					$self->ch_debug(["result of baddata_error after checking field value $field_value against regex $validate_regex->{$regex} was $field_baddata_error"]);
				}
			}
			
			#captcha ... of type "recaptcha"
			if ($field->{edit_fieldtype} eq 'CAPTCHA_RECAPTCHA') {
				my $c = Captcha::reCAPTCHA->new;
				my $captcha = $field->{cgi_value__captcha};
				my $remote_addr = $self->{wa}->env('remote_addr');
				my $privkey = $self->{wa}->config('recaptcha_privkey');
				my $result = $c->check_answer($privkey, $remote_addr, $captcha->{challenge}, $captcha->{response});
				if (!$result->{is_valid}) {
					$field_baddata_error = 1;
					$self->ch_debug(['_validate_field_values for a CAPTCHA_RECAPTCHA we think the captcha failed to validate - here is reported error:', $result->{error} ]);
				}
			}

			###super simple error reporting. come up with something better as its needed.
			if ($field_baddata_error && ($edit_options->{baddata_error_message} || $edit_options->{baddata_error_stringsuffix}) ) {
				my $message = $edit_options->{baddata_error_stringsuffix} ? $self->{wa}->get_strings('field_baddata_error__' . $edit_options->{baddata_error_stringsuffix})->{'field_baddata_error__' . $edit_options->{baddata_error_stringsuffix}} : $edit_options->{baddata_error_message};
				push(@{$formerror->{baddata_error_messages}}, { message => $message });
			}

			##### 2009 07 13. Well its been a long ass time since I added anything serious to this code. But I think the time is right to implement a simple idea I've had kicking around which is to have validate subref on a per-field basis. these validate subs should always be coded on the data object itself. unlike the validate_hook that is always part of a webapp caller object and will do general oddball validations for a particular form submission, this approach will happen always during fieldsauuto validation of that form processing process.
				#it seems also that I should only do validate subs if there was a field value present. seems reasonable since we can always code required rule on the field to make sure it has a value present.
			if ($field->{validate_sub}) {
				#documentation (lol):
					#code a string name of the validate sub (which must live in the dobj NOT the webapp btw) in the validate_sub key of the field ref.
					#your validate sub will get obj ref and then a hashref with: field_value (the value of the field), and formerror hashref.
					#your validate sub must return a hashref if it is going to flag field level errors. the hashref should have a key of required_error, dupe_error or baddata_error, depending on what type of error it was.
					#your validate sub can also include in its return hashref a key of field_value, which if present will overwrite the existing field value with this new one.
					#returning messages: args will include 'formerror' hashref. valid structure of this hash is keys of baddata_error_messages, nodupe_error_messages or required_error_messages that point to arrayrefs of hashrefs structured like { message => 'the error text' }. push in error text manually as apropriate.
				#INCONSISTENCY NOTE: for the nodupe stuff, the error type is 'dupe_error', but related messages go under 'nodupe_error_messages' the arrayref in the formerror hashref.
				#Other note: dont forget you are inside dataobj and have full access to everything including fieldrefs of other fields.
				#my $validation_rpt = $field->{validate_sub}->($self, {field_value => $field_value, formerror => $formerror });
				my $validate_call = '$self->{do}->' . $field->{validate_sub} . '({field_value => $field_value, formerror => $formerror, fieldref => $field })';
				my $validation_rpt = eval "$validate_call";
				$self->{wa}->ch_debug(['_validate_field_values: got this validation_rpt back after evalling this code:', $validation_rpt, $validate_call ]);
				if ($@) { die "Error executing _validate_field_values for a field level custom validator callback '$field->{validate_sub}': $@"; }
				if (!$validation_rpt || (ref($validation_rpt) ne 'HASH')) { die "Error: a validate_sub was called but it did not return a hashref"; }
				if ($validation_rpt->{required_error}) { $field_required_error = 1; }
				if ($validation_rpt->{dupe_error})     { $field_dupe_error = 1; }
				if ($validation_rpt->{baddata_error})  { $field_baddata_error = 1; }
				if ($validation_rpt->{field_value})    { $field_value = $validation_rpt->{field_value}; } #the power ... and the pain?
			}

		}

		#basic error reporting --- leave detailed error reporting to a separate func which will just pick up flags and do gay things with field headings and shit I have no idea about at the moment. scope baby. scope.
			#adding elses so that session fields that were once flagged error but no longer are will go back to being non-error!.
		if ($field_required_error) { $field->{required_error} = 1; $formerror->{required_error} = 1; $field_error = 1; } else { $field->{required_error} = 0; }
		if ($field_dupe_error)     { $field->{dupe_error} = 1;     $formerror->{dupe_error} = 1;     $field_error = 1; } else { $field->{field_dupe_error} = 0; }
		if ($field_baddata_error)  { $field->{baddata_error} = 1;  $formerror->{baddata_error} = 1;  $field_error = 1; } else { $field->{baddata_error} = 0; }

		if ($field_error) {
			$field->{field_error} = 1;
			$error = 1;
		} else {
			$field->{field_error} = 0;
		}
	}
	
	#die "yeah here with error status of $error (we'll return the opposite)";

	if ($error) {
		$formerror->{validated} = 0;
	} else {
		$formerror->{validated} = 1;
	}
	return $formerror;

}

sub _session_fields {
	my $self = shift;
	my $args = shift;
	
	#overhauling the usage of this. from now on we're ALWAYS saving/loading the fields of the main form_spec.
		#when we load up, we should freshen up the main parameter to fieldref mapping and the fieldrefs in any registered fspec.
	
	#ok this just returns 1 unless called with load_for_screen then it returns the fields. and you have to sue THOSE fields.
	
	#i think I either want to save fields or load them.
	my $session = $self->{wa}->session();
	if (!defined($session->param('_data_obj_saved_fields'))) { $session->param('_data_obj_saved_fields' => {}); }

	if ($args->{save_for_screen}) {
		my $sfs = $args->{save_for_screen};
		
		#maybe we could be given f_fields, ef_fields, or sf_fields, but I think we just want to grab the current status of all of them and save em.
		$session->param('_data_obj_saved_fields')->{$sfs} = {
			f  => $self->{'do'}->form_spec()->{fields},
			ef => $self->{'do'}->{ef_specced} ? $self->{'do'}->editform_spec()->{fields} : undef,
			sf => $self->{'do'}->{sf_specced} ? $self->{'do'}->searcform_spec()->{fields} : undef,
		};
		#$session->param('_data_obj_saved_fields')->{$sfs} = $fields;
		#$self->ch_debug(['session_fields: saving these fields', $fields]);
	}
	
	if ($args->{clear_for_screen}) {
		my $cfs = $args->{clear_for_screen};
		delete($session->param('_data_obj_saved_fields')->{$cfs});
		return 1;
	}

	if ($args->{load_for_screen}) {
		my $lfs = $args->{load_for_screen};
		my $field_groups = $session->param('_data_obj_saved_fields')->{$lfs};
		if (!$field_groups) { return 0; } #nothing was saved there, nothing to do.

		#freshen param to fieldref map (based on nodupes list of allfields produced by going over merged fields of each field group.)
			#this is potential source of error if that $allfields->{"$_"} thing dont work right or if somehow the fieldrefs that should be the same ref in 3 lists turns out to be 3 different references somehow omg.
		my $allfields = {};
		foreach (keys(%{$field_groups})) {
			my $fields = $self->{fp}->_get_merged_fields_and_subfields($field_groups->{$_}); 
			foreach (@$fields) {
				$allfields->{"$_"} = $_; #stringify for the key, point to the fieldref. ... hoping this works the way I epect. just want a complete nodupes list of fields to do _parameter_to_fieldref on.
			}
		}
		foreach (keys(%$allfields)) {
			$self->{fp}->_parameter_to_fieldref($allfields->{$_});	
		}

		$self->{'do'}->form_spec()->{fields} = $field_groups->{f};
		if ($self->{'do'}->{ef_specced} && $field_groups->{ef}) {
			$self->{'do'}->editform_spec()->{fields} = $field_groups->{ef};
		}
		if ($self->{'do'}->{sf_specced} && $field_groups->{sf}) {
			$self->{'do'}->searchform_spec()->{fields} = $field_groups->{sf};
		}

#		#ensure all fspecs (f, ef, sf) refer to _these_ fields.
#		my $form_specs = [ $self->{'do'}->form_spec() ];
#		if ($self->{'do'}->{ef_specced}) { push(@$form_specs, $self->{em}->editform_spec()); }
#		if ($self->{'do'}->{sf_specced}) { push(@$form_specs, $self->{sm}->searchform_spec()); }
#		
#		foreach my $form_spec (@$form_specs) {
#			foreach (@{$form_spec->{fields}}) {
#				my $loaded_fld = $self->{'do'}->{_fieldrefs}->{$_->{parameter_name}};
#				$_ = $loaded_fld ? $loaded_fld : $_; #update if we found.
#			}
#		}

		return 1;
		#$self->ch_debug(['session_fields: loading these fields (are they being assinged?)', $fields]);
	}
	
	return undef; #i suppose if we didnt get any useful args we wont be doing much at all.
}

#not sure I really want to put formerrors in the session. I am thinking now that I really want to validate in two place: 1) during processing of the submission to know what needs to happen next (submission conf of retry_form), and then in get_editform for a retry, to re-flag everything, especially given that something could have changed since the form was last retry'd like in CMCEduFree where they can go select the course.
	#maybe I do ... i know I want to be ABLE to show the special error messages when returning to a form even when not doing retry_revalidate
sub _session_formerror {
	my $self = shift;
	my $args = shift;

	my $error = $args->{error};

	my $session = $self->{wa}->session();
	if (!defined($session->param('_data_obj_saved_formerrors'))) { $session->param('_data_obj_saved_formerrors' => {}); }

	if ($args->{save_for_screen} && $error) {
		my $sfs = $args->{save_for_screen};
		$self->ch_debug(['_session_formerror: here with these form errors: ', $error]);
		#die "stop to see what we'll save for form errors";
		$session->param('_data_obj_saved_formerrors')->{$sfs} = $error;
	}
	if ($args->{clear_for_screen}) {
		my $cfs = $args->{clear_for_screen};
		delete($session->param('_data_obj_saved_formerrors')->{$cfs});
		return 1;
	}
	if ($args->{load_for_screen}) {
		my $lfs = $args->{load_for_screen};
		$error = $session->param('_data_obj_saved_formerrors')->{$lfs};
		if (!$error) { $error = {}; }
		return $error;
	}
	
	return undef; #i suppose if we didnt get any useful args we wont be doing much at all.
}


##adding this formstatus one for one purpose: the scenario is that amifx form user completed the form properly, then used the back arrow in a shitty browser to reload the form. the reloaded form was cached and not actually hitting the server to reload it. SOooo ... the successful save caused some db action to happen and then the data object cleared the session fields as per usual because its done. But when user uses back button in IE7 it redisplays the form without hitting the server. and since it doesnt hit the server, get_editform doesnt get called, the fields are still cleared in the session. user fills this cached form in again and submits, process_form_submission finds no session fields and so does its BASIC standard_editform_fields, to at least be able to pick up cgi values etc. if this submission generates an error we will go back to retry_form BUT WE NEVER PROPERLY SET UP THESE FIELDS THEY WONT HAVE LISTOPTIONS OR BE SET UP FOR CAPTCHAS. Now of course this scenario shouldnt really arise. its due to stupid browsers and user behaviour and not using the proper entry points. But since it _CAN_ happen we need to try and handle it cleanly ....
#	#so what I'm thinking to solve the problem and FORCE a proper resetting of the form fields is to set a form status that says it is expired/processed, meaning that we can say for CERTAIN that the sessionized fields need to be rebuilt/reflagged.
####then another thought occurred that had me comment this out immediately after writing it .... WHY ARE WE CLEARING SESSION FIELDS AFTER THE SUCCESSFUL SAVE ANYWAY? Just wonderin.
#sub _session_formstatus {
#	my $self = shift;
#	my $args = shift;
#
#	my $status = $args->{status};
#
#	my $session = $self->{wa}->session();
#	if (!defined($session->param('_data_obj_saved_formstatus'))) { $session->param('_data_obj_saved_formstatus' => {}); }
#
#	if ($args->{save_for_screen} && $status) {
#		my $sfs = $args->{save_for_screen};
#		$self->ch_debug(['_session_formstatus: here with these form status: ', $status]);
#		#die "stop to see what we'll save for form statuss";
#		$session->param('_data_obj_saved_formstatus')->{$sfs} = $status;
#	}
#	if ($args->{clear_for_screen}) {
#		my $cfs = $args->{clear_for_screen};
#		delete($session->param('_data_obj_saved_formstatus')->{$cfs});
#		return 1;
#	}
#	if ($args->{load_for_screen}) {
#		my $lfs = $args->{load_for_screen};
#		$status = $session->param('_data_obj_saved_formstatus')->{$lfs};
#		if (!$status) { $status = {}; }
#		return $status;
#	}
#	
#	return undef; #i suppose if we didnt get any useful args we wont be doing much at all.
#}

sub _set_save_values {
	#purely to go over fields and pull values from some attribute into one called save_value. so that the save_record routine can be run.
	my $self = shift;
	my $fields = shift;
	my $other_args = shift;
	if (!$other_args->{inspect}) {
		die "set_save_values needs to know what attribute to inspect. sorry.";
	}
	my $value_attrib = $other_args->{inspect} . '_value';

	###going to need to code for the subfields of a COMBO_RADIO_CONTROLLED_FIELD shit here.
		#obtain merged fields list .. fields and their subfields all as a flat list.
	my $sql_fields = $self->{fp}->_get_merged_fields_and_subfields($fields);
	foreach (@$sql_fields) {
#	foreach (@$fields) {
		$_->{save_value} = $_->{$value_attrib};
	}
	return 1;
}

#### Functions to get fields in
#_inject_edit_fields  (created to add some fields for slapping in some extra values during a save operation, and is also used to slap some in during initialization, but mainly just to set the values of certain fields so they can be saved)
#_add_editform_fields (created to add some fields to a form that will be working fields and be validated but which might not save to the db directly)
#_init_form_spec      (created to add some fields to a form that are defined purely with fieldref hashrefs, at the time of object initialization, as a replacement for the fields gathering code in _build_form_spec. and then to use that form in standard ways like showing, validating, saving, etc. -- this last one because today I want to define data objects in code. I want to do this because I am concerned about promoting data object changes up from dev->test->prod, and because I'm jealous of Django. and yeah I want object relationships too!)
#_save_operation_field_injection (which is just using _inject_edit_fields but you know, actually doing some postprocessing like _complex_custom_fieldshit, _set_efspec_fieldtype_flags)

#added _inject_edit_fields with the following usage in mind:
	#call to process_form_submission with an argument like pre_save_inject_fields => [{ db_field_name => table.fieldname, inject_value => 'foo' }]
sub _save_operation_field_injection {
	my $self = shift;
	my $args = shift;
	
	#inject fields and get back the updated fields that might need further standard field processing.
	my $updated_fields = $self->_inject_edit_fields($args);
	foreach my $field_ref (@$updated_fields) {
		$self->{fp}->_complex_custom_field_init($field_ref);	
	}

	#merge with subfields and do operations that have to happen on every. single. field. subfield or not.
	my $merged_updated_fields = $self->{fp}->_get_merged_fields_and_subfields($updated_fields); #get merged with subfields in case we added any fields that have subfields.
	foreach my $field_ref (@$merged_updated_fields) {
		$self->{fp}->_set_efspec_fieldtype_flags($args->{form_spec}, $field_ref);	
		$self->{fp}->_parameter_to_fieldref($field_ref);	
	}
}

sub _inject_edit_fields {
	my $self = shift;
	my $args = shift;

	#$self->ch_debug(['_inject_edit_fields: with args like: ', $args]);
	#ok be a little less forgiving.
	my $form_spec = $args->{form_spec};
	if (!$form_spec) {
		$self->error('_inject_edit_fields needs to be passed a form_spec -- it could even come from the form_spec() method (or editform_spec or searchform_spec I am sure)');
	}

	my $added_or_modified_fields = [];
	my $fields = $form_spec->{fields};
	my $inject_fields = $args->{inject_fields};
	my $target = $args->{target};
	if (!$args->{target}) {
		#what should the default target _value type be? go with cgi since this whole shit is being coded as a hook in process_form_submission and the set_save_values which comes before the save operation will pick up from things named as cgi.
		$target = 'cgi';
	}
	my $value_attrib = $target . '_value';
	
	#SOMETHING to be careful about with inject_values is when the fields are loaded up from the session repatedly, each time you inject you'll be adding the same fields over again and it will mean they are in there twice or more. I've solved this in one case by having the process_form_submission clear session fields for the screen after a good validation.
		#and that is stupid -- so I will modify it to only ADD the field if it doesnt already exist in the fields, and otherwise I will just set the value.
		#also just renamed from inject_values to inject_edit_values since is IS only working off an ef_spec that it obtains by itself.
	
	#here we will add fields as needed and set new values for existing ones.
		#we need to set a parameter_name, a db_field name, a foo_value (cgi_value by default), and a flag to let us know it is an injected field. (I think a flag for injected_field might make sense in case i need to strip out later.)
		#note all fields have to have parameter_names so we can just come up with them if they werent provided.
	foreach my $inject_field (@$inject_fields) {
		my $field_ref = {}; #if we find it, it will be here, if we didnt find it, we'll make it here and add it.
		my $found_existing = 0;

		#figure out the param name of the field we're looking for in the edit fields (if it wasnt specified explicitly)
		my $inject_value = $inject_field->{inject_value};
		my $param = $inject_field->{parameter_name};
		my $db_field = $inject_field->{db_field_name};

		if (!$param && $inject_field->{db_field_name}) {
			#so we were told db_field_name but NOT a param name .. thats ok, we can make up a param name then.
			$param = $db_field;
			$param =~ s|\.|_|g;
		}

		#go over the fields of the editform, and either find the one we are injecting a value for and reference it, or record the fact that we have to completely add the field.
		foreach (@$fields) {
			if ($_->{parameter_name} eq $param) {
				$found_existing = 1;
				$field_ref = $_;
				last;
			}
		}
		
		#did we NOT find an existing field? establish it then. otherwise, maybe just override some things in the existing one.
		unless ($found_existing) {
			#did not find existing one. make it.
			$field_ref = {
				db_field_name      => $db_field,
				parameter_name     => $param,
				#$value_attrib      => $inject_value,
				#injected_field     => 1,
				#edit_show_field    => 1,
			};
			
			#push in the now established field ref
			push(@$fields, $field_ref);
		} else {
			#just be able to override the db field name of some existing one.
			if ($db_field) {
				$field_ref->{db_field_name} = $db_field; #of course I'm coding to allow for this override without actually needing it ... which means I'm getting ahead of myself and should STOP!
			}
		}
		

		#set attribs that will apply to the field whether we found an existing field ref to update or are workign with a new one.
			#i think its safe to assume that the db_field_name and the parameter_name will already be set if we FOUND THE FREAKIN field by parameter name in the existing freakin list.
			#so just set the value and the injected flag
		$field_ref->{injected_field} = 1;
		$field_ref->{edit_show_field}   = exists($inject_field->{edit_show_field})   ? $inject_field->{edit_show_field}   : 1; 
		$field_ref->{search_show_field} = exists($inject_field->{search_show_field}) ? $inject_field->{search_show_field} : 1;

		#only set the value (in the specified target value attribute) if an inject_value was actually provided. (as long as the key is there, go with it even if its undef -- maybe we want to set a db field to NULL or something.)
		if (exists($inject_field->{inject_value})) {
			$field_ref->{$value_attrib} = $inject_value;
		}
		#and for display value too, one can be provided.
		if (exists($inject_field->{inject_value_disp})) {
			$field_ref->{$value_attrib . '_disp'} = $inject_field->{inject_value_disp};
		}
		
		#ensure presence in the parameter_to_fieldref map.
		$self->ch_debug(['_inject_edit_fields: adding a fieldref to the parameter_to_fieldref map, at a param named: ', $field_ref->{parameter_name}]);

		push(@$added_or_modified_fields, $field_ref);
	}

	#$self->ch_debug(['_inject_edit_fields: after processing, the ef spec fields look like: ', $fields]);

	#return $self;
	return $added_or_modified_fields;
}

sub _add_editform_fields {
	my $self = shift;
	my $ef_spec = shift;
	my $add_fields = shift;
	my $other_args = shift;
	
	#so we are going to add fields in, these will be fields that should be shown to gather user input and to be validated, but which may not (and will not in the case that this is being coded for) be saved into the DB -- they DONT have to have a db_field_name, and if they dont then the save record stuff should skip over them.
		#the order in which we add them shouldnt matter, because a display order should be coded into them. if NOT, then for now lets just die if a display order is missing.
	my $fields = $ef_spec->{fields};

	foreach my $parameter_name (keys (%$add_fields)) {
		my $field_ref = $add_fields->{$parameter_name};
		#use the key of the add_fields hash as the parameter name, unless there already is a parameter name.
		$field_ref->{parameter_name} = $parameter_name unless $field_ref->{parameter_name};
		$field_ref->{edit_show_field} = 1; #kinda important.
		$field_ref->{attrib_sources} = { all => 'Field Added by _add_editform_fields (presumably all attrs are hardcoded in source)' };
		#what else has to happen to them?
			#in future, if no display order is set, establish one ... for now just die.
		if (!$field_ref->{edit_display_order}) {
			$self->error("_add_editform_fields: encountered a field without an edit_display_order. This should in future be auto-recoverable.");
			die "_add_editform_fields: error: encountered a field without an edit_display_order. This should in future be auto-recoverable.";
		}
		
		#set ef_spec flags based on fieldtype. 
		$self->{fp}->_set_efspec_fieldtype_flags($ef_spec, $field_ref);
#		$self->{fp}->_add_field_edit_options($field_ref, { key => 'add_edit_options' });
#		$self->{fp}->_add_field_edit_validate_rules($field_ref, { key => 'add_edit_validate_rules' });
		$self->{fp}->_add_field_properties($field_ref, { property => 'edit_options',        from_key => 'add_edit_options', highlevel_prefix => 'eo'  });
		$self->{fp}->_add_field_properties($field_ref, { property => 'edit_validate_rules', from_key => 'add_edit_validate_rules' });
		
		#ensure presence in the parameter_to_fieldref map.
			#or maybe we dont really need to do dont bother.
		
		push(@$fields, $field_ref);
	}
	
	return 1;
}

#This field_preprocessing function is to do something to the fields AFTER the sql has been built with them, but BEFORE the query is executed and the results created
	#this is so that our results include the things that they contextually should, and exclude those things that should logically be exlcluded.
sub _standard_editform_fields {
	my $self = shift;
	my $fields = shift;
	my $other_args = shift;
	
	#first strip out non-edit_show_field ones.
	$self->{fp}->_filter_fields($fields, {edit_show_field => 1});

	#include some field level validate rule flags, especially required. This is purely so we can indicate to the luser what is expected of them!
	foreach (@$fields) {
		#set fieldtype code in a way for easy templating. .. eft is edit_fieldtype
		$_->{'eft_' . $_->{edit_fieldtype}} = 1;

		#for unspecified edit_display_order, fall back to sql_query order. used below in our edit-order field sort.
		if (!$_->{edit_display_order} && $_->{sql_query_order}) { $_->{edit_display_order} = $_->{sql_query_order}; }

		my $rules = $_->{edit_validate_rules};
		if ($rules->{required}) {
			$_->{edit_field_required} = 1;
		}
		#any others? what about nodupe fields, maybe include a message about those? not sure what form that'd take yet.

	}

	#sort by edit display order, falling back to others as required.
	@$fields = sort {
		$a->{edit_display_order} <=> $b->{edit_display_order}
	} @$fields;

	return 1;
}

sub _standard_editform_field_postprocessing {
	#now I think I might be getting in over my head ... I'm doing this function here because I dont want to be referncing 'db_value' in the editform template ... i want it to have an edit_value ... which might come from ... anywhere. generally it will come from the db to start, and then retry fields of some kind after failed validation or something. not sure yet.
		#yeah this might not be the right approach. I think I'm getting ahead of myself. and I know what happens now when I get ahead of myself.
	
	#ok ... edit_values and listoptions here. this is to be run AFTER values are picked up from somewhere -- db, cgi, whatever.
	
	my $self = shift;
	my $fields = shift;
	my $other_args = shift;
	
	if (!$other_args->{inspect}) {
		$self->error("editform field posprocessing needs to know what attribute to inspect. sorry.");
	}
	#$self->{wa}->dbg_print(['_standard_editform_field_postprocessing: here1: the curent errror is:', $self->error() ]);
	return $self if ($self->error());

	my $value_attrib = $other_args->{inspect} . '_value';

	#i want to include subfields in this so that they also get an edit_value set.
	my $merged_fields = $self->{fp}->_get_merged_fields_and_subfields($fields);
	#$self->{wa}->dbg_print(['_standard_editform_field_postprocessing: here2: the merged fields are like:', $merged_fields ]);

	foreach (@$merged_fields) {
#	foreach (@$fields) {
		#$self->ch_debug(['_standard_editform_field_postprocessing: going to apply an edit value on a field with a param named:', $_->{parameter_name}]);

		$_->{edit_value}      = $_->{$value_attrib};
		$_->{edit_value_disp} = $_->{$value_attrib . '_disp'};
		
		#add the edit options for templating
			#only if not explicitly "done already" (note this is 20070131 experimental, just want to not do it if it was already done for a custom field like CMC's COMBO_RADIO_CONTROLLED_FIELD that needed them early for the SQL part of the process to know about the subfields.)


		
		#SELECT (single, multi) listoptions.
		if ($_->{edit_fieldtype} =~ /^.*SELECT_.*$/) { 
			#should decide whether to get listoptions from db or from code.
				#will do that by seeing if a key for the field's parameter name exists in the return of the _field_listoptions function (which it wont for ones that dont define it)
			my $lo_source = 'db';
			if (exists($self->{'do'}->_field_listoptions()->{$_->{parameter_name}})) { $lo_source = 'code'; } #if theres a key in the hashref we get...
			if ($_->{edit_options}->{lo_from_code})                                  { $lo_source = 'code'; die "in this case, how would we know what code to run to get the listoptions??? guess I've never used this, but it would need to be the name of a function that was gonna run from a known thing like the owning wa."; }

			#$self->ch_debug(['_standard_editform_field_postprocessing: current parameter name and lo_source (and result of call to _field_listoptions)', $_->{parameter_name}, $lo_source, $self->{'do'}->_field_listoptions() ]);

			##2007 03 05 - I also think here it is important to decode JSON'd multiselect values into the array they should probably be. this is experimental.
			##and 2007 04 16 err do this inside this other block now. and totally hacked it up.
				##probably for cmcreg fif stuff. it is inconsistent with the what we do for cgi_values pickup. but its not too bad. we can do similar and at least get the __multi thing set up.
				#also, if get_field_listoptions is going to do something useful, like set selected values, we should be doing this before we doing _get_field_listoptions_from_*
			my $multi = ($_->{edit_fieldtype} =~ /^MULTISELECT_/) ? 1 : 0;
			if ($multi) {
				#put edit_value from decoded json for multi for fif, and for setting selected values in get_field_listoptions. the handle the display-from-listoptions related stuff that is useful for multiselect fields.
				#multiselect values from a JSON dump back into perl data. #2007 04 16 heheheoops.
				$_->{edit_value} = $_->{edit_value} ? JSON::Syck::Load($_->{edit_value}) : undef;
			}
		
			if ($lo_source eq 'db') {
				$_->{edit_listoptions} = $self->{lo}->_get_field_listoptions_from_db($_->{sql_value_lookup}, $_->{edit_value}, {field_ref => $_});
			} else {
				$_->{edit_listoptions} = $self->{lo}->_get_field_listoptions_from_code($_, { selected_value => $_->{edit_value} });
			}

			my $display_value_from_listoptions = 0;
			if ($multi) {
				$_->{edit_value__multi_values} = $_->{edit_value}; #2007 04 16 prep for _display_value_from_listoptions since this is useful.
				$display_value_from_listoptions = 1;
			} elsif ($_->{edit_options}->{display_value_from_listoptions}) { #2007 06 08 - sometimes we have a SINGLESELECT_DROPDOWN that is not using an sql_value_lookup to get a nice display value for its display-only modes. In such cases I'd like to explicity request that the display vlaue be picked out of listoptions.
				$display_value_from_listoptions = 1;
			}
			if ($display_value_from_listoptions) {
				$self->{fp}->_display_value_from_listoptions($_, { inspect => 'edit' }); ##2007 04 16 and do the code of _display_value_from_listoptions on it too, that which we wrote 4 days after the initial lines of this little hack
			}

			$_->{edit_listoptions_source} = $lo_source; #just for reference.
		}

		#COMBO_RADIO_CONTROLLED_FIELD and other shit ... will only handle field types it knows about. should refer to edit_value(s) unless told otherwise. 
		$self->{lo}->_complex_custom_field_edit_listoptions($_, $other_args);

		#probably should do the plaintext html, text wrapping, short text, etc here instead of inside _perfom_select. also should havea viewform postprocessign or something.
		
		#2009 11 17 handling fileinput in a bit more detail for uploading little pdf files for a bmg fpm system template record. would like to provide more info about the existing file associated with the record for linking to file.
		if ($_->{edit_fieldtype} eq 'FILEINPUT') {
			#at the very least we need to know its extension to be able to prepare a link to it.
			my $file_upload_record_classname = 'SpApp::DataObjects::AppFileUpload';
			my $upload_filename = $file_upload_record_classname->new($self->{wa}, { record_id => $_->{edit_value} })->val('upload_filename');
			my $xtn = ($upload_filename =~ /\.(\w+)$/) && $1;
			$_->{xtn} = $xtn;
			$_->{upload_filename} = $upload_filename;
		}
		
	} #end loop over fields.

	#2007 09 11 - experimental multi_lang field labels. doing edit_display_names from interface strings.
		#this may need to be revised if we have issues with paramter_name collisions but I'm suspecting that in all cases the display name for a field with a given parameter name can be the same. (assumptions like this have a way of biting u in the ass however)
	if ($self->{'do'}->form_spec()->{form}->{multi_lang}) {
		my $fldlabel_stringnames = [ map { 'fieldlbl__' . $_->{parameter_name} } grep { $_->{edit_show_field} } @$merged_fields ];
		my $field_labels = $self->{wa}->get_strings($fldlabel_stringnames);
		#now go over the fields and apply the field labels we got for each param ... skip if not edit_show_field or didnt get a field label.
		foreach my $field (@$merged_fields) {
			next if (!$field->{edit_show_field});
			next if (!$field_labels->{'fieldlbl__' . $field->{parameter_name}});

			$field->{edit_display_name} = $field_labels->{'fieldlbl__' . $field->{parameter_name}};
			$field->{multi_lang_labels} = 1; #flag for designed editform controller to know it has to plug in a proper field label from the field edit_display_name
		}
		$self->ch_debug(['_standard_editform_field_postprocessing: multi-lang field labels:', $field_labels, 'for strings named:', $fldlabel_stringnames ]);
	}

	return 1;
}

sub _prepare_captchas {
	my $self = shift;
	my $fields = shift;
	my $other_args = shift;

	#NOTE, as of 2008 11 27 for the CAPTCHA_RECAPTCHA experiment, this func is really going to just generate some html from code that is in the 
	#there is no hit to a 3rd party web server until that html gets rendered by user's browser at which point it will do some JS code to grab images from CMU etc.

	my $captcha_fieldtypes = {
		'CAPTCHA_RECAPTCHA' => 1, #this is the first type of captcha we are ever attempting to use here. It is a web service provided by CMU.
	};
	foreach my $fld (@$fields) {
		if (!$captcha_fieldtypes->{$fld->{edit_fieldtype}}) { next; }
		if ($fld->{edit_fieldtype} eq 'CAPTCHA_RECAPTCHA') {
			my $c = Captcha::reCAPTCHA->new;
			my $ssl = $self->{wa}->env('https') eq 'on' ? 1 : 0;
			my $pubkey = $self->{wa}->config('recaptcha_pubkey');
			#valid field edit_options for this fieldtype are theme and tabindex
			my $options = $fld->{edit_options} ? $fld->{edit_options} : {};
			my $captcha_html = $c->get_html($pubkey, undef, $ssl, $options);
			$self->{wa}->debuglog(['_prepare_captchas: just obtained html for a captcha']);
			$fld->{captcha_html} = $captcha_html;
		}
	}
	
	$self->ch_debug(['_prepare_captchas: here with fields like: ', $fields ]);

	return undef;
}
1;