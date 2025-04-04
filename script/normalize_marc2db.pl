use Koha::Plugins;
use C4::Context;
my $dbh = C4::Context->dbh;

# my $plugin = Koha::Plugins->new()->GetPlugin('Koha::Plugin::HKS3::NormalizeMARC2DB');
use Koha::Plugin::HKS3::NormalizeMARC2DB;

my $plugin =  Koha::Plugin::HKS3::NormalizeMARC2DB->new();
# $plugin->install();

my $sql = 'select biblionumber from biblio_metadata';
my $sth = $dbh->prepare($sql);
$sth->execute();
my $rows = $sth->fetchall_arrayref( {} ); 
# use Data::Dumper; 
# print Dumper $rows;
foreach my $row (@$rows) {
    printf "%12d \n", $row->{biblionumber};
    $plugin->normalize_biblio($row->{biblionumber});
}
