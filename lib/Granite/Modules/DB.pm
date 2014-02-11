package Granite::Modules::DB;
use Moose;
use Granite::Schema;
use Config::Any;
use Data::Dumper;


#[{
#    'conf/sql_connect_info.json' => {
#        'connect_info' => {
#            'password' => 'system',
#            'options' => {
#                'RaieError' => '1',
#                'PrintError' => '1'
#            },
#            'mysql_enable_utf8' => '1',
#            'dsn' => 'dbi:mysql:granite;host=localhost',
#            'AutoCommit' => '1',
#            'user' => 'granite'
#        }
#    }
#}];

sub init {
    my $cfg = Config::Any->load_files({ files => [ $Granite::cfg->{main}->{sql_config} ], use_ext => 1 });





#    my $schema = Granite::Schema->connect('');
}


1;

