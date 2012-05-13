#=============================================
# app_cookie_verification
# this is just to track how many times we redirect in the cookie check trap for an IP. its a little silly to think that that a client couldnt redirect with query params, but we gotta be sure. dont want to end up ever with someone trapped in an infinite redirect!
package SpApp::DataObjects::CookieVerification;
use base "SpApp::DataObj";
use strict;

sub _init_fields {
	my $self = shift;
	my $fields = [
		{ db_field_name => 'app_cookie_verification.ip_address',  parameter_name => 'ip_address' },
		{ db_field_name => 'app_cookie_verification.redir_count', parameter_name => 'redir_count'},
	];
	
	return $fields;
}

sub _init_form {
	return { name => 'APP_COOKIE_VERIFICATION', no_db_form_spec => 1 };
}

1;

#=============================================
# app_listoption -- adding for a temp means by which to produce display values for multiselect cboxes.
package SpApp::DataObjects::AppListoption;
use base "SpApp::DataObj";
use strict;
sub _init_fields {
	return [
		{ db_field_name => 'app_listoption.parameter_name', parameter_name => 'param',     db_field_type => 'vc_nn_b',  edit_default_value => '', db_index => 1 },
		{ db_field_name => 'app_listoption.separator',      parameter_name => 'separator', db_field_type => 'int_nn_0', edit_default_value => 0 },
		{ db_field_name => 'app_listoption.value',          parameter_name => 'value', db_index => 1 },
		{ db_field_name => 'app_listoption.display_value',  parameter_name => 'display_value', db_field_type => 'vc_n' },
		{ db_field_name => 'app_listoption.display_order',  parameter_name => 'display_order', db_field_type => 'int_n' },
		{ db_field_name => 'app_listoption.disabled',       parameter_name => 'disabled', db_field_type => 'int_nn_0', edit_default_value => 0 },
	];
}
sub _init_form {
	return { name => 'AppListoption', no_db_form_spec => 1, default_sort => '{"parameter_name":"display_order"}' };
}
1;

#=============================================
# app_image_upload - thinking a db table to track all images uploaded would be useful, could do things like obtain an ID to use in a non-stupid-tied-filehandle-based way.
package SpApp::DataObjects::AppImageUpload;
use base "SpApp::DataObj";
use strict;
sub _init_fields {
	return [
		{ db_field_name => 'app_image_upload.id',              db_field_type => 'int_nn_0', },
		{ db_field_name => 'app_image_upload.upload_filename', db_field_type => 'vc_n', },
		{ db_field_name => 'app_image_upload.image_dir',       db_field_type => 'vc_n', },
	];
}
sub _init_form {
	return { name => 'AppImageUpload', no_db_form_spec => 1, fieldname_part_params => 1 };
}
1;

#=============================================
# app_image_upload - thinking a db table to track all images uploaded would be useful, could do things like obtain an ID to use in a non-stupid-tied-filehandle-based way.
package SpApp::DataObjects::AppFileUpload;
use base "SpApp::DataObj";
use strict;
sub _init_fields {
	return [
		{ db_field_name => 'app_file_upload.id',              db_field_type => 'int_nn_0', },
		{ db_field_name => 'app_file_upload.upload_filename', db_field_type => 'vc_n', },
		{ db_field_name => 'app_file_upload.file_dir',        db_field_type => 'vc_n', },
	];
}
sub _init_form {
	return { name => 'AppFileUpload', no_db_form_spec => 1, fieldname_part_params => 1 };
}
1;

#=============================================
# app_interface_string - I just want some easy access to this -- the Strings.pm currently uses some direct SQL.
package SpApp::DataObjects::AppInterfaceString;
use base "SpApp::DataObj";
use strict;
sub _init_fields {
	return [
		{ db_field_name => 'app_interface_string.id', },
		{ db_field_name => 'app_interface_string.stringname',   },
		{ db_field_name => 'app_interface_string.render_with_htc',   },
		{ db_field_name => 'app_interface_string.text_en',   },
		{ db_field_name => 'app_interface_string.text_fr',   },
		{ db_field_name => 'app_interface_string.text_zh',  parameter_name => 'text_zh_chopped', search_result_options => { maxchars => 5 } }, #just playin with maxchars on utf fields, want to make sure it works right for multi-byte.
		{ db_field_name => 'app_interface_string.text_zh',}, 
	];
}
sub _init_form {
	return { name => 'AppInterfaceString', no_db_form_spec => 1, fieldname_part_params => 1 };
}
1;

#=============================================
# app_log - As of 2007-12-17 (waaay too late) we are finally not going to think about reading form fields from the DB for an AppLog data object.
package SpApp::DataObjects::AppLog;
use base "SpApp::DataObj";
use strict;
sub _init_fields {
	return [
		{ db_field_name => 'app_log.app_name',},
		{ db_field_name => 'app_log.user_table',},
		{ db_field_name => 'app_log.user_id',},
		{ db_field_name => 'app_log.action',},
		{ db_field_name => 'app_log.detail',},
	];
}
sub _init_form {
	return { name => 'AppLog', no_db_form_spec => 1, fieldname_part_params => 1 };
}
1;