package SpApp::DataObj;
use strict;

#use Object::Destroyer;
use Scalar::Util qw(weaken);
use Data::Dumper;

use SpApp::DataObj::SupportObj::EditMode;
use SpApp::DataObj::SupportObj::EditModeInternals;
use SpApp::DataObj::SupportObj::SearchMode;
use SpApp::DataObj::SupportObj::SQLAbstraction;
use SpApp::DataObj::SupportObj::FieldProcessing;
use SpApp::DataObj::SupportObj::Listoptions;

### public access stuff. ####
# constructor
sub new {
	my $invocant = shift;
	my $class    = ref($invocant) || $invocant;  # Object or class name
	my $self = {};
	bless $self, $class;

#	if (ref($self) eq 'LBG::DataObj::Company') {
#		die "here with a " . ref($self);
#	}

	my $web_app = shift; #needed for access to dbh, query, session, etc.
	my $other_args = shift;

	$self->{_ERROR_COND} = undef;	#set up for error method. why here? dunno.
	if (!$web_app) {
		$self->error('new needs a webapp.');
	}
	$self->{wa} = $web_app; #or equivalent.
	weaken($self->{wa}); #2011 01 13 attempt to resolve memory leak (part 1 of 3);

	#just for debug, and track attrib sources, lets turn it off if we're not in debug mode (since nobody will be looking anyways!)
	if ($self->{wa}->param('debug_mode')) {
		$self->{_TRACK_ATTRIB_SOURCES} = 1; #keep this as 1 to see the attrib source cascade nastiness (coolness?) in debug mode.
		#print STDERR "DataObj: debug on -- will track attribute sources \n";
	} else {
		$self->{_TRACK_ATTRIB_SOURCES} = 0;
		#print STDERR "DataObj: not going to track attribute sources \n";
	}

	#Set up support objects. These are all being broken out primarily for managablility. Hopefully it works out.
	my $objrefs = $self->_load_support_obj($other_args); #instantiate them all.
	$self->_init_support_obj($objrefs, $other_args); #make them all know about each other (or most of them anyway, will do _init_custom in some of them maybe to
	$self->{_support_objrefs} = $objrefs;

#	$self->{wa}->debuglog(['dataobj: pre-initialize']);
	$self->_initialize($other_args);
#	$self->{wa}->debuglog(['dataobj: post-initialize']);

	#my $wrapper = Object::Destroyer->new( $self, '_dereference' );
  #return $wrapper;

	return $self;
}

sub _load_support_obj {
	my $self = shift;
	my $data_obj_constructor_args = shift; #s.b. just a ref to whatever $other_args was obtained in DataObj::new().

	my $support_obj_prefix = 'SpApp::DataObj::SupportObj';
	my $support_obj = {
		em  => 'EditMode',
#		emi => 'EditModeInternals',
		sm  => 'SearchMode',
		sa  => 'SQLAbstraction',
		fp  => 'FieldProcessing',
		lo  => 'Listoptions',
	};
	my $objrefs = {};
	#loop once to instantiate all of them and
	foreach (keys(%$support_obj)) {
		my $objref = ($support_obj_prefix . '::' . $support_obj->{$_})->new($self, $data_obj_constructor_args);
		$self->{$_} = $objref;
		$objrefs->{$_} = $objref;
	}
	#$self->{_support_objrefs} = $objrefs;
	return $objrefs;
}

sub _dereference {
	my $self = shift;

	my $ref_names = [ qw{ do em	emi sm sa fp lo	wa} ]; #note emi is internal to em but that doesnt really matter too much for what we want to try and do here. (kill references). also note wa thrown in there to remove from everything.

	my $objrefs = $self->{_support_objrefs};
	$objrefs->{emi} = $objrefs->{em}->{emi}; #b/c it wouldnt be readily available otherwise. emi only existed inside em. but it has references to everything too.

	foreach (@$ref_names) {
		if ($objrefs->{$_}) {
			my $objref = $objrefs->{$_}; #for scoping $_ shit.
			#kill all references to this and other support objects in the support object.
			foreach my $refname (@$ref_names) {
				$objref->{$refname} = undef;
			}
		}
		#kill our reference to shit as well.
		$self->{$_} = undef;
	}
	$self->{_support_objrefs} = undef;
	%$self = (); #from Object::Destroyer. looks nice. kill in faceyish.
	#did calling this in DESTROY accomplish anything? who knows! lets find out. maybe memory will stop going up up up up up.
	#die "lol, well this happend";

	return 1;
}

sub _init_support_obj {
	my $self = shift;
	my $objrefs = shift;
	my $data_obj_constructor_args = shift; #s.b. just a ref to whatever $other_args was obtained in DataObj::new().

	#my $objrefs = $self->{_support_objrefs};
	#loop again to once to give each one all the object refs now that they all exist.
	foreach (keys(%$objrefs)) {
		$objrefs->{$_}->_standard_init($objrefs, { dont_ref => { $_ => 1 } }, $data_obj_constructor_args); #dont_ref will not make an internal reference to the one with that key, which is the one we are setting up now. If we just did all of them then each one would end up with a circular reference to itself and to me that is just messy and potentially bad/dangerous.
	}
}

sub _augment_editmode_values {
	my $self = shift;
	my $args = shift;

	my $fields = $args->{fields};
	my $target = $args->{target}; #usually 'db'. cuz we want to fix up db_values before we go off copying them to edit_values to show stuff to the user.
	#this func allows us a chance to, when we are editing some existing record (we should have a record id to be here, and we should have ALREADY loaded db_values into the fields when we are here, as this should only be called from get_editform in the section where we've $obtained_record, anyways this gives us a chance to override the loaded db_values from somewhere else, or even set them entirely from scratch if there is no db_field_name associated with some bullshit field that doesnt really exist in the db. (IDL 2 db flags from 1 unbound cbox)
	#but we dont do anything in this default definition of the function. subclass should override if there is something to do.
	#IT MUST BE OVERRRIDDEN IN SUBCLASS TO USE IT
	return undef;
}

sub _augment_searchmode_values {
	my $self = shift;
	my $args = shift;

	my $select_result = $args->{select_result};
	#lets us use a custom dobj function (that overrides this dummy one) to do stuff to the results.
	#IT MUST BE OVERRRIDDEN IN SUBCLASS TO USE IT
	return undef;
}

sub error {
	my $self = shift;
	my $value = shift;
	my $args = shift; #maybe we want non-fatal errors or a better way to control i dunno.

	###NOTE TO SELF::: I've sort of come to depend on this die'ing. in a lot of places, this should really always die. I may have to audit one day and pass more args to this like fatal and nonfatal errors and shit like that. meh.

	if ($value) {
		$self->{_ERROR_COND} = $value;
		unless($args->{nonfatal}) {
			die "DataObj Error: $value" . Dumper($args);
		}
		#die "Self destructing on data object error - doing this b/c I am often finding myself not realizing an error condition happened";
	} else {
		return $self->{_ERROR_COND};
	}
}

sub clear_error() {
	#adding this 2008 07 14 b/c when dobj used with find_record_for_edit in loops it was having an error condition persist past the first failure and subsequent lookups were getting stuck with old record values due to the erorr condition being present and causing _standard_editform_field_postprocessing (i think that wsat he one) from executing. gonna call this now in some places where it might make sense.
	my $self = shift;
	$self->{_ERROR_COND} = undef;
}

sub ch_debug {
	my $self = shift;
	my $var = shift;
	return $self->{wa}->ch_debug($var);
}

## public methods ##
	## i think a good general idea is to return the object ref in most cases. private  methods that do this now might not really be needing to do that, but by-and-large I think public methods probably should. allows the chaining stuff.
sub initialized() {
	my $self = shift;
	return $self->{_INITIALIZED};
}

sub form_name {
	my $self = shift;
	my $form_name = shift;

	#getter/setter for form_name
	if ($form_name) {
		$self->{form_name} = $form_name;
		return $self;
	} else {
		return $self->{form_name};
	}
}

#just for even MORE convenience.
sub id {
	my $self = shift;
	return $self->record_id(@_);
}

sub record_id {
	my $self = shift;
	my $record_id = shift;

	#getter/setter for record_id
	if ($record_id) {
		$self->{record_id} = $record_id;
		return $self;
	} else {
		return $self->{record_id};
	}
}

sub clear_record_id {
	my $self = shift;
	$self->{record_id} = undef;

	#this should also attempt to discover the pk field amongst the form_spec fields list and clear any edit_value out of that field as well.
		#because for 2007 08 22 when I want to clear_record_id off a object that has field 'id' in its field list, the save operation code is still going to use the edit_value on that field. well, hopefully no longer.
	my $form_spec = $self->form_spec();
	my $pk_field = $form_spec->{form}->{pk_field};
	my $pk_in_fieldlist = [ grep { $_->{db_field_name} eq $pk_field } @{$form_spec->{fields}} ];
	foreach (@$pk_in_fieldlist) {
		$_->{edit_value} = undef;
		#$self->ch_debug(['clear_record_id: fingers crossed']);
	}

	return $self; #for chaining operations.
}

sub form_spec {
	my $self = shift;
	my $form_spec = shift;
	#getter/setter for generalized form_spec.
	if ($form_spec) {
		#set it
		$self->{form_spec} = $form_spec;
		# soo if the form_spec was just changed is there anything we need to do? do we need to re-initialize or antyhing?
	} else {
		#get it
		return $self->{form_spec};
	}
}

###SEARCH MODE
sub searchform_spec {
	my $self = shift;
	return $self->{sm}->searchform_spec(@_);
}

sub get_search_results {
	my $self = shift;
	return $self->{sm}->get_search_results(@_);
}

sub paginate_search_results {
	my $self = shift;
	return $self->{sm}->paginate_search_results(@_);
}

###EDIT MODE
sub editform_spec {
	my $self = shift;
	return $self->{em}->editform_spec(@_);
}

sub get_editform {
	my $self = shift;
	return $self->{em}->get_editform(@_);
}

sub process_form_submission {
	my $self = shift;
	return $self->{em}->process_form_submission(@_);
}

sub pickup_and_sessionize_cgi_values {
	my $self = shift;
	return $self->{em}->pickup_and_sessionize_cgi_values(@_);
}

sub delete_record {
	my $self = shift;
	return $self->{em}->delete_record(@_);
}

sub get_edit_errors {
	my $self = shift;
	return $self->{em}->get_edit_errors(@_);
}

#Edit mode record access:
sub find_record_for_edit {
	my $self = shift;
	return $self->{em}->find_record_for_edit(@_);
}
sub find { #same shit shorter pile
	my $self = shift;
	return $self->{em}->find_record_for_edit(@_);
}

sub load_record_for_edit {
	my $self = shift;
	return $self->{em}->load_record_for_edit(@_);
}
sub load { #super short-fast-call version. and i mean, what else are we loading.
	my $self = shift;
	my $record_id = shift;
	return $self->{em}->load_record_for_edit({ record_id => $record_id });
}

sub new_record_for_edit {
	my $self = shift;
	return $self->{em}->new_record_for_edit(@_);
}
sub newrec { #shorter.
	my $self = shift;
	return $self->{em}->new_record_for_edit(@_);
}

sub save_edited_record {
	my $self = shift;
	return $self->{em}->save_edited_record(@_);
}
sub save { #same thing, shorter name. honestly "save_edited_record" is getting a bit tedious! (like, what else are we saving)
	my $self = shift;
	return $self->{em}->save_edited_record(@_);
}

#Editmode "values"
sub set_edit_values {
	my $self = shift;
	return $self->{em}->set_edit_values(@_);
}

sub set_values {
	my $self = shift;
	return $self->{em}->set_values(@_);
}

sub set_values_from_similar {
	my $self = shift;
	return $self->{em}->set_values_from_similar(@_);
}

sub get_allvals {
	my $self = shift;
#wtf how did this line get like this ?!?? how come i never had a problem until now !?!?
#	return $self->{em}->get_edit_values(@_);
	return $self->{em}->get_allvals(@_);
}

sub val {
	my $self = shift;
	return $self->{em}->get_set_value(@_);
}

sub get_edit_values {
	my $self = shift;
	return $self->{em}->get_edit_values(@_);
}

sub get_edit_display_values {
	my $self = shift;
	return $self->{em}->get_edit_display_values(@_);
}

sub get_values {
	my $self = shift;
	return $self->{em}->get_values(@_);
}

sub get_display_values {
	my $self = shift;
	#this is to do the same thing that get_edit_display_values does, except its for when you need to specify the 'inspect' b/c its not 'edit'. and you have to specify it.
	return $self->{em}->get_display_values(@_);
}

## db focussed 2007 03 shit
sub create_table {
	my $self = shift;
	my @ct_args = @_;

	$self->{sa}->_create_table(@ct_args);

	return $self;
}

sub empty_table {
	my $self = shift;
	my @ct_args = @_;
	my $form_spec = $self->form_spec();
	$self->{sa}->_empty_table($form_spec, @ct_args);
	return $self;
}

## 2007 04 03 giving public access to validate_field_values.
sub validate_field_values {
	my $self = shift;
	return $self->_validate_field_values(@_);
}

sub fieldref {
	my $self = shift;
	my $param = shift;
	if (!$param) { return $self->{_fieldrefs}; } #send them all back if a particular one was not asked for.
	return $self->{_fieldrefs}->{$param};
}

#################################
#### Internal object funcs ######
#################################

#have to override these in the base class and return the data structures that _init_form_spec will want if you want to use the _init_form_spec powers.
sub _init_fields { return undef; }
sub _init_form   { return undef; }
sub _field_listoptions { return {}; } #should return a hashref of param => sub_ref. each sub_ref should return an arrayref filled with hashes like {display_value => 'Kandahar', value => 235}

#Once it is initialized we should be able to use it to get the record data, save records, get a search list, etc.
sub _initialize {
	my $self = shift;
	my $args = shift; #should have a form_name and probably a record_id in here.

	$self->param(%{$args->{params}});
	$self->record_id($args->{record_id});

	#I want to be able to distinguish between a "formcontrol_db" and a "data_db" ...
	# - formcontrol_db would be where form and field definitions, dropdown list options (for alo table listoptions only!) would come from.
	# - data_db would be where row data would come from or be saved to.
	#We should set default values for these if they are not passed in. The default must be the db_name specified in the application config.
	$self->{_formcontrol_db} = $args->{formcontrol_db} ? $args->{formcontrol_db} : $self->{wa}->config('db_name');
	$self->{_data_db}        = $args->{data_db}        ? $args->{data_db}        : $self->{wa}->config('db_name');

	#build a form spec on field specifications from the db or from a data structure.
	my $form_spec = $self->_init_form_spec($args); #pass args onwards.
	my $form = $form_spec->{form};
	#if we get a form name out of init_form spec, then we should look to args for one. and bail if we dont get a form name from there either. we need a form name. it can be wahtever. same name as perl class why not if not doing db based fieldspec stuff.
	if (!$form->{name}) {
		if (!$args->{form_name}) {
			$self->error("initialize needs a form name.");
		}
		$form->{name} = $args->{form_name};
	}

	#SOOO .. we have a form name or we've bailed by now.

	#we also might be fully specced out. but there also might be db based info to add!. lets go with the notion that anything that comes out of the db will override anything that is already set up, UNLESS a no_override param is passed or something like that.
	#lets get any db based stuff, unless of course we're told not to.
	unless ($form->{no_db_form_spec}) {
		##building the form spec means quite a bit of db centric work ... i think i really dont want to do that until neccessary, especially since I can work with fields that come out of the session a lot.
			#but without that ... what does initialized really mean? just that we have a form name set, and possibly also a record id set. hrm.
			#on second thought, I _need_ to have the form part of the form_spec. I think I want to always do that. And the fields, well, not doing them will just complicate things. so I guess I'll suffer the performance hit to have them be there always.
		my $build_args = { form_spec => $form_spec };
		if ($args->{keep_commented_out_fields}) { $build_args->{keep_commented_out_fields} = 1; }
		if ($args->{no_override})               { $build_args->{no_override} = 1; }
		if ($args->{track_attrib_sources})      {	$self->{_TRACK_ATTRIB_SOURCES} = 1;	} #probably should lose this... but it was meant for debug in event of deeply relying on that field value overriding and inheritance stuff with db fields, should it ever go awry. #oh wait i think formtool uses this info too.
		#$self->ch_debug(['_initialize: going to build a form spec with these args: ', $build_args]);
		$form_spec = $self->_build_form_spec($build_args);
	}

	#2007 02 06 -- adding a hook to be able to do _inject_edit_fields as well. Primarily this is because I really dont want to piggy back a new bloody form on top of the base one that the client fills in just to get an extra db field to be selected and given back when I'm using the thing internally.
	if ($args->{init_inject_fields}) {
		#NOT sure that this usage is really acceptable. other usages seem to do things in a way that the injected fields won't stay in the session. not sure that it matters. i am scared that I'm going to start confusing myself with all the hooks and ways of adding shit. conquer your fears. conquer!
		$self->{em}->{emi}->_inject_edit_fields({ form_spec => $form_spec, inject_fields => $args->{init_inject_fields} });
	}

	####At this point we should have the complete set of fields for operating post initialize. It is now time to do additional processing to ALL the fields we have.
		#this same processing is (generally) duplicated over in emi->_save_operation_field_injection
	foreach my $field_ref (@{$form_spec->{fields}}) {
		$self->{fp}->_complex_custom_field_init($field_ref);
	}
	#merge with subfields and do operations that have to happen on every. single. field. subfield or not.
	my $merged_updated_fields = $self->{fp}->_get_merged_fields_and_subfields($form_spec->{fields}); #get merged with subfields in case we added any fields that have subfields.
	#$self->ch_debug(['merged fields in _initialize: ', $merged_updated_fields]);
	foreach my $field_ref (@$merged_updated_fields) {
		$self->{fp}->_set_efspec_fieldtype_flags($form_spec, $field_ref);
		$self->{fp}->_parameter_to_fieldref($field_ref);
	}

	#set the form spec now. finally. after _everything_ has been processed, processed again, then processed some more. ahhh the processing.
	$self->form_spec($form_spec);
	#$self->ch_debug(['_initialize: form spec shaped up like: ', $form_spec]);

	##experimental 2007 03 24 .... if we have a record_id ..... load the record. (we might have got and set a record_id by args above.)
		#so do it for record_id or find or new args. leave it alone otherwise.
		#can now do App::DataObj::TableObj->new({ new => { foo => 'foofield_value', bar => 'barfield_value' }, save => 1}); and that will create a record.
		#can now do App::DataObj::TableObj->new({ find => { foo => 'foofield_value', bar => 'barfield_value' }, or_new => 1}); and that will find us up a object with those values. ... pass or_new as well to pass that on. and you still have to save manually.
		#can now do App::DataObj::TableObj->new({ record_id => 'foo' }); and that load up that record.
	if ($self->record_id()) {
		$self->load_record_for_edit();
	} elsif ($args->{find}) {
		#bwuauahahahah of find one by criteriams maybe
		my $find_args = {criteria => $args->{find}};
		if ($args->{or_new}) {
			$find_args->{or_new} = 1;
		}
		$self->find_record_for_edit($find_args);
	}	elsif (exists($args->{'new'})) {
		#and if asking for a new one we can set it up with the chosenered values. also we can just make a new one with no values by doing { new => undef } since we only set up the values if the value for new is a hashref.
		$self->new_record_for_edit();
		if (ref($args->{'new'}) eq 'HASH') {
			$self->set_edit_values($args->{'new'});
		}
		#and if they want to just save it, sure why the f not.
		if ($args->{save}) {
			$self->save_edited_record();
		}
	}

	#should we generate the SQL here too? searchform or editform version? or both? or whichever told to? do we save it in the object? if we do that then maybe we dont have to generate it again for getting search results and editforms eh.?
	$self->{_INITIALIZED} = 1;
}

#init a data object with just these fields.
#yet another way to slap some fields in.
#if we want to expand on an existing form that is defined in the db, then we should NOT be using this, and should be doing the regular initialization but with enhancements to the _inject_edit_fields code to accommodate more fuller field definitions and maybe not turning some things on that are defaulting on in that one.
sub _init_form_spec {
	my $self = shift;
	my $args = shift;

	my $init_fields = $self->_init_fields($args);
	my $init_form   = $self->_init_form($args);
#	if (!$init_fields || !$init_form) {
#		return undef; #just bail if we didnt get both. and we _WONT_ get them if the data object was not specifically set up to do this stuff by being a subclass with overridden _init_fields and _init_form (and maybe other) methods.
#	}
	if (!$init_form) {
		return { form => {}, fields => [] }; #just bail with a blank form_spec if we didnt get $init_form, b/c then theres really nothing to do. if we dont get init_fields thats ok, b/c we'll still do form stuff and return a form_spec.
	}

#	if (ref($init_fields) ne 'ARRAY') {
	if ($init_fields && ref($init_fields) ne 'ARRAY') {
		$self->error('_add_init_fields: data obtained from $self->_init_fields must be an arrayref of of fields hashrefs.');
	}
	if (ref($init_form) ne 'HASH') {
		$self->error('_add_init_fields: data obtained from $self->_init_form must be a hashref.');
	}
	if (!$init_form->{name}) {
		$self->error('_add_init_fields: data obtained from $self->_init_form must include a "name" key.');
	}

	my ($form, $fields) = ({}, []);
	my ($sql_query_order, $edit_display_order, $search_display_order) = (0, 0, 0);
	$form->{name}             = $init_form->{name}; #we can guess at this if it isnt provided.
	$form->{base_table}       = $init_form->{base_table}; #we can guess at this if it isnt provided.
	$form->{default_sort}     = $init_form->{default_sort}; #goddam it, I thought I took care of carrying this forward already. (well fuck, FINALLY is now!)
	$form->{no_db_form_spec}  = $init_form->{no_db_form_spec}; #2007 07 13 - bloody hell. without carrying this forward until now, we've been hitting the db on every dobj request even for those explicitly marked no_db_form_spec. fucking WOOOPSIE. Why again am I not just USING the init_form hashref????? why am I rebuilding it????
	$form->{multi_lang}       = $init_form->{multi_lang}; #2007 09 12 - MOTHERFUCKER. HAVE TO FUCKING REMEMBER TO CARRY SHIT FORWARD!!!!!
	$form->{skip_meta_fields} = $init_form->{skip_meta_fields};

	#so here is where i want to basically be able to handle the setup of the form spec in whatever weird ways I want for whatever weird conveniences I feel that I want.
	foreach my $fieldref (@$init_fields) {
		my $param = $fieldref->{parameter_name};
		my $db_field = $fieldref->{db_field_name};

		if (!$param && $db_field) {
			#so we were told db_field_name but NOT a param name .. thats ok, we can make up a param name then.
			if ($init_form->{fieldname_part_params}) {
				my ($tablepart, $fieldpart) = $db_field =~ /(.*)\.(.*)/;
				$param = $fieldpart; #god help us if one duplicates. well we could always manually specify it.
			} else {
				$param = $db_field;
				$param =~ s|\.|_|g;
			}
			$fieldref->{parameter_name} = $param;
		}

		#but if we still dont have a parameter name we cannot keep the field because all fields must have a parameter name.
		if (!$param) { next; }
		if (!$form->{base_table} && $db_field =~ /^(\S*)\.(\S*)$/) {
			$form->{base_table} = $1; #establish if it wasnt and we can.
		}

		###field ordering .. update our running numbers if something was provided, else add 10 to it and assign it.
		#query
		if ($fieldref->{sql_query_order}) {
			$sql_query_order = $fieldref->{sql_query_order};
		} else {
			$fieldref->{sql_query_order} = ($sql_query_order += 10);
		}
		#edit_display
		if ($fieldref->{edit_display_order}) {
			$edit_display_order = $fieldref->{edit_display_order};
		} else {
			$fieldref->{edit_display_order} = ($edit_display_order += 10);
		}
		#search_display
		if ($fieldref->{search_display_order}) {
			$search_display_order = $fieldref->{search_display_order};
		} else {
			$fieldref->{search_display_order} = ($search_display_order += 10);
		}

		#establish some defaults if they werent provided.
		if (!$fieldref->{edit_fieldtype}) { $fieldref->{edit_fieldtype} = 'TEXTINPUT_PLAIN'; }
		if (!exists($fieldref->{search_show_field})) { $fieldref->{search_show_field} = 1; }
		if (!exists($fieldref->{edit_show_field}))   { $fieldref->{edit_show_field}   = 1; }

		#defaults for display names if not provided: (same 'algorithm' (lol) as FormTool::Admin::guess_field_definition
		if (!exists($fieldref->{edit_display_name}) || !exists($fieldref->{search_display_name})) {
			my $display_name = $fieldref->{parameter_name};
			$display_name =~ s|_| |g;
			$display_name =~ s/\b(\w)/\u$1/g; #title case. k++ to vladimir-ga for his post 10 Jul 2005 13:53 PDT http://answers.google.com/answers/threadview?id=541585
			if (!exists($fieldref->{edit_display_name})) {
				$fieldref->{edit_display_name} = $display_name;
			}
			if (!exists($fieldref->{search_display_name})) {
				$fieldref->{search_display_name} = $display_name;
			}
		}

		#edit options high level prefixes (like what we do with _add_field_properties for them with db-based formfields)
		foreach (keys(%{$fieldref->{edit_options}})) {
			$fieldref->{'eo_' . $_} = $fieldref->{edit_options}->{$_};
		}

		#what else?

		push(@$fields, $fieldref);
	}

	#line below is copied from elsewhere ... note we dont actually make use of base_table_pk_field right now.
	$form->{pk_field} =  $form->{base_table} . ($init_form->{base_table_pk_field} ? '.' . $init_form->{base_table_pk_field} : '.id'); #use base_table_pk_field as the pk field, or id if its not specified.

	return { form => $form, fields => $fields }; #thats a form_spec.
}

#get the form spec.
sub _build_form_spec {
	my $self = shift;
	my $args = shift; #for some control.

	#whatever form_spec we get in here will have a form_name. if we didnt have a form name we would have bailed in new().
	my $form_spec = $args->{form_spec};
	if (!$form_spec) {
#		$self->ch_debug(['bailing with no formspec at all:', $form_spec]);
		$self->error('get_form_spec requires a form spec to start with -- object probably wanst initialized properly.');
	}

	my $form      = $form_spec->{form};
	my $form_name = $form->{name};
	my $override  = $args->{no_override} ? 0 : 1; #default to overridding attribs unless told not to.

	my @form_ids  = ();
	my $form_ids = {}; #just to track form names for convenience ... id => name

	#lots of rules:
		#first get the base form id. we do things by name here for the sake of the tool that I havent made yet.
		#get the form_spec fields from app_form. if its based on another form, keep doing it until all of them have been gone through and we have reached the form not based on another.
		#we really care about the fields of the forms in the reverse order that the forms are discovered ... ie, form 3 baesd on form 1, form 1 version of same field in form 3 takes precedence.
#	my $dbh = $self->get_dbh();
	my $dbh = $self->_get_formcontrol_dbh();
	my $sql = 'SELECT id FROM app_form WHERE name = ?';
	my $form_row = $dbh->selectrow_hashref($sql, undef, $form_name) or die $dbh->errstr;
	my $id = $form_row->{id};
	my $start_form_id = $id; #and we work from this one to the base one. for tracking base forms, we must not include this one though.
	$form->{attrib_sources} = {}; #for later tool development (and I bet it'll help in debugging too) I'd like to know which form each attribute we settle with comes from.
	$form->{base_forms} = [];
#	if (!$id) { $self->error("_build_form_spec: could not obtain a form id based on form named $form_name ... dying in place of better error handling"); }
	if (!$id) {
		#hrm, if we couldnt find it in the db, that should be ok. we can just bail with whatever we were given already for a form spec.
#		$self->ch_debug(['bailing with a formspec like:', $form_spec]);
		return $form_spec;
	}

	$self->ch_debug(['get_form_spec: the id of which was determined to be', $id]);
  #get attributes of all the forms we have to deal with to construct this one, and store them apropriately.
 	#note in terms of override it is already set to not override, so anything passed in through the form_spec form will remain in place.

  $sql = 'SELECT * FROM app_form WHERE id = ?';
	my $sth = $dbh->prepare($sql);
	my $reached_base = 0;
	while (!$reached_base) {
		$sth->execute($id);
		my $row = $sth->fetchrow_hashref();

		#$self->ch_debug(["get_form_spec: so I'm looking for parent forms. and while I was at it I got these attribs for form id $id", $row]);

		#put this form into the beginning of the list of forms to look at. (that way the base form will end up as the first one in the list)
		unshift(@form_ids, $id);
		if ($id != $start_form_id) {
			unshift(@{$form->{base_forms}}, $row->{name});
		}

		#also we will set the form_spec in these iterations ... attributes that are not nulls should be set in the form_spec.
		foreach (keys(%$row)) {
			#if its not already defined in the form spec so far and is defined in the row we just got, set it in the form spec. this way we are keeping attributes of the derived forms we start our form search with, and not applying attribs from parent forms that have been overridded by derived forms.
			if (!defined($form->{$_}) && defined($row->{$_})) {
#				$self->ch_debug(["building form spec, setting attrib $_ from form named $row->{name}"]);
				$form->{$_} = $row->{$_};
				if ($self->{_TRACK_ATTRIB_SOURCES}) {
					$form->{attrib_sources}->{$_} = $row->{name};
				}
			}
		}

		$form_ids->{$id} = $row->{name}; #most for attrib_sources and debug help.

		if (!$row->{base_form_id}) {
			#we've reached the base form. we're done
			$reached_base = 1;
		} else {
			#we have not reached the base form, set the id for next iteration to tbe base_form_id just encountered.
			$id = $row->{base_form_id};
		}

	}

	if ($override) {
		$form->{pk_field} = $form->{base_table} . ($form->{base_table_pk_field} ? $form->{base_table_pk_field} : '.id'); #use base_table_pk_field as the pk field, or id if its not specified.
	}

	#get the fields from those forms.
	#At this point we'll have a list of forms to get fields for.
		#we need to get the list of field ids from each of those in turn.
		#we should track field ids we've discovered as we obtain those base field specs so as to do it only once for each field.
		#any attributes speficied in the form_field entries will override base attributes discovered from the base field spec.
		#and we'll loop over them in the order from base -> derived so that the attribute overrides are easy.

	my $fields = {}; #track fields discovered to do it only once per. start with field_id => { base_field_spec } #end up with field_id => { completed_field_spec }.

	#so get all the fields ids that we'll need to look further into.
		#honestly, not sure what order the fields should be in at this point. Probably going to do a codewise sort based on the eventual use (I have search_display_order and edit_display_order attribs but I think maybe I'll need a sql_field_order or something for db operations (which would override other _order fields if present maybe? I dunno yet).
	my $frmflds_sql = 'SELECT * FROM app_form_field WHERE form_id = ?'; #get all attribs from the fields specified for the forms. We'll use this to get all our base field ids, and to get all our override properties we will use later to ... override.
	my $frmflds_sth = $dbh->prepare($frmflds_sql);

	my $fldspec_sql = 'SELECT * FROM app_field WHERE id = ?';
	my $fldspec_sth = $dbh->prepare($fldspec_sql);

	foreach my $form_id (@form_ids) {
		$frmflds_sth->execute($form_id); #query for all field attribs of all fields of the current form (forms will start from base b/c of what we did above)

		#go over each of those fields of the current form, look up base field spec if not already done so, then override attribs as required.
		while (my $frmfld_row = $frmflds_sth->fetchrow_hashref()) {
			#look up f.spec if not already done so
			if (!$fields->{$frmfld_row->{field_id}}) {
				#obtain and plug the base field spec
				$fldspec_sth->execute($frmfld_row->{field_id});
				my $base_fld = $fldspec_sth->fetchrow_hashref(); #must only ever be one row and this must be it.
				$fields->{$frmfld_row->{field_id}} = $base_fld;

				if ($self->{_TRACK_ATTRIB_SOURCES}) {
					#if tracking attrib sources, go through all the defined attribs of the base field def and cite the base field the attrib source in the field info.
					foreach my $attrib (keys(%$base_fld)) {
						if (defined($base_fld->{$attrib})) {
							#push(@{$fields->{$frmfld_row->{field_id}}->{attrib_sources}->{$attrib}}, '[ -- BASE_FIELD -- ]');
							$fields->{$frmfld_row->{field_id}}->{attrib_sources}->{$attrib} = '[ -- BASE_FIELD -- ]';
						}
					}
				}
			}

			#plug attribs as required (those that have a value, NULLs should be undef and that means no value.);
				#how would we be able to override a property from a base field/formfield to the effect of a null value? for ex, override a field required status of a base field to have no validation rule?
			foreach my $attrib (keys(%$frmfld_row)) {
				if (defined($frmfld_row->{$attrib})) {
					$fields->{$frmfld_row->{field_id}}->{$attrib} = $frmfld_row->{$attrib}; #override attrib of field spec with the same attrib from this formfield row.
				}

				#track attribute sources if told to do so -- since we're going over the forms in the order from parent -> derived for the fields we can push field-attribute source form-names onto the end.
					#note so this is tracking all attributes that are not inherited from the base field spec.
				if ($self->{_TRACK_ATTRIB_SOURCES} && defined($frmfld_row->{$attrib})) {
					#i also want to track fallback values for attribs if doing _TRACK_ATTRIB_SOURCES -- mainly for the custom field editing screen js whizbang.
						#but I'm not sure on the best way to handle it accurately and I dont want to get into it right now .. what I have on that screen will suffice for the moment.
					$fields->{$frmfld_row->{field_id}}->{attrib_sources}->{$attrib} = $form_ids->{$form_id};
				}
			}
		}
	}

	#now .. right here .. do I want to loop over the finalized fields to, say, strip out any fields which are "commented_out" or something like that? I think that would be good. that way there'd be a SUPER easy way to even get a field right out of the SQL statement, which would supercede (obviously) the later filters for edit_show_field or search_show_field.
		#oh actually -- well I put it in a grep which will happen before the sorting of the fields. down below. actually that was such a simple little addition.

	#complete fields array -- sort by query ordering (or search display ordering failing that)
		#wondering if the way I wrote that out helps or hinders readability. obviously I hope it helps since I'm not some paranoid and self-deluded obfuscationist.
		#thinking further, I'm deciding that this is for the form_spec, and for the sql query to WORK. ... so ... go with sql_query_order ALWAYS. (and fall back to search, edit ordering in case there are dupes.)

	#Dont sound like a retard. Oh and btw, read it backwards. keys, grep, sort, map.
		#2007 02 08 saucey edit -- do the edit_options decode here, now and once only. who cares if they dont get used!
	my @fields = map {
		$self->_remap_keys($fields->{$_}); #now with edit_options_encoded instead.
#		$self->{fp}->_add_field_edit_options($fields->{$_}, { json => 'edit_options_encoded' });
#		$self->{fp}->_add_field_edit_validate_rules($fields->{$_}, { json => 'edit_validate_rules_encoded' });
		$self->{fp}->_add_field_properties($fields->{$_}, { property => 'edit_options',         from_json => 'edit_options_encoded', highlevel_prefix => 'eo' });
		$self->{fp}->_add_field_properties($fields->{$_}, { property => 'edit_validate_rules',  from_json => 'edit_validate_rules_encoded' });
		$self->{fp}->_add_field_properties($fields->{$_}, { property => 'search_query_options', from_json => 'search_query_options_encoded' });
		$self->{fp}->_add_field_properties($fields->{$_}, { property => 'search_output_format', from_json => 'search_output_format_encoded' });
		$self->{fp}->_add_field_properties($fields->{$_}, { property => 'edit_output_format',   from_json => 'edit_output_format_encoded' });

		$fields->{$_}
	} sort {
		$fields->{$a}->{sql_query_order}      <=> $fields->{$b}->{sql_query_order} or
		$fields->{$a}->{search_display_order} <=> $fields->{$b}->{search_display_order} or
		$fields->{$a}->{edit_display_order}   <=> $fields->{$b}->{edit_display_order}
	} grep {
		my $ret = 0;
		if ($args->{keep_commented_out_fields}) {
			$ret = 1;
		} else {
			$ret = !$fields->{$_}->{field_commented_out}; #1 if not commented out :)
		}
		$ret;

	} keys(%$fields);

	#need now to merge the fields we've just collected with the existing fields from the form_spec we were passed in. we will either override fields or not, but duplicate parameter names are not allowed.
#	$self->ch_debug(['before deciding what to keep or not, heres what we found from the db: ', \@fields]);
	my $keeper_fields = $override ? \@fields : $form_spec->{fields};
	my $disposable    = $override ? $form_spec->{fields} : \@fields;
	my $keeper_params = { map { $_->{parameter_name} => $_ } @$keeper_fields };
	foreach (@$disposable) {
		next if $keeper_params->{$_->{parameter_name}}; #skip this disposable field if its parameter name is already listed. bye bye poor disposable field reference. into the digital dustbin.
		push(@$keeper_fields, $_);
	}

	#apply the updated field set.
	$form_spec->{fields} = $keeper_fields;

	return { form => $form, fields => \@fields };

}

#purpose: change anything that the db record might have given us that we know about that we have to do something about.
sub _remap_keys {
	my $self = shift;
	my $fieldref = shift;
	my $args = shift;

	foreach ('edit_options', 'edit_validate_rules', 'search_query_options', 'search_output_format', 'edit_output_format') {
		if ($fieldref->{$_}) {
			$fieldref->{$_ . '_encoded'} = delete($fieldref->{$_});
		}
	}
}

#this one just makes our parameter_to_fieldref mapping. It will include subfields in there.
#it was added 2007 02 26 to help support some stuff I want to be able to access in the Relator thing. Want to just ask for fieldrefs by parameter name, and since I already sorta had that now its formalized.
	#update, making this operate on a single field and moving it to {fp}.
#sub _parameter_to_fieldref {
#	my $self = shift;
#	my $args = shift;
#
#	my $form_spec = $self->form_spec();
#	my $param_fields = $self->{fp}->_get_merged_fields_and_subfields($form_spec->{fields});
#
#	my $param_to_fieldref = { map { $_->{parameter_name} => $_ } grep {$_->{parameter_name}} @$param_fields };
#	$form_spec->{form}->{parameter_to_fieldref} = $param_to_fieldref;
#	$self->form_spec($form_spec); #set it back.
#}

sub _get_dbh {
	my $self = shift;
	my $db_name = shift;
	if (!$db_name && $self->{'_db_name'}) {
		$db_name = $self->{'_db_name'};
	}
	#$self->ch_debug(["DataObj::_get_dbh: asking for a dbh with db_name of $db_name"]);
	return $self->{wa}->get_dbh({db_name => $db_name});
}

sub _get_formcontrol_dbh {
	my $self = shift;
	#$self->ch_debug(["DataObj::_get_formcontrol_dbh: my formcontrol dbh name is:", $self->{_formcontrol_db}]);
	return $self->_get_dbh($self->{_formcontrol_db});
}
sub _get_data_dbh {
	my $self = shift;
	return $self->_get_dbh($self->{_data_db});
}

sub split_keywords {
	my $self = shift;
	return $self->{sa}->_split_keywords(@_);
}

#eventually to replace my own split_attribs thing with the JSON thing. As suggested by merlyn in #perl on irc.freenode.net/irc.freenode.org ... as opposed to kludging in escapes now that I want them
	#and also, a goofy silly idea to kludge json attribute lists into the things I've already used my own goofy thing for, if the first char looks like JSON, slam it through here. -- yeah no becase I've already fixed all uses of _split_attribs as well as the values in the db!
sub _json_attribs {
	my $self = shift;
	my $json_str = shift;

	my $perl_data_structure = JSON::Syck::Load($json_str);
	#$self->ch_debug(['_json_attribs: turned this into that', $json_str, $perl_data_structure]);
	return $perl_data_structure;
}

#rrrrrrrrrrripped from cgiapp... (thanks cgiapp!) adding here 2007 08 21 because I want to set some custom params inside some custom object methods that I'm adding to dataobjs like the blumont monthdoc editor object.
	#(then oh so slightly modified)
sub param {
	my $self = shift;
	my (@data) = (@_);

	# First use?  Create new __PARAMS!
	$self->{__PARAMS} = {} unless (exists($self->{__PARAMS}));

	my $rp = $self->{__PARAMS};

	# If data is provided, set it!
	if (scalar(@data)) {
		# Is it a hash, or hash-ref?
		if (ref($data[0]) eq 'HASH') {
			# Make a copy, which augments the existing contents (if any)
			%$rp = (%$rp, %{$data[0]});
		} elsif ((scalar(@data) % 2) == 0) {
			# It appears to be a possible hash (even # of elements)
			%$rp = (%$rp, @data);
		} elsif (scalar(@data) > 1) {
			croak("Odd number of elements passed to param().  Not a valid hash");
		}
	} else {
		# Return the list of param keys if no param is specified.
		return (keys(%$rp));
	}

	# If exactly one parameter was sent to param(), return the value
	if (scalar(@data) <= 2) {
		my $param = $data[0];
		return $rp->{$param};
	}
	#return;  # Otherwise, return undef
	return $self;  # Otherwise, return object reference. (for teh chainingz)
}

sub DESTROY {
	#attempting to figure out some memory bloat issue, it was suggested that circular references can lead to the GC not being able to deallocate memory. now I _know_ i have effectively circular references in this code in that we have refs to the support objects and they all have refs back to us (their ->{'do'})
	my $self = shift;
	
	#print "lololol in destroy\n";
	#die "lol, well this also happend";

	#die "really here";
#	$self->{wa}->debuglog(['here1 in destroy']);
#	$self->_dereference();
#	$self->{wa}->debuglog(['here2 in destroy']);
	return 1;
}

1;
