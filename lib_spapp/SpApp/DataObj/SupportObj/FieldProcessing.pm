package SpApp::DataObj::SupportObj::FieldProcessing;
use base SpApp::DataObj::SupportObj;
use strict;

sub _set_efspec_fieldtype_flags {
	my $self = shift;
	my $ef_spec  = shift;
	my $fieldref = shift;
	my $other_args = shift;
	
	if ($fieldref->{edit_fieldtype} =~ /^TEXTINPUT_RICH/) { $ef_spec->{form}->{editform_has_rte} = 1; }
	if ($fieldref->{edit_fieldtype} =~ /^DATE/)           { $ef_spec->{form}->{editform_has_dateinput} = 1; }
	if ($fieldref->{edit_fieldtype} =~ /^FILEINPUT/ || $fieldref->{edit_fieldtype} =~ /^IMAGEINPUT/) { $ef_spec->{form}->{editform_has_fileinput} = 1; }
	if ($fieldref->{edit_fieldtype} =~ /^COMBO_RADIO_CONTROLLED_FIELD/)                              { $ef_spec->{form}->{editform_has_rcf} = 1; }

	return $fieldref;
}

sub _parameter_to_fieldref {
	my $self = shift;
	my $fieldref = shift;
	my $other_args = shift; #dunno .. more control later.

	#$self->ch_debug(['_parameter_to_fieldref: operating on a fieldref like:', $fieldref]);
	
	if (!$fieldref) {
		$self->error("_parameter_to_fieldref requires a fieldref");
	}
	if (!$fieldref->{parameter_name}) {
		return $fieldref; #nothing to do if no parameter_name ... not sure the field would even be valid .. meh headings etc maybe.
	} else {
		$self->{'do'}->{_fieldrefs}->{$fieldref->{parameter_name}} = $fieldref;
	}
	return $fieldref;
}

sub _complex_custom_field_init {
	my $self = shift;
	my $fieldref = shift; #2007 03 28 - this is a fieldprocessing thing now. but it should 
	my $args = shift;

	#my $fields = $self->form_spec()->{fields};
	#foreach my $fieldref (@$fields) {
	
	#2007 01 30, adding this code to deal with all the setup variables for a custom field type that I'm calling COMBO_RADIO_CONTROLLED_FIELD
	if ($fieldref->{edit_fieldtype} =~ /^COMBO_RADIO_CONTROLLED_FIELD/) {
		#get the options for it. should tell us everything we need to set this thing up.

		#edit options here should be based on something like:
			#{"values_table":"cmcreg_howheard_mediastream", "subfields":{"select":{"values_table":"cmcreg_howheard_mediastream_promotion", "db_field_name":"cmcreg_client_signup.how_heard_mediastream_promotion_id","values_table_fk_field":"mediastream_id","blankitem_label":"Promotion"},"text":{"db_field_name":"cmcreg_client_signup.how_heard_mediastream_freeformtext"}}}
			#explained: values_table is defined for everything that has list values, so the radio button at top level, and the select subfield as well. the db_field_name is coded for each of the subfields so that the thing will know where to save the values.
		#down in _standard_editform_field_postprocessing we will add all the editing options ... but for now I really need to get the subfield infos in there, because I'm going to need that info to build sql and shit.
		my $edit_options = $fieldref->{edit_options};

		#now we will have eo_subfield info in the fieldref. establish the parameter names for the subfields. assuming that was not provided already.
			#add the parameter names to the eo_subfields info too. kinda important for the sql building.
		foreach my $subfield_type (keys(%{$edit_options->{subfields}})) {
			my $subfield = $edit_options->{subfields}->{$subfield_type};
			if (!$subfield->{parameter_name}) {
				$subfield->{parameter_name} = $fieldref->{parameter_name} . '_sub_' . $subfield_type;
			}
		}
		
		#make subfields available at a specific key of the field .. subfields. should work off that for everything else.
		$fieldref->{subfields} = Clone::clone($edit_options->{subfields}); #take as a copy. so we are not modifying the version in the edit_options when we do stuff to them.
	}

	if ($fieldref->{edit_fieldtype} eq 'IMAGEINPUT') {
		#just going to add some keys to the fieldref about image directory and default size tag, (default to disp if not specified)
			#the point of them is to assist in automatically rendering the image inside generic editforms.
		my $image_options = $fieldref->{edit_options}->{image_options};
		$fieldref->{image_directory} = $image_options->{directory};
		$fieldref->{image_default_sizetag} = $image_options->{default_sizetag} ? $image_options->{default_sizetag} : 'disp';
	}

	if ($fieldref->{edit_fieldtype} eq 'FILEINPUT') {
		#some similar stuff to what is done for imageinput. only simpler.
		my $file_options = $fieldref->{edit_options}->{file_options};
		$fieldref->{file_directory} = $file_options->{directory};
	}
	#} #end loop over fields.
		
	#return 1;
	return $fieldref;
}

sub _add_field_properties {
	#edit options are the values coded in the db field "edit_options" as a JSON string. I seem to be using those for general customizations.
		#i broke this out to a new function on 2007 01 31 b/c of the new CMC field thing that needed the options to be applied early. I'm actually thinking now that I'm not sure why I dont always do the options early, other than some fields may be discarded before we get to the _standard_editform_field_postprocessing
		#also, changing this to give a eo_ prefix of all edit_option things. so its clear where they came from. I'm sure that's going to break a lot of stuff right now! oh well. conquer your fears. nobody is running production stuff off the dev libs, right? RIGHT??
	my $self = shift;
	my $fieldref = shift;

	my $args = shift;
	my $property_name = $args->{property};
	if (!$property_name) {
		$self->error('_add_field_properties cannot add properties without a property name');
	}
	
	#so now we should just be adding stuff. and so we should be able to call this again and add more stuff, if, say, we are slapping some more fields in or something.
	my $property_data = undef;
	#$self->ch_debug(['_add_field_properties: for a fieldref like:', $fieldref ]);

	if ($args->{from_json}) {
		$property_data = $self->{'do'}->_json_attribs($fieldref->{$args->{'from_json'}});
		#$self->ch_debug(['here with property data like: ', $property_data, 'for property named', $property_name ]);
	} elsif ($args->{from_key}) {
		$property_data = $fieldref->{$args->{'from_key'}};
	} elsif ($args->{hashref}) {
		$property_data = $args->{'hashref'}; #i think this is unused thus far.
	}
	
	if ($property_data) {
		$fieldref->{$property_name} = $property_data;
		if ($args->{highlevel_prefix}) {
			foreach my $subprop (keys(%$property_data)) {
				#edit options want to have a eo_ prefix at fieldref level, and we can now ask for that.
				$fieldref->{$args->{highlevel_prefix} . '_' . $subprop} = $property_data->{$subprop};
			}
		}
	} else {
		#2007 05 28, started having an issue where this property was an empty string from a db-defined data obj for EDU. Not sure how we never had a problem before, but this should fix it now that we have an issue.
		$fieldref->{$property_name} = {};
	}

	#$self->ch_debug(['field after adding a property based on args', $fieldref, $args]);
	return $fieldref;
}

##### _add_field_properties above should replace both these.
#sub _add_field_edit_options {
#	#edit options are the values coded in the db field "edit_options" as a JSON string. I seem to be using those for general customizations.
#		#i broke this out to a new function on 2007 01 31 b/c of the new CMC field thing that needed the options to be applied early. I'm actually thinking now that I'm not sure why I dont always do the options early, other than some fields may be discarded before we get to the _standard_editform_field_postprocessing
#		#also, changing this to give a eo_ prefix of all edit_option things. so its clear where they came from. I'm sure that's going to break a lot of stuff right now! oh well. conquer your fears. nobody is running production stuff off the dev libs, right? RIGHT??
#	my $self = shift;
#	my $fieldref = shift;
#
#	my $args = shift;
#	
#	#so now we should just be adding stuff. and so we should be able to call this again and add more stuff, if, say, we are slapping some more fields in or something.
#	foreach ('json','hashref','key') {
#		my $edit_options;
#		if ($args->{$_} && $_ eq 'json') {
#			$edit_options = $self->{'do'}->_json_attribs($fieldref->{$args->{'json'}});
#		}
#
#		if ($args->{$_} && $_ eq 'hashref') {
#			$edit_options = $args->{'hashref'};
#		}
#		if ($args->{$_} && $_ eq 'key') {
#			$edit_options = $fieldref->{$args->{'key'}};
#		}
#			
#		foreach my $edit_option (keys(%$edit_options)) {
#			$fieldref->{edit_options}->{$edit_option} = $edit_options->{$edit_option};
#			$fieldref->{'eo_' . $edit_option}         = $edit_options->{$edit_option};
#		}
#	}
#
##	$fieldref->{edit_options_added} = 1; #flag that we've done it so we hopefully dont repeat ourselves.
#	#$self->ch_debug(['field after adding edit_options', $_, 'we have decoded edit options like', $edit_options]);
#	return $fieldref;
#}
#
#sub _add_field_edit_validate_rules {
#	my $self = shift;
#	my $fieldref = shift;
#
#	my $args = shift;
#	
#	#so now we should just be adding stuff. and so we should be able to call this again and add more stuff, if, say, we are slapping some more fields in or something.
#	foreach ('json','hashref','key') {
#		my $validate_rules;
#		if ($args->{$_} && $_ eq 'json') {
#			$validate_rules = $self->{'do'}->_json_attribs($fieldref->{$args->{'json'}});
#		}
#
#		if ($args->{$_} && $_ eq 'hashref') {
#			$validate_rules = $args->{'hashref'};
#		}
#		if ($args->{$_} && $_ eq 'key') {
#			$validate_rules = $fieldref->{$args->{'key'}};
#		}
#			
#		foreach my $rule (keys(%$validate_rules)) {
#			$fieldref->{edit_validate_rules}->{$rule} = $validate_rules->{$rule};
#		}
#	}
#
##	$fieldref->{edit_options_added} = 1; #flag that we've done it so we hopefully dont repeat ourselves.
#	#$self->ch_debug(['field after adding edit_options', $_, 'we have decoded edit options like', $edit_options]);
#	return $fieldref;
#}

#was thinking of doing cgi_value_disp by looking to edit_listoptions and finding a value that matches the cgi_value.
#this is another experiment. It is based on the logic that if we are picking up cgi parameters, we must be submitting some form from an editing mode. IF that is the case, then the fields that are SELECT_ type ones that have listoptions should ALREADY have the listoptions set up.
#in such a case where there are listoptions, and we have a cgi_value, we should be able to go over the listoptions, find the one that matches the cgi_value, and use the display_value for cgi_value_disp.
sub _display_value_from_listoptions {
	my $self = shift;
	my $fieldref = shift;
	my $args = shift;
	
	if (!$args->{inspect}) { $self->error('_display_value_from_listoptions needs to know what to inspect for doing lookup within listoptions.'); }

	my $value_attrib = $args->{inspect} . '_value'; #so, db_value .. or cgi_value .. or whatever.
	my $disp_attrib = $value_attrib . '_disp';
	my $mv_check_attrib = $value_attrib . '__multi_values'; #check for multiple values first.
	my $inspect_values;
	if ($fieldref->{$mv_check_attrib}) {
		#explicit multivalues arrayref has been setup.
		$inspect_values = $fieldref->{$mv_check_attrib};
	} else {
		#some sillyness (think repop_values for a fif and needing an edit_values from db that were the right format) has us with multiselect values loaded from json in db being turned into arrayrefs for edit_value (or so it would seem) so lets fall back to either an existing arrayref in the value_attrib, or an arrayref'ized scalar from the same place.
		$inspect_values = (ref($fieldref->{$value_attrib}) eq 'ARRAY') ? $fieldref->{$value_attrib} : [	$fieldref->{$value_attrib} ]
	}

	if (!defined($fieldref->{$value_attrib}) || !$fieldref->{edit_listoptions}) {
		#if there is no value for the field, or of the field doesnt have listoptions, then the display value(s) have to be the same as the inspect value(s).
		$fieldref->{$disp_attrib} = join(', ', @$inspect_values); #b/c where else could the display values come from!?
	}
	
	#so get the display values. antyhing we can't find will just keep the original inspect value.
	my @display_values = map { 
		my $inspect_value = $_;
		my $display_value = $inspect_value; #something to start with. hopefully will be replaced with a real display value.
		my $matching_listoptions = [ grep {$inspect_value eq $_->{value}} @{$fieldref->{edit_listoptions}} ];
		if ($matching_listoptions->[0]) {
			$display_value = $matching_listoptions->[0]->{display_value};
		}
		
		$display_value; #send it back.
	} @$inspect_values;

	$fieldref->{$disp_attrib} = join(', ', @display_values);

	return 1;
}
	
sub _get_merged_fields_and_subfields {
	my $self = shift;
	my $fields = shift;
	
	#2007 01 31 CMC Combo field thing, we need to loop over fields that include some EXTRA fields which are really subfields.
	my $sub_fields = [];
	foreach my $fld (@$fields) {
		if ($fld->{subfields}) {
			foreach my $subfield_type (keys(%{$fld->{subfields}})) {
				push(@$sub_fields, $fld->{subfields}->{$subfield_type});
			}
		}
	}
	my $sql_fields = [ @$fields, @$sub_fields ]; 

#	my @debug = map { {db_field_name => $_->{db_field_name}, parameter_name => $_->{parameter_name}} } @$sql_fields;
#	$self->ch_debug(['_get_merged_fields_and_subfields: going to work with these fields (just showing db_field_name and paramter_name for now):', @debug]);
	return $sql_fields;
	
#	$self->ch_debug(['_get_merged_fields_and_subfields
#	die "After first call to _get_merged_fields_and_subfields";
}

sub _fields_simple_values {
	my $self = shift;
	my $fields = shift;
	my $other_args = shift;
	
	if (!$other_args->{inspect}) {
		#hrmm ... what should be the default to inspect ... lets die until I can determine a good default.
		$self->error("form_spec_simple_values: need to be told what to inspect - sorry.");
	}
	
	#2007 08 06 this seems idiotic given that this func should return a hashref. just going to send back an empty one henceforth. (I am seeing entire dobj refs being dumped in error output sometimes - fucking lame and non-useful.)
	#return $self if ($self->error()); 
	return {} if ($self->error()); #s.b. less useless than what I'd been doing before.

	my $value_attrib = $other_args->{inspect} . '_value'; #so, db_value .. or cgi_value .. or whatever.
	$self->ch_debug(['_fields_simple_values: with args like:', $other_args ]);
	my $include_fmt = 1; #check for formatted values and include those too. its concievable I might want to turn that off someday.
	my $include_lkp = 1; #check for looked up values and include those too. its concievable I might want to turn that off someday.
	my $simple_values = {};
	#$self->ch_debug(['_fields_simple_values: args, value attrib, and fields for fishing:', $other_args, $value_attrib, $fields ]);
		
	#the point of this func is to go through the fields and pull out values from some specific attribute of each field and just make a nice flat hashref of them for easy doing stuff with.
		#and that _lkp/_fmt shit for finding the display value will only work if we're inspecting db stuff methinks. having weird problems after making a bunch of changes that are related to the way this func works (and not sure how stuff ever worked before doh argh motherfuck!!) .. attmpting fix for other value_attribs that might already have been set up with a _disp value for us to pull.
#	foreach my $field (@$fields) {
#		$simple_values->{$field->{parameter_name}} = $field->{$value_attrib};
#		my $disp_value_from = $value_attrib . '_disp';
#		if (!$field->{$disp_value_from}) {
#			#no _disp already set up for this value_attrib, try to look to _lkp and stuff, though that'll probably only work if we're inspecting at 'db' values.
#			if ($include_lkp && $field->{looked_up}) {
#				#$simple_values->{$field->{parameter_name} . '_lkp'} = $field->{$value_attrib . '_lkp'};
#				$disp_value_from = $value_attrib . '_lkp';
#			}
#			if ($include_fmt && $field->{formatted}) {
#				#$simple_values->{$field->{parameter_name} . '_fmt'} = $field->{$value_attrib . '_fmt'};
#				$disp_value_from = $value_attrib . '_fmt';
#			}
#		}
#		#$self->ch_debug(['_fields_simple_values: parameter_name, value attrib, disp_value_from, field:', $field->{parameter_name}, $value_attrib, $disp_value_from, $field ]);
#		$simple_values->{$field->{parameter_name} . '_disp'} = $field->{$disp_value_from};
#	}

	foreach my $field (@$fields) {
		$simple_values->{$field->{parameter_name}}           = $field->{$value_attrib};
		$simple_values->{$field->{parameter_name} . '_disp'} = $field->{$value_attrib . '_disp'};

		#any weird auto de/re jsonification of multivalues or anything here? or is that already done.

		if ($include_lkp && $field->{looked_up}) {
			$simple_values->{$field->{parameter_name} . '_lkp'} = $field->{'db_value_lkp'}; #the only thing that ever GETS a _lkp is db values.
		}
		if ($include_fmt && $field->{formatted}) {
			$simple_values->{$field->{parameter_name} . '_fmt'} = $field->{$value_attrib . '_fmt'};  #the only thing that ever GETS a _fmt is db values.
		}

		#thinking automatic inclusion of image field image directory info would be handy. - attribute should only exist on IMAGEINPUT fields.
			#but maybe not, maybe its out of scope, maybe templates that want this should have it hardcoded instead. not sure.
#		if ($field->{image_directory}) {
#			$simple_values->{$field->{parameter_name} . '_image_directory'} = $field->{image_directory};
#		}
	}

	#$self->ch_debug(['_fields_simple_values: sending back: ', $simple_values ]);

	return $simple_values;
}

sub _filter_fields {
	my $self = shift;
	my $fields = shift;
	my $other_args = shift;
	
	#my $filtered = $fields; #start with all and strip away.

	#for now I just want one to filter out non edit_show_field ones.
	if ($other_args->{edit_show_field}) {
		@$fields = grep { $_->{edit_show_field} == 1; } @$fields;
	}
	if ($other_args->{search_show_field}) {
		@$fields = grep { $_->{search_show_field} == 1; } @$fields;
	}
	#2008 11 28 - thinking about making it mandatory for search mode that the field have a db_field_name
#but still just thinking about it .... there is search_show_field => 0 .... 
#	if ($other_args->{db_field_name}) {
#		@$fields = grep { $_->{db_field_name}; } @$fields;
#	}
	
	return $fields;
}

sub _image_upload {
	my $self = shift;
	my $field = shift;
	my $args = shift;

	require Image::Magick;
	my $file_param = $field->{parameter_name} . '_imageinput';
	my $image_options = $field->{edit_options}->{image_options};
	
	my $cgi = $self->{wa}->query();
	
	my $filename = FileUpload::Filename->name({ filename  => $cgi->param($file_param) });
	my $file_dir = $self->{wa}->env('document_root') . '/' . $image_options->{directory};
	my $orig_dir = $file_dir . '/original';
	#my $filepath = $file_dir . '/' . $filename;
	my $upload_fh = $cgi->upload($file_param);

	#2009 08 11 moving this code up a bit since some of the code before where this used to be might try to look in these dirs. feels cleaner to have it make sure they are existing up here.
	if (!-d $file_dir) {
		#mkdir $file_dir or die "Failed to create directory $file_dir during image upload";
		my $mkdir_result = mkdir $file_dir;
		if (!$mkdir_result) {
			my $message = undef;
			if (!-e $self->{wa}->env('document_root')) {
				$message = 'well the document root doesnt even exist.';
			} elsif (!-w $self->{wa}->env('document_root')) {
				$message = 'the document root exists, but I cannot write to it';
			}
			die "$message";
		}
	}
	if (!-d $orig_dir) {
		mkdir $orig_dir or die "Failed to create directory $orig_dir during image upload";
	}
	
	#2009 04 15 experiment for updating images instead of always making new ones.
		#grab the claimed image_id from the cgi. should be able to go overwrite something then if we got this and it exists.
		#arguably cgi access should be done only in pickup_cgi_values BUT we're already accessing it here to get a filehandle and if we are gonna stop accessing cgi in here then we can probably move both cgi extractions up out of this module :D
	my $image_id  = $cgi->param($field->{parameter_name}); 

	# get extension, no extension means failure.
	my $extension;
	if($filename =~ /\.(\w+)$/) { 
		$extension = $1; 
	} else { 
		return {}; #fail.
	};
	
	#check extension. bad one means (you guessed it) failure.
	my $valid_extensions = { 'bmp' => 1, 'png' => 1, 'gif' => 1, 'jpg' => 1, 'jpeg' => 1};
	if (!$valid_extensions->{$extension}) {
		return {};
	}

	#upload with a id-based filename.
	#my $foo = SpApp::DataObjects::AppImageUpload->new($self->{wa})->create_table({drop=>1});

	$self->ch_debug(['_image_upload: the field we are working with, and uploading an image for:', $field, 'for claimed image id', $image_id ]);
	#die "in _image_upload before actually doing anything, for claimed image id '$image_id'";
	
	my $image_upload_record_classname = 'SpApp::DataObjects::AppImageUpload';
	
	if ($image_id) {

		#is updating an existing image! woot.
		#to update, we need to know the upload_filename for the extension, so we can go remove 
		my $update_image = $image_upload_record_classname->new($self->{wa}, { record_id => $image_id });
		my $old_upload_filename = $update_image->val('upload_filename');
		if (!$old_upload_filename) {
			die "Error updating image: could not find old upload_filename to extract extension info from for removal of old original image.";
		}
		my $old_xtn = ($old_upload_filename =~ /\.(\w+)$/) && $1;

		#the "original" is the originally uploaded file without type or size conversion, with its upload extension. just renamed for app image id numbering.
		#and the only reason I'm going out of my way to remove it here is that the "original" one is the only one that keeps its very original extension and format and if that extension differes for the newly uploaded version I dont want the old one in a different format still kicking around in the filesystem! all the sizings we take will be converted to jpg and so updating an existing one will just overwrite those sizings with new jpgs.
		my $original_path = $orig_dir . '/' . $image_id . '.' . $old_xtn;
		#die "in _image_upload before actually doing anything, for claimed image id '$image_id' the old xtn is $old_xtn and i think i need to unlink '$original_path' before doing anything else";
		if (-e $original_path) {
			unlink($original_path);
		} else {
			die "Error: could not remove old original image that is being updated. This probably should not be fatal. That image might simply not exist.";
		}
		$update_image->set_edit_values({
			upload_filename => $filename,
			image_dir       => $image_options->{directory}, #i know, we're updating, and the image_dir probably didnt change. But shouldnt hurt to update it anyway.
		})->save();
		$self->ch_debug(['_image_upload: should have just updated the record for image id:', $image_id, 'with new upload_filename of:', $filename ]);

	} else {
		#is a first time upload.
		$image_id = $image_upload_record_classname->new($self->{wa}, { 'new' => { 
			upload_filename => $filename,
			image_dir       => $image_options->{directory},
		}, save => 1 })->record_id();
	}

	my $upload_path = $orig_dir . '/' . $image_id . '.' . $extension;

	#we'll place the upload inside the target image dir, though this one is a temp file.
	open UPLOADFILE, ">$upload_path" or die "couldn't create upload file at '$upload_path'\n";
	while (<$upload_fh>) {
		print UPLOADFILE $_;
	}
	close UPLOADFILE;

	#now go and make the sizes.
	my $image_sizes = $image_options->{sizes}; #should be tag/width pairs.
	if (!$image_sizes->{disp}) { $image_sizes->{disp} = 250; } #a reasonable default display image size.
	if (!$image_sizes->{thumb}) { $image_sizes->{thumb} = 100; } #a reasonable default thumbnail image size. want it to be usable in search results.

	$self->ch_debug(['_image_upload: picked up image sizes as follows: ', $image_sizes]);

	#we will take copies of the image for each of the sizes. A special image size tag 'disp' will have the sized image saved in the root of the img_lib_dir. All others will go into named-by-the-tag subdirs.
	my $first_resizing = 1; #just a flag to let us pull out the image details only once.
	my $image_info = {};
	my $meta_sizes = {
		'original' => 1, #dir for storing the actual original image file, just renamed.
		'orig_size' => 1, #dir for a copy which has been forced into a jpg at the original size.
	};

	#get info from image.
	my $source_image = Image::Magick->new();
	$source_image->Read( $upload_path );
	$image_info->{height}    = $source_image->Get('height');
	$image_info->{width}     = $source_image->Get('width');
	$image_info->{filesize}  = $source_image->Get('filesize');
	$image_info->{format}    = $source_image->Get('format');
	if (!$image_info->{width}) { return {} }; #not sure exactly how to report on the defective image just yet but lets go ahead and stop ourselves from dividing by zero.
	$image_info->{y_to_x}    = $image_info->{height} / $image_info->{width};

	#created original sized jpg version. will recompress.
	my $destdir         = $file_dir . '/orig_size';
	my $orig_size_fname = $image_id . '.jpg';
	my $destpath        = $destdir . '/' . $orig_size_fname;
	if (!-d $destdir) {	mkdir $destdir or die "Could not create dest dir: $destdir";	}
	$source_image->Scale(width => $image_info->{width}, height => $image_info->{height});
	$source_image->Write($destpath);
	$image_info->{orig_size_fname} = $orig_size_fname;
	$image_info->{upload_filename} = $filename;  #2009 01 30 store the original uploaded filename somewhere in memory - writing it to the db up above is good too but I want to be able to access it without having to go to that table.
	$image_info->{upload_ext}      = $extension; #2009 01 30 we havent been giving this back in any useful way up until now
	$image_info->{app_image_id}    = $image_id;  #2009 01 30 we havent been giving this back in any useful way up until now

	foreach my $size_tag (keys(%$image_sizes)) {
		
		next if ($meta_sizes->{$size_tag}); #b/c certain ones are special tag/subdir that we shouldnt mess with.
		
		my $source_image = Image::Magick->new();
		$source_image->Read( $upload_path );

		if ($image_info->{width} < $image_sizes->{$size_tag}) { 
			#if source image is physically narrower than the set display width, then keep preserver width (do _not_ scale image larger)
			$image_info->{$size_tag . '_x'} = $image_info->{width};
			$image_sizes->{$size_tag}       = $image_info->{width};
		} 
		$image_info->{$size_tag . '_y'} = int($image_sizes->{$size_tag} * $image_info->{y_to_x});

		my $dest_ext      = 'jpg'; #make it a jpeg always.
		my $destfilename  = $image_id . '.' . $dest_ext; #so save in a subdir named by the size tag.
		my $destdir       = $file_dir . '/' . $size_tag;
		my $destpath      = $destdir . '/' . $destfilename;

		#all sized images go into subdirs. original images live at the top level.
		#check that target image-tag dir exists ... create it if not.
		if (!-d $destdir) {
			mkdir $destdir or die "Could not create dest dir: $destdir";
		}

		$source_image->Scale(width => $image_sizes->{$size_tag}, height => $image_info->{$size_tag . '_y'});
		$source_image->Write($destpath);
		$self->ch_debug('after scaling for display the image is this wide: ' . $source_image->Get('width') . " ... now about to write it out to $destpath");
	}
	
#	my $debug_info = [
##		"the uploaded image filename was $source_filename", 
##		"the filename part was $filename",
##		"the extension part of that was $extension",
##		"the path we wrote it to was $upload_path",
##		"image info below",
#		$image_info,
#	];
#
#	$self->ch_debug($debug_info);

	#clean up by removing the temp file.
	#unlink ($upload_path);
	my $upload_result = {
		uploaded    => 1,
		image_info  => $image_info,
		image_sizes => $image_sizes,
	};

	return $upload_result;

}	

sub _file_upload {
	my $self = shift;
	my $field = shift;
	my $args = shift;

	my $file_param = $field->{parameter_name} . '_fileinput';
	my $file_options = $field->{edit_options}->{file_options}; 
	
	my $cgi = $self->{wa}->query();
	
	my $filename = FileUpload::Filename->name({ filename  => $cgi->param($file_param) });
	my $file_dir = $self->{wa}->env('document_root') . '/' . $file_options->{directory};
	#my $filepath = $file_dir . '/' . $filename;
	my $upload_fh = $cgi->upload($file_param);

	#make sure directories exist.
	if (!-d $file_dir) {
		#mkdir $file_dir or die "Failed to create directory $file_dir during image upload";
		my $mkdir_result = mkdir $file_dir;
		if (!$mkdir_result) {
			my $message = undef;
			if (!-e $self->{wa}->env('document_root')) {
				$message = 'well the document root doesnt even exist.';
			} elsif (!-w $self->{wa}->env('document_root')) {
				$message = 'the document exists, but I cannot write to it';
			}
			die "$message";
		}
	}
	
	#if its already been uploaded before we might be updating some known file id. take note of it.
	my $file_id  = $cgi->param($field->{parameter_name}); 

	# get extension, no extension means failure. (actually not sure this matters on file upload, might lose that restriction at some point, of course it is nice to be able to classify things with it.)
	my $extension;
	if($filename =~ /\.(\w+)$/) { 
		$extension = $1; 
	} else { 
		return {}; #fail.
	};
	
	#dont bother to check extension since it can be any file type really.

	$self->ch_debug(['_file_upload: the field we are working with, and uploading a file for:', $field, 'for claimed image id', $file_id ]);
	#die "in _image_upload before actually doing anything, for claimed image id '$image_id'";
	
	my $file_upload_record_classname = 'SpApp::DataObjects::AppFileUpload';
	
	if ($file_id) {

		#is updating an existing file! woot.
		#to update, we need to know the upload_filename for the extension, so we can go remove 
		my $update_file = $file_upload_record_classname->new($self->{wa}, { record_id => $file_id });
		my $old_upload_filename = $update_file->val('upload_filename');
		if (!$old_upload_filename) {
			die "Error updating file: could not find old upload_filename to extract extension info from for removal of old original file.";
		}
		my $old_xtn = ($old_upload_filename =~ /\.(\w+)$/) && $1;
		#and the only reason I'm going out of my way to remove it here is that the "original" one is the only one that keeps its very original extension and format and if that extension differes for the newly uploaded version I dont want the old one in a different format still kicking around in the filesystem! all the sizings we take will be converted to jpg and so updating an existing one will just overwrite those sizings with new jpgs.
		my $original_path = $file_dir . '/' . $file_id . '.' . $old_xtn;
		#die "in _image_upload before actually doing anything, for claimed image id '$image_id' the old xtn is $old_xtn and i think i need to unlink '$original_path' before doing anything else";
		if (-e $original_path) {
			unlink($original_path);
		} else {
			die "Error: could not remove old original file that is being updated. This probably should not be fatal. That file might simply not exist.";
		}
		$update_file->set_edit_values({
			upload_filename => $filename,
			file_dir        => $file_options->{directory}, #i know, we're updating, and the image_dir probably didnt change. But shouldnt hurt to update it anyway.
		})->save();
		$self->ch_debug(['_file_upload: should have just updated the record for file id:', $file_id, 'with new upload_filename of:', $filename ]);

	} else {
		#is a first time upload.
		$file_id = $file_upload_record_classname->new($self->{wa}, { 'new' => { 
			upload_filename => $filename,
			file_dir        => $file_options->{directory},
		}, save => 1 })->record_id();
	}
	
	my $upload_path = $file_dir . '/' . $file_id . '.' . $extension;

	#we'll place the upload inside the target image dir, though this one is a temp file.
	open UPLOADFILE, ">$upload_path" or die "couldn't create upload file at '$upload_path'\n";
	while (<$upload_fh>) {
		print UPLOADFILE $_;
	}
	close UPLOADFILE;

	my $file_info = {};
	$file_info->{filesize}  = -s $upload_path;
	#$file_info->{format}    = '???';
	$file_info->{upload_filename} = $filename;  #2009 01 30 store the original uploaded filename somewhere in memory - writing it to the db up above is good too but I want to be able to access it without having to go to that table.
	$file_info->{upload_ext}      = $extension; #2009 01 30 we havent been giving this back in any useful way up until now
	$file_info->{app_file_id}     = $file_id;  #2009 01 30 we havent been giving this back in any useful way up until now

	my $upload_result = {
		uploaded   => 1,
		file_info  => $file_info,
	};
	return $upload_result;
}	

1;