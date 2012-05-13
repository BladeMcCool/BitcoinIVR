package SpApp::ImportExportXLS;
#note, this is a copy of the Abriachart code for this, however I plan to hack it up into a generalized routine which may possibly have callbacks for stupid gayness like mapping happy fun display names to data object parameter names. or other dumb ideas.
#gorsh .. cut the wheat from the chaffe. core ideas to hold on to:
#what are we really doing here? we are going to open an excel file(s), and read data out of worksheet(s).
#presumably every worksheet represents flat tabular data, with headings above fields so we can somehow figure out what data goes into what db field.
#i think we do something with a list of roww. i think we can structure it like an array of hashrefs, each hashref representing a single row of data, keyed by field parameter names.
#that clearly splits xls import into two operations - obtaining rows from xls worksheets, and then doing something with them.
#i can think of only one "standard" do-something-with-it concept, and that would be blanket record insertion. I can think that perhaps we might want to do updates if one of the fields was a clearly marked 'record_id' or just 'id'
#but either way, this auto behavior would have to be requested i think, and even then it would need to know what data object to use for 

use strict;
use Spreadsheet::ParseExcel::Simple;
use Archive::Extract;
use FileUpload::Filename;
use Data::Dumper; 
use Time::Piece;
use B; #for coderef2name which I got off perlmonks
use Encode;


sub new {
	my $class = shift;
	my $self = {};
	bless $self, $class;

	my $web_app = shift; #needed for access to dbh, query, session, etc.
	my $other_args = shift;

	$self->{_ERROR_COND} = undef;	#set up for error method. why here? dunno.
	if (!$web_app) {
		$self->error('new needs a webapp.');
	}
	$self->{wa} = $web_app;
	
	return $self;
}

sub error {
	my $self = shift;
	my $value = shift;
	
	if ($value) {
		$self->{_ERROR_COND} = $value;
	} else {
		return $self->{_ERROR_COND};
	}
}

sub ch_debug {
	my $self = shift;
	my $var = shift;
	return $self->{wa}->ch_debug($var);
}

sub import_xls {
	my $self = shift;
	my $args = shift;
	
	#args will include:
	#	upload_param   => 'cgi_param_for_filedata', #cgi param to find file data in.
	#	save_to_dir    => '/var/www/somehost.com/xls_upload', #path to save file data to
	#	worksheets_meta => {
	#		'worksheet_name' => {
	#			data_obj_classname    => 'Some::Data::Object',
	#			heading_to_params_map => { 'Some Long-Winded Field Name' => 'dobj_field_parameter',	}, 
	#		},
	#		'_first_worksheet' => { #a special case, because we dont know or care what the worksheet is called ... we know that the first one we encounter is this one.
	#			data_obj_classname    => 'Some::Data::Object',
	#			heading_to_params_map => { 'Some Long-Winded Field Name' => 'dobj_field_parameter',	}, 
	#		},
	#	}

	#probbaly needs some kind of import operation descriptor, but will basically handle upload, extract data, and insert records.
	$args->{filepaths} = $self->handle_xls_upload($args);
	my $extract_result = $self->extract_data_from_xls($args);
	return $extract_result;

}

#pass a parameter_name to get the file data with, and a save_to_dir path to save it/them to.
sub handle_xls_upload {
	my $self = shift;
	my $args = shift;
	
	#check we can save to the target path ..
	my $filename = undef;
	my $filepath = undef;
	if (!-w $args->{save_to_dir}) {	die "target path $args->{save_to_dir} is not writable to me";	}

	my $upload_handling = 1; #usually we want to get the data from the cgi and save to filesystem.
	if ($args->{read_from_existing_file}) { 
		$upload_handling = 0;
	}

	if ($upload_handling) {
		my $upload_param = $args->{upload_param} . '_fileinput';
		my $cgi = $self->{wa}->query();
		$filename = FileUpload::Filename->name({ filename  => $cgi->param($upload_param) });
		$filepath = $args->{save_to_dir} . '/' . $filename;
		my $upload_fh = $cgi->upload($upload_param);
		open UPLOADFILE, ">$filepath" or die "couldn't create upload file at '$filepath'\n";
		while (<$upload_fh>) {
			print UPLOADFILE $_;
		}
		close UPLOADFILE;
	} else {
		#not handling upload, just using existing file whos filename has been passed in.
		$filename = $args->{read_from_existing_file};
		$filepath = $args->{save_to_dir} . '/' . $filename;
	}
	
	#handle multiple files now.
	my $filepaths = [];
	
	#now, I'd like to be able to deal with both plain .xls files and ones that were uploaded in a zip file.
	#so, if the file extension was .xls, just return the filepath. If the extension was .zip, then extract the single .xls file from it.
	#use Archive::Extract; #move to vhost.conf once verified working
	if ($filename =~ /\.zip$/) {
		my $ae = Archive::Extract->new( archive => $filepath, type =>'zip' );
		my $ok = $ae->extract(to => $args->{save_to_dir}) or die "AE Error: " . $ae->error;
		my $files   = $ae->files();		
		#now this module is VERY simple to use, but we can't really control which files will get extracted. Thats ok, since I dont want to do all that work anyway. Lets just use the _first_ .xls file we find. Who really cares if we extract other stuff into the temp directory. Hell, in future maybe we'll WANT to support multiple .xls files, and return an array of filepaths .. whatever for now go with first one found.
		#simplest operation would be to die if the first file is not a .xls file.
		#$self->ch_debug(['handle_xls_upload: extracting from zip file, looking at a file list like: ', [sort {lc($a) cmp lc($b)} (@$files)] ]);
		foreach (@$files) {
			next if ($_ !~ /\.xls$/);
			push(@$filepaths, $args->{save_to_dir} . '/' . $_);
		}
		if (!scalar(@$filepaths)) {
			die "Error: No .xls files found in uploaded .zip file.";
		}
		$self->ch_debug(["inside uploaded .zip named $filename we have files like:", $files, 'copied to', $filepaths]);
	} else {
		#not a zip upload, just the one file can be handled.
		push(@$filepaths, $filepath);
	}
	
	#sort alphabetically so that the order in which stuff is loaded can sort of be controlled.
	@$filepaths = sort {lc($a) cmp lc($b)} @$filepaths; #this sort method will have us with numbers and underscore prefixed items at the beginning of the list. which is good if you want to control what order stuff goes in.
	
	$self->ch_debug(['handle_xls_upload: here with sorted list of filepaths like:', $filepaths ]);

#	die "Before sending back filepaths";
	return $filepaths;
}

sub extract_data_from_xls {
	my $self = shift;
	my $args = shift;

	my $filepaths       = $args->{filepaths};
	my $worksheets_meta = $args->{worksheets_meta};
	my $load_data       = $args->{load_data};
	my $return_data     = $args->{return_data};
	if (!$load_data) { $return_data = 1; }

	#we dont need to know much to do this. we can look through all the sheets of all the files we got, and can fish out rows. with field headings as parameter names we can produce row hashes easily. if we know what data object to use for what worksheet, we can use it to load the data.
	#presumably there is a limited subset of worksheets we actually care about. a couple magic worksheet names to think about, and otherwise just look for the ones we've been given.
	
	my $extraction_report = {}; #in case we want to send back some meta.
	my $failure_report    = {}; #cuz I want to know why they suck. will get jammed into the extraction_report.
	my $worksheets_data = {};
	my $worksheets_unprocessed_data = {};
	my $table_actions_tracking = {}; #to keep us on track and make sure we arent fucking ourselves up (dont empty or create a db table more than 1x during an import operation)
	my $worksheets_encountered = 0;
	#go over each of the uploaded files (can only be more than one if provided in a .zip file at the moment) and load the data from each. any errors must note the workbook AND worksheet name in addition to the line number.
	foreach my $filepath (@$filepaths) {

		#ensure what should be there is in fact there.
		if (!-e $filepath) { die "path '$filepath' does not exist -- but I should have just created it. Something must have gone horribly wrong."; }
		
		my $xls = Spreadsheet::ParseExcel::Simple->read($filepath);
	  my @sheets = $xls->sheets;
	
		#anything to report?
		#push(@printable_load_report, "Workbook file: $filepath");
		
		foreach my $sheet (@sheets) {
			$worksheets_encountered++;
			
			#figure out if we care to bother extracting anything from this worksheet.
				#should make this case insensitive but that would mean converting the keys of the worksheet_meta hashref to their lower case forms first ... hrm.
			my $sheetname = $sheet->sheet->{Name};
			my $extract_from_sheet = 0;
			my $worksheet_meta_sheetname = undef; 
			if ($worksheets_meta->{$sheetname}) {
				$worksheet_meta_sheetname = $sheetname;
				$extract_from_sheet = 1;
			} elsif ($worksheets_encountered == 1 && $worksheets_meta->{_first_worksheet}) {
				$worksheet_meta_sheetname = '_first_worksheet';
				$extract_from_sheet = 1;
			}			
			$self->{wa}->debuglog(['extract_from_sheet: looking at a sheet named:', $sheetname, 'of file', $filepath, 'we care about all those in this list:', [keys(%$worksheets_meta)], 'and so we have decided to care this much about the current one', $extract_from_sheet ]);
			
			#skip to the next one if we know we dont care about this one.
			next if (!$extract_from_sheet); 
			
			my $worksheet_meta = $worksheets_meta->{$worksheet_meta_sheetname};
			my $load_sheet_data = $load_data;
			my $load_data_obj   = $worksheet_meta->{data_obj_classname} ? ($worksheet_meta->{data_obj_classname})->new($self->{wa}) : undef;
			if ($load_sheet_data && !$load_data_obj) { die "Cannot load sheet data without a data object to do so"; }
			my $params_conversion_context = {}; #pass around to conversion subs so they can pass each other data.
			
			#creating and emptying of tables? flagging at the worksheet_meta level always overrides args-level flags.
			my $create_target_table = 0;
			my $empty_target_table = 0;
			if ($load_data_obj) {
				if (defined($worksheet_meta->{create_target_table})) {
					$create_target_table = $worksheet_meta->{create_target_table};
				} elsif ($args->{create_target_tables}) {
					$create_target_table = 1;
				}

				#flagging at the worksheet_meta level always overrides args-level flags.
				if (defined($worksheet_meta->{empty_target_table})) {
					$empty_target_table = $worksheet_meta->{empty_target_table};
				} elsif ($args->{empty_target_tables}) {
					$empty_target_table = 1;
				}
				
				#there is situation where db schema has changed and we just for this run, while it is uncommented, recreate the tables early upon first encounter.
				if ($load_sheet_data && $args->{create_target_tables_immediately} && !$table_actions_tracking->{created}->{$load_data_obj->form_spec()->{form}->{base_table}}) {
					$load_data_obj->create_table({drop=>1});
					$table_actions_tracking->{created}->{$load_data_obj->form_spec()->{form}->{base_table}} = 1; #yes, you did it now. remember it for next time, fucker. (me so silly)
				}
			}

			my $fields_mapped    = 0; #turn true once we've picked up the field headings from the first row and mapped them to data object parameter names.
			my $column_params    = {}; #map numeric columns starting from 0 to 
			my $params_orig_headings = {}; #map dobj param names to the origninal headings of the xls (new for 2008 02 28 as we want a whole row params conversion sub to know more precisely where field values came from
			my $last_column      = undef; #determined by headings, zero-indexed last column number, we wont read past this and first row where all fields up to this one are empty is our early eof.
			my $field_formats    = $worksheet_meta->{field_formats}; #would be dobj params to field formats like 'number'. lets us know what is acceptable value to stick into the row hash.
			my $strip_formatting = $worksheet_meta->{strip_formatting}; #should be hashref of param_names => 1 for which we MUST get unformatted values

			#push(@printable_load_report, "Worksheet: $sheetname");

			#foreach line of the sheet
			my $row_num = 0; #row of actual data
			my $line_num = 0; #line in the file being processed
			my $headings_line = defined($worksheet_meta->{headings_line}) ? $worksheet_meta->{headings_line} : 1; #can be overridden. can even be set to zero if there are none or you want them in the data.
			my $worksheet_row_data = []; #to hold row hashrefs.
			my $worksheet_row_unprocessed_data = []; #to hold row arrayrefs of unmolested row data.
			DATA_ROW: while ($sheet->has_data) {
				my @data = $sheet->next_row; #we'd LIKE to be able to use the formatted values -- but they need to be formatted in such a way as to be useful. Perhaps we need to have a mapping of params-to-valueaccessor lolz --- actually i kinda implemented that now with the while strip_formatting thing.
				
				$line_num++; #line of actual file.
				$params_conversion_context->{sheet_name} = $sheetname;
				$params_conversion_context->{xls_file}   = $filepath;
				$params_conversion_context->{line_num}   = $line_num;
	
				#possibly-pre-dataload, possibly-pre-headings-encountered goofyass shit?				
					#mainly adding so I can do some shit that will get some info into the context in some stupid ass lame excel files from blumont.
				if ($worksheet_meta->{line_processing_subs}->{$line_num}) {
					my ($subrefs, $subref_args) = $self->_get_subrefs_and_args($worksheet_meta->{line_processing_subs}->{$line_num});
					foreach my $subref (@$subrefs) {
						$subref->($self->{wa}, {
							unprocessed_row_data => \@data,
							context              => $params_conversion_context,
							%$subref_args,
						});
					}
				}

				#if we have not reached the headings line we will not be loading any data.
				if ($line_num < $headings_line) {
					next;
				}
				
				#on first run, do headings to params map.
				if (!$fields_mapped && $line_num == $headings_line) {
					#default the field params to match the headings exactly. override those with any provided overrides.
					for (my $i = 0; $i < @data; $i++) {
						if (!$data[$i]) { last; } #done, nothing more to look at.

						#case-insensitive lookup - remap the headings-to-params to be all lower case for headings.
							#if no mapping provided, will just assume that the lower-cased field-heading and the parameter-name are the same.
						my $field_param = lc($data[$i]);
						my $h_to_p = { map { lc($_) => $worksheet_meta->{heading_to_params_map}->{$_} } keys(%{$worksheet_meta->{heading_to_params_map}}) };
						
						if ($h_to_p->{$field_param}) { 
							#o i c, it needs to be remapped.
							$field_param = lc($h_to_p->{$field_param});
						}
						$column_params->{$i} = $field_param; #now I know what field data in column 2 is for ... for example.
						$last_column = $i; #if we run again, will be updated

						#take note of where stuff will be coming from in case we need to know elsewhere.
						$params_orig_headings->{$field_param} = $data[$i];
					}
					$fields_mapped = 1;
					next; #skip to the next row, nothing more to do with the fields headings row!
				}
				$row_num++; #incr the line number only after headings have been done. so first data record is line 1 not the headings row.

				##debug slam hammery? dont want to do huge data set sometimes when workin on code so bail after x records.
				#if ($row_num > 5) { last DATA_ROW; }
				##comment that shit out if you wanna do a real full data set.
			
				### not doing db stuff just yet #@data = @data[0..$last_column]; #dont allow too many fields in the xls sheet to cause a bind-variable-count problem -- lose any extra fields!
		
				#build the row hash. Also, terminate if we have hit a completely empty row.
				my $row_data = {};
				my $row_has_data = 0; #initial pessimismo. and all it takes is a single cell with data to have row_has_data.
				for (my $i = 0; $i <= $last_column; $i++) {
					if ($data[$i] !~ /^\s*$/) { $row_has_data = 1; }
					#depending if we're to strip_formatting from this field, we'll eithre be pulling from simple $data[$i] or digging into the sheet and grabbing the unformatted value directly.
					my $cell_data = $strip_formatting->{$column_params->{$i}} ? $sheet->{sheet}->{Cells}[$line_num-1][$i]->{Val} : $data[$i];
					if ($field_formats->{$column_params->{$i}}) {
						#format accordingly, if needed.
						if ($field_formats->{$column_params->{$i}} eq 'number' && $cell_data =~ /^\s*$/) {
							$cell_data = undef;
						}
					}
					$row_data->{$column_params->{$i}} = $cell_data;
				}
				
				if ($row_has_data) {
					#i was thinking we could be doing inline processing here, and this would be the spot to do it. acutally ... lets mess with that.

					if ($worksheet_meta->{params_conversion_subs} || $worksheet_meta->{data_validation_sub}) {
						#set up context - is used for a few different possibly processings.
						$params_conversion_context->{row_num}    = $row_num; #row of data being processed. number 1 is the first one after the headings.
						$params_conversion_context->{line_num}   = $line_num; #actual line number of the import worksheet
						$params_conversion_context->{previous_processed_rows} = $worksheet_row_data; #dont really need to assign this for every row but should be harmless as it's just a reference.
						$params_conversion_context->{params_orig_headings}    = $params_orig_headings; #cuz i need this info now in a _whole_row conversion thing (2008 02 28)
					}

					#field data processing? if there are worksheet_meta params_conversion_subs then we need to call them.
						#any of these conversion subs is expected to return a scalar to replace the original value, however since we are passing the row data it is quite conceivable that it can do whatever the hell to the whole data.
						#a special param _whole_row can be used to call it differently and not assign back to the row, this would be for just generally processing the row data via the row_data hashref.
						#otherwise, an existing parameter must be named and the result will be assigned back.
					if ($worksheet_meta->{params_conversion_subs}) {
						
						#get the processing subs into the right order. key thing being that any _whole_row one comes last, after others have done their shit to the row.
						my @param_conversion_ordered = grep {$_ ne '_whole_row'} keys(%{$worksheet_meta->{params_conversion_subs}});
						if ($worksheet_meta->{params_conversion_subs}->{_whole_row}) { push(@param_conversion_ordered, '_whole_row'); }#this will be last now if it was present.

						foreach my $param (@param_conversion_ordered) {

							my $conversion_control = $worksheet_meta->{params_conversion_subs}->{$param};

							my ($subrefs, $subref_args) = $self->_get_subrefs_and_args($conversion_control);
							#run multiple subref's for each param, as required.
							foreach my $subref (@$subrefs) {
								if ($param eq '_whole_row') { 
									#a _whole_row one will actually be the last one that is done, because we've made sure they are ordered so up above.
									#it is expected to manipulate the row_data directly.
									$params_conversion_context->{param} = undef; #no specific param here.
									$subref->($self->{wa}, {
										row_data    => $row_data, #all the data, function will just do what it has to do on it.
										context     => $params_conversion_context,
										data_obj    => $load_data_obj,
										%$subref_args,
									});
								} else {
									#regular single param/field fixup.
									#it is expected to return a new value for the field and not mess with the row itself (although nothing will stop it)
									$params_conversion_context->{param} = $param;
									$row_data->{$param} = $subref->($self->{wa}, {
										param_data  => $row_data->{$param}, #what was specifically asked for
										row_data    => $row_data, #the rest of the data in case its needed.
										context     => $params_conversion_context,
										data_obj    => $load_data_obj,
										%$subref_args,
									});
								}
							}
						}
					}
					
					#data integrity checks? because input is just plain bad. (doing it after params conversion subs since one of those could have made the row good)
					if ($worksheet_meta->{data_validation_sub}) {
						$params_conversion_context->{param} = undef; #no specific param here (and might have set one earlier)

						my ($subrefs, $subref_args) = $self->_get_subrefs_and_args($worksheet_meta->{data_validation_sub});
						foreach my $subref (@$subrefs) {
							my $valid = $subref->($self->{wa}, {
								row_data    => $row_data, #the whole row data. assumed to be needed.
								context     => $params_conversion_context,
								data_obj    => $load_data_obj,
								%$subref_args,
							});
							if (!$valid) {
								#what should we do??? I'm really not sure. I tend to think that if the row is deemed invalid then we should just pretend we didnt even see it.
								#meaning skip to the next, dont add it to the row data, dont load it dont do anything after this point with it.
								
								#also take a note of the lameness.
								if (ref($failure_report->{$filepath}->{$sheetname}->{$row_num}) ne 'ARRAY') { $failure_report->{$filepath}->{$sheetname}->{$row_num} = []; }
								push(@{$failure_report->{$filepath}->{$sheetname}->{$row_num}}, $self->coderef2name($subref));
								$extraction_report->{had_failure} = 1;
								
								#and then skip to the loo my darlin.
								next DATA_ROW;
							}
						}
					}

					if ($return_data) {
						push(@$worksheet_row_data, $row_data);
						push(@$worksheet_row_unprocessed_data, \@data);
					}
					if ($load_sheet_data) {
						#moving the empty/create stuff here ... so we have to be told to LOAD data before we will think about messing with db stuff.
						#and then of course we actually have to have hit a row with data before we'll get here too, so a empty worksheet with just headings will not cause us to wipe the table (though now what would we do if we wanted to wipe the table - not sure).
						my $db_table = $load_data_obj->form_spec()->{form}->{base_table};
						if (!$db_table) { die "Error no db_table determined from the data object. Incorrect call?"; }
						if ($create_target_table && !$table_actions_tracking->{created}->{$db_table}) {
							$load_data_obj->create_table({drop=>1});
							$table_actions_tracking->{created}->{$db_table} = 1; #so we dont do it again.
						}
						if ($empty_target_table && !$table_actions_tracking->{emptied}->{$db_table}) {
							$load_data_obj->empty_table();
							$table_actions_tracking->{emptied}->{$db_table} = 1; #so we dont do it again.
						}

						#die "yeah supposed to insert some data";
						#if we were thinking about doing updates instead of inserts, here is where we'd ponder it.
						$load_data_obj->new_record_for_edit()->set_edit_values($row_data)->save_edited_record();
						#die "yeah supposed to have just inserted some data";
						$extraction_report->{loaded_records}->{$worksheet_meta_sheetname}++;
						#push($extraction_report->{report}->{
					}
					$extraction_report->{report}->{$worksheet_meta_sheetname}->{num_records}++;
				} else {
					#die "DEBUG: extract_data_from_xls: reached a row with no data at row $row_num of sheet with meta name of $worksheet_meta_sheetname - must verify this block.";
					#since this working, but is also a case that we might want to know about, do some debuglog instead.
					$self->{wa}->debuglog(["DEBUG: extract_data_from_xls: reached a row with no data at row $row_num of sheet with meta name of $worksheet_meta_sheetname. - might want to just check that the worksheet really ends at that point, though it probably really does."]);
					last; #hit a row with no data, we are done like a turkey dinner at thanksgiving.
				}

			} #end loop over worksheet rows.
			#die "stop and see";


			#i can imagine needing to do some processing based on ALL rows before inserting ANY of them. in that case a new flag will be reqiured that skips the line-by-line loading and enables something down here than would then call a subref with all the data and then load in whatever data was kept (imagine it totally changing rows or wanting to skip rows entirely)

			#stick the data into the big d.s.
			if ($return_data) {
				#$worksheets_data->{$worksheet_meta_sheetname} = $worksheet_row_data;
				push(@{$worksheets_data->{$worksheet_meta_sheetname}}, @$worksheet_row_data);
				push(@{$worksheets_unprocessed_data->{$worksheet_meta_sheetname}}, @$worksheet_row_unprocessed_data);
			}
			
			#report something about the worksheet just dealt with.
			#push(@printable_load_report, "Processed $row_num worksheet rows. Running error count is: " . scalar(@error_report));
			
		} #end loop over worksheets
	} #end loop over uploaded .xls files.

	$extraction_report->{data}             = $return_data ? $worksheets_data             : {};
	$extraction_report->{unprocessed_data} = $return_data ? $worksheets_unprocessed_data : {};
	$extraction_report->{failures} = $failure_report;
	return $extraction_report;
	
}

sub _get_subrefs_and_args {
	my $self = shift;
	my $control = shift;
	
	#$self->ch_debug(['_get_subref_and_args here with args like:', $control, 'ref of control is', ref($control) ]);

	my $subrefs = [];
	my $subref_args = {};

	if (ref($control) eq 'CODE') {
		#just a subref
		$subrefs = [ $control ];
	} elsif (ref($control) eq 'ARRAY') {
		#just proof them
		foreach (@$control) { if (ref($_) ne 'CODE') { die "Encountered non CODE reference within arrayref of subs"; } }
		$subrefs = $control;
	} elsif (ref($control) eq 'HASH') {
		#hashref - must have keys 'sub' and 'args'. and they must be the right type of thing.
		if (!$control->{'sub'}) { die "No value for the subref was provided."; }
		$subrefs      = $control->{'sub'};
		$subref_args  = $control->{'args'} ? $control->{'args'} : {};
		if (ref($subrefs) eq 'ARRAY')  { 
			#proof them
			foreach (@$subrefs) { if (ref($_) ne 'CODE') { die "Encountered non CODE reference within arrayref of subs"; } }
		} elsif (ref($subrefs) eq 'CODE') {
			$subrefs = [ $subrefs ];
		} else {
			die "Error: sub provided is NOT a sub ref or an arrayref of subrefs.";
		}
		if (ref($subref_args) ne 'HASH') { die "Error: args provided is NOT a hash ref."; }
	} else {
		die "Error: unrecognized field/data/param control spec.";
	}
	
	return ($subrefs, $subref_args);
}

sub export_xls {
	my $self = shift;
	die "NYI - have a look at Reporting::excel_report and Reporting::send_excel_data (call 2nd with output of 1st) - some notes in the comments in Reporting on how to use that function. It expects a data structure of a certain layout to be passed.";
}

#this bit here stolen/borrowed directly from http://www.perlmonks.org/?node_id=413799
	#(cuz I want to know the name of the subref that just returned a 0 to me thus failing a record and denying its insertion.)
sub coderef2name {
	my $self = shift;
   eval {
      my $obj = B::svref_2object( shift() );
      $obj->STASH->NAME . "::" . $obj->GV->NAME;
   } || undef;
}

1;