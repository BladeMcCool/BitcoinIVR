package SpApp::Reporting;

#group reporting related shit in one place.
	
use strict;
use Spreadsheet::WriteExcel;

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

#calling excel_report ... (is a little hairy unless you are passiing well configured search_results. )
#
#$args = {
# report_name => 'common to all worksheets',
#	report_data => [{
#		worksheet_name => 'the worksheet name'
#		worksheet_data => { 
#			suppress_standard_header => 1,
#			suppress_standard_footer => 1,
#			excel_formats => { parameter_name => { data_format => 'float', value_source_override => 'disp' }, ...}; #valid formats are: int, float, date, date_time. no format means its regular text. and you can code excel_format on each fieldref instead to be more precise. valid value_source_overrrides are just 'disp' at the moment.
#			records => [
#				{ record_fields => [{ search_show_field => 1, parameter_name => 'foo_field', display_name => 'foo heading text', db_value => 'blabla', db_value_disp => 'bla bla'  }, ... ]},
#				...
#			]
#		}
#}];
#
#or ..
#
#$args = {
# report_name => 'for only the one worksheet',
#	report_data => { 
#		suppress_standard_header => 1,
#		suppress_standard_footer => 1,
#		excel_formats => { parameter_name => { data_format => 'float', value_source_override => 'disp' }, ...}; #valid formats are: int, float, date, date_time. no format means its regular text. and you can code excel_format on each fieldref instead to be more precise. valid value_source_overrrides are just 'disp' at the moment.
#		records => [
#			{ record_fields => [{ search_show_field => 1, parameter_name => 'foo_field', display_name => 'foo heading text', db_value => 'blabla', db_value_disp => 'bla bla' }, ... ]},
#			...
#		]
#	}

sub excel_report {
	my $self = shift;
	my $args = shift;
	
	my $report_data = $args->{report_data}; #could be arrayref or hashref. if it is arrayref, we assume multiple worksheets in same output document.
		
	use IO::Scalar;
	use Spreadsheet::WriteExcel;
	my $xls_str;
	my $fh;
	#print STDERR "excel_report 1\n";
	if ($args->{fh}) {
		$fh = $args->{fh};
	} else {
		$fh = IO::Scalar->new(\$xls_str);
	}
	my $workbook  = Spreadsheet::WriteExcel->new($fh);
	my $format_bold = $workbook->add_format(bold => 1);
	my $format_date_time = $workbook->add_format(num_format => 'yyyy-mm-dd hh:mm:ss');
	my $format_date = $workbook->add_format(num_format => 'yyyy-mm-dd');
	my $fixed_cell_width  = 15;

	my $now_str = localtime(); #just for the time stamp.
	#print STDERR "excel_report 2\n";

	#get out the report title
	my $report_name = $args->{report_name};
	if (!$report_name) { $report_name = "Generic Report"; }
	$report_name =~ tr/\:\*\?\/\\/     /; #transliterate all excelBad chars to spaces.

	#support multiple worksheets.
		#report data should be an array of hashrefs with keys like 'worksheet_name' and 'worksheet_data' (which for backward compatibility report_data should be a hashref with probaly the only key of 'records')
		#if it wasnt passed in as an arrayref, make it into one in the above format and use $report_name (processed from other_args->{report_name)) as the worksheet name.
	if (ref($report_data) ne 'ARRAY') {
		$report_data = [{
			worksheet_name => $report_name,
			worksheet_data => $report_data,
		}];
	}

	my $sheet_footer_text = 'Powered by CHWS';
	if ($args->{sheet_footer_text}) {
		$sheet_footer_text = $args->{sheet_footer_text};
	} elsif ($self->{wa}->config('sheet_footer_text')) {
		$sheet_footer_text = $self->{wa}->config('sheet_footer_text');
	}
		
	#$self->{wa}->debuglog(['excel_report, with args like: ', $args, 'and now report data like:', $report_data ]);
	#so every report data entry in the arrayref will give us at least one worksheet. if any of them are header+list with multiple headersection results, those will also each result in multiple worksheets being added (you know, like once that is implemented lol).

#	#generate the report
#	if ($report->{header_plus_list}) {
#		#loop over each search main result
#
#		foreach my $search_result (@{$report->{search_results}}) {
#			#add a new worksheet for each main record
#			my $worksheet = $workbook->add_worksheet('Record ' . $search_result->{number});
#			my $hpos = 0; #horizontal position
#			my $vpos = 0; #vertical position
#			
#			$worksheet->write_string($vpos, $hpos, $self->param('_mail_return_name'));
#			$worksheet->write_string($vpos, $hpos+2, $report_name);
#			$worksheet->write_string($vpos, $hpos+4, $now_str);
#			$vpos+=2;
#		
#			#the over each field of the result record to draw the header area
#			$worksheet->write_string($vpos, $hpos, 'Record ' . $search_result->{number} . ' of ' . $report->{num_records} . ':', $format_bold);
#			$vpos++; $hpos = 0; #cr-lf
#			foreach my $result_field (@{$search_result->{result_fields}}) {
#				if ($result_field->{show_field}) {
#					$worksheet->write_string($vpos, $hpos, $result_field->{display_name}, $format_bold); #draw the heading
#					$hpos++; #next cell over
#					if ( $result_field->{excel_format} eq 'int' || $result_field->{excel_format} eq 'float' ) {
#						$worksheet->write_number($vpos, $hpos, $result_field->{field_value});
#					} elsif ($result_field->{excel_format} eq 'date') {
#						my $field_value = $result_field->{field_value};
#						$field_value .= 'T'; #append a T to the date in accordance with the Spreadsheet::WriteExcel module
#						$worksheet->write_date_time($vpos, $hpos, $field_value, $format_date);
#					} elsif ($result_field->{excel_format} eq 'date_time') {
#						my $field_value = $result_field->{field_value};
#						$field_value =~ s|\s|T|g; #change the seperating space betweend date and time to a 'T'. as in 2005-09-08 11:09:26 becomes 2005-09-08T11:09:26
#						$worksheet->write_date_time($vpos, $hpos, $field_value, $format_date_time);
#					} else {
#						$worksheet->write_string($vpos, $hpos, $result_field->{field_value}); #draw the value
#					}
#					$vpos++; $hpos = 0; #cr-lf
#				}				
#			}
#			$vpos++; #blank line before "record details label";
#			$worksheet->write_string($vpos, $hpos, 'Record Details:', $format_bold);
#			$vpos++;
#		
#			foreach my $sub_searchform_field (@{$search_result->{sub_searchform_fields}}) {
#				#draw the field headings for the details rows
#				if ($sub_searchform_field->{show_field}) {
#					$worksheet->set_column($hpos, $hpos, $fixed_cell_width);
#					$worksheet->write_string($vpos, $hpos, $sub_searchform_field->{display_name}, $format_bold);
#					$hpos++; #over one cell for next heading
#				}
#			}
#			$vpos++; $hpos = 0; #cr-lf
#			foreach my $sub_search_result (@{$search_result->{sub_search_results}}) {
#				#draw the field values, one line at a time!
#				foreach my $result_field (@{$sub_search_result->{result_fields}}) {
#						if ($result_field->{show_field}) {
#							if ( $result_field->{excel_format} eq 'int' || $result_field->{excel_format} eq 'float' ) {
#							$worksheet->write_number($vpos, $hpos, $result_field->{field_value});
#						} elsif ($result_field->{excel_format} eq 'date') {
#							my $field_value = $result_field->{field_value};
#							$field_value .= 'T'; #append a T to the date in accordance with the Spreadsheet::WriteExcel module
#							$worksheet->write_date_time($vpos, $hpos, $field_value, $format_date);
#						} elsif ($result_field->{excel_format} eq 'date_time') {
#							my $field_value = $result_field->{field_value};
#							$field_value =~ s|\s|T|g; #change the seperating space betweend date and time to a 'T'. as in 2005-09-08 11:09:26 becomes 2005-09-08T11:09:26
#							$worksheet->write_date_time($vpos, $hpos, $field_value, $format_date_time);
#						} else {
#							$worksheet->write_string($vpos, $hpos, $result_field->{field_value}); #draw the value
#						}
#						$hpos++; #over one cell for next field
#					}
#				}
#				$vpos++; $hpos = 0; #cr-lf
#			}
#			$vpos+=3; $hpos = 0; #cr(3)-lf
#			$worksheet->write_string($vpos, $hpos, 'Powered by CHWS Schedule');
#		}
#
#	} else {


	#print STDERR "about to loop over worksheets of which there are " . scalar(@$report_data) . "\n";
	#$self->ch_debug(['like a motherfucker:', $report_data]);
	my $sheetcount = 0;
	foreach (@$report_data) {	
		$sheetcount++;
		my $hpos = 0; #horizontal position
		my $vpos = 0; #vertical position

		my $sheet_name = $_->{worksheet_name};
		my $sheet_data = $_->{worksheet_data};
		my $excel_formats = $sheet_data->{excel_formats} ? $sheet_data->{excel_formats} : {}; #I will say this is the _preferred_ way of specifying the excel formats for the fields of a given worksheet. however, there is another way, embedded in the fields.

		#see CPAN module docs for sheet naming rules. suffice it to say they suck, no excelbad chars, no dupes, and max 32 chars. lame.
		$sheet_name =~ s|: | - |g; #change colon-space to space-dash-space for worksheet names.
		$sheet_name =~ tr/\*\?\/\\/    /; #transliterate all remaining excelBad chars to spaces.
		$sheet_name = substr($sheet_name, 0, 31); #chop the bitch to 31 chars max due to excel lameness.

		my $worksheet = $workbook->add_worksheet($sheet_name);
#		my $worksheet = $workbook->add_worksheet($sheetcount); #was trying to debug weird/gay shit with sheet names.

		unless($sheet_data->{suppress_standard_header}) {
			$worksheet->write_string($vpos, $hpos, $self->{wa}->config('mail_return_name'));
			$worksheet->write_string($vpos, $hpos+2, $report_name); #should appear at top of all report worksheets and be the same on each.
			$worksheet->write_string($vpos, $hpos+4, $now_str);
			$vpos+=2;
		}

		$self->ch_debug(['going to build the excel rows with this field data', $sheet_data]);
		
		my $headings_drawn = 0;

		#print STDERR "about to loop over records in worksheet named '$sheet_name'\n";
		foreach my $search_result (@{$sheet_data->{records}}) {
			if (!$headings_drawn) {
				foreach my $field (@{$search_result->{record_fields}}) {
					if (!$field->{search_show_field}) { next; } #skip to the loo and have a poo. err, just dont draw heading of non showing item.

					#draw the field headings for the details rows
					$worksheet->set_column($hpos, $hpos, $fixed_cell_width);
					$worksheet->write_string($vpos, $hpos, $field->{display_name}, $format_bold);
					$hpos++; #over one cell for next heading
				}
				$vpos++; $hpos = 0; #cr-lf
				$headings_drawn = 1; #yes it is completed now boner head.
			}

			#draw the field values, one line at a time!
			#print STDERR "about to loop over record_fields\n";
			foreach my $field (@{$search_result->{record_fields}}) {
				#print STDERR "writing record field\n";
				if (!$field->{search_show_field}) { next; } #skip to the loo and have a poo. err, just dont draw heading of non showing item.

				#get data format from excel_formats hashref, or fall back to looking at the field itself. 
					#(I have coded a reporting API in AdminBase that will set up the excel_formats, however there is an older report from Education, final course report for general consumption (userlevel 10) to export all the person's scores which is set up to put excel format on the record_fields themselves, as this was the older way of doing it, I dont think I should just stop supporting that since there is no dobj really associated with that report and so it should still have a way to specify the formats!)
				my $data_format = $excel_formats->{$field->{parameter_name}}->{data_format};
				if (!$data_format && $field->{excel_format}) { 
					$data_format = $field->{excel_format};
				}
				
				#k this value_source_override is stupid. need to rewrite this whole shit.
				my $value_source_override = $excel_formats->{$field->{parameter_name}}->{value_source_override}; #currently only applicatble in certain places ... like date fields!

				if ( $data_format eq 'int' || $data_format eq 'float' ) {
					$worksheet->write_number($vpos, $hpos, $field->{db_value_disp});
					#$self->{wa}->debuglog(['wrote a number like:', $field->{db_value_disp} ]);
				} elsif ($data_format eq 'date') {
					my $field_value = ($value_source_override && $value_source_override eq 'disp') ? $field->{db_value_disp} : $field->{db_value}; #probably to use unformatted value here .... i assume.
					$field_value .= 'T'; #append a T to the date in accordance with the Spreadsheet::WriteExcel module
					$worksheet->write_date_time($vpos, $hpos, $field_value, $format_date);
				} elsif ($data_format eq 'date_time') {
					my $field_value = ($value_source_override && $value_source_override eq 'disp') ? $field->{db_value_disp} : $field->{db_value}; #probably to use unformatted value here .... unless told otherwise.
					$field_value =~ s|\s|T|g; #change the seperating space betweend date and time to a 'T'. as in 2005-09-08 11:09:26 becomes 2005-09-08T11:09:26
					$worksheet->write_date_time($vpos, $hpos, $field_value, $format_date_time);
				} else {
					$worksheet->write_string($vpos, $hpos, $field->{db_value_disp}); #draw the value
				}
				$hpos++; #over one cell for next field
			}
			$vpos++; $hpos = 0; #cr-lf
		}

		unless($sheet_data->{suppress_standard_footer}) {
			$vpos+=3; $hpos = 0; #cr(3)-lf
			$worksheet->write_string($vpos, $hpos, $sheet_footer_text);
		}
	}

	if ($args->{return_workbook_data_only}) {
		return { workbook => $workbook, report_name_clean => $report_name, formats => { bold => $format_bold } };
	}

	$workbook->close(); # This is required before we use the scalar
	return \$xls_str;
}
	
sub send_excel_data {
	my $self = shift;
	my $xls_str = shift; #reference.
	my $other_args = shift;
	
	my $filename = $other_args->{report_name}; #without .xls suffix .. thats already conveniently hard coded below.
	$self->{wa}->header_type('header');
	$self->{wa}->header_props(
		-type                  =>'application/vnd.ms-excel',
		'-content-length'      =>length($$xls_str),
		'-content-disposition' => "attachment; filename=\"$filename.xls\"",
	);
	return $$xls_str;
}

1;