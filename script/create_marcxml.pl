use Koha::Plugins;
use C4::Context;
use Try::Tiny qw(catch try);
use XML::SemanticDiff;
use Path::Tiny;

my $dbh = C4::Context->dbh;

# my $plugin = Koha::Plugins->new()->GetPlugin('Koha::Plugin::HKS3::NormalizeMARC2DB');
use Koha::Plugin::HKS3::NormalizeMARC2DB;

my $plugin =  Koha::Plugin::HKS3::NormalizeMARC2DB->new();
# $plugin->install();

my $sql = 'select biblionumber, metadata from biblio_metadata';
# my $sql = 'select biblionumber, metadata from biblio_metadata where biblionumber = 11';
my $sth = $dbh->prepare($sql);
$sth->execute();
my $rows = $sth->fetchall_arrayref( {} ); 
# use Data::Dumper; 
# print Dumper $rows;
my $xml;
my $diff = XML::SemanticDiff->new();
foreach my $row (@$rows) {
    printf "%12d \n", $row->{biblionumber};
    my ($record_id) = $dbh->selectrow_array('select id from nm2db_records where biblionumber = ?', undef, $biblionumber);
    try {
        $xml = $plugin->generate_marcxml($record_id);
    } catch {
        warn $_;
    };
#    path("created-$biblionumbner.xml")->spew_utf8($xml);
#    path("metadata-$biblionumbner.xml")->spew_utf8($row->{metadata});
    foreach my $change ($diff->compare($xml, $row->{metadata} )) {
        print "$change->{message} in context $change->{context}\n";
    }
}
