package SpApp::Dispatch;
use base 'CGI::Application::Dispatch';

#see:
#http://search.cpan.org/~wonko/CGI-Application-Dispatch-2.10/lib/CGI/Application/Dispatch.pm
sub dispatch_args {
    return {
        prefix  => 'CMCReg',
        table   => [
            ''                => { app => 'User', rm => '' }, #just let the app determine rm.
            ':rm'             => { app => 'User'},
            'admin/:rm'       => { app => 'Admin' },
        ],
        args_to_new => {
					PARAMS => { '_app_name' => 'cmcreg', '_dispatch_redirect_style' => 1 },
        },
        not_found => '/404.html',
    };
}

1;