package Gadwall::Users;

use strict;
use warnings;

use Gadwall::User;

use base 'Gadwall::Table';

sub columns {
    return (
        login => {},
        email => {
            required => 1,
        },
        password => {
            fields => [qw/pass1 pass2/],
            required => 1,
            validate => sub {
            },
            error => "Please enter the same password twice"
        },
        roles => {
            fields => qr/^is_[a-z]+$/,
            validate => sub {
                my (%set) = @_;

                my $i = 31;
                my @roles = (0)x32;
                foreach my $r (Gadwall::User->roles()) {
                    if ($set{"is_$r"}) {
                        $roles[$i] = 1;
                    }
                    $i--;
                }

                return (roles => join "", @roles);
            }
        }
    );
}

sub rowclass {
    "Gadwall::User"
}

1;
