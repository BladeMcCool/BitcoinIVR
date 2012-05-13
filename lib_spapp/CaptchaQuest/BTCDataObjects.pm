package CaptchaQuest::BTCDataObj::BTCSysUser;
use base "SpApp::DataObj";
use strict;
sub _init_fields {
	return [
		{ db_field_name => 'btcsys_user.userid',   db_field_type => 'int_us_nn_0', search_query_options => { keyword => 1 }, db_index => 1 }, 
		{ db_field_name => 'btcsys_user.pin',      db_field_type => 'int_us_nn_0', search_query_options => { keyword => 1 }, db_index => 1  }, 
		#{ db_field_name => 'btcsys_user.pin',      db_field_type => 'vc_n', search_query_options => { keyword => 1 }, },  #maybe try some whizbang crypto shit for lulz?
		{ db_field_name => 'btcsys_user.btc_address', db_field_type => 'vc_n', search_query_options => { keyword => 1 }, db_index => 1 }, 
		{ db_field_name => 'btcsys_user.receive_sms_from', db_field_type => 'vc_n', search_query_options => { keyword => 1 }, db_index => 1 }, 
		{ db_field_name => 'btcsys_user.enabled',    db_field_type => 'int_nn_0', edit_default_value => 1, edit_fieldtype => 'SINGLESELECT_DROPDOWN', sql_value_lookup => 'yes_no', search_query_options => { dropdown => 1 }, }, 
	];
}
sub _init_form {
	return { name => 'BTCSysUser', no_db_form_spec => 1, fieldname_part_params => 1 };
}
1;

package CaptchaQuest::BTCDataObj::BTCSysAddressbook;
use base "SpApp::DataObj";
use strict;
sub _init_fields {
	return [
		{ db_field_name => 'btcsys_addressbook.userid',        db_field_type => 'int_us_nn_0', search_query_options => { keyword => 1 }, db_index => 1 }, 
		{ db_field_name => 'btcsys_addressbook.syscode',       db_field_type => 'int_us_n',    search_query_options => { keyword => 1 }, db_index => 1  }, 
		{ db_field_name => 'btcsys_addressbook.btc_address',   db_field_type => 'vc_n', search_query_options => { keyword => 1 }, db_index => 1 }, 
		{ db_field_name => 'btcsys_addressbook.display_order', db_field_type => 'int_us_nn_0', search_query_options => { keyword => 1 }, }, 
		{ db_field_name => 'btcsys_addressbook.enabled',       db_field_type => 'int_nn_0', edit_default_value => 1, edit_fieldtype => 'SINGLESELECT_DROPDOWN', sql_value_lookup => 'yes_no', search_query_options => { dropdown => 1 }, }, 
	];
}
sub _init_form {
	return { name => 'BTCSysAddressbook', no_db_form_spec => 1, fieldname_part_params => 1 };
}
1;

#just storing these so we know to skip them as having been already vetted for being junk. so we dont bother with them again. due to how the rss sms thing works we'll see them over and over. wnat to not care.
package CaptchaQuest::BTCDataObj::BTCSysSMSJunk;
use base "SpApp::DataObj";
use strict;
sub _init_fields {
	return [
		{ db_field_name => 'btcsys_smsjunk.userid',        db_field_type => 'int_us_nn_0', search_query_options => { keyword => 1 }, db_index => 1 }, 
		{ db_field_name => 'btcsys_smsjunk.btc_address',   db_field_type => 'vc_n', search_query_options => { keyword => 1 }, db_index => 1 }, 
	];
}
sub _init_form {
	return { name => 'BTCSysSMSJunk', no_db_form_spec => 1, fieldname_part_params => 1 };
}
1;
