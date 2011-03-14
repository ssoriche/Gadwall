#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Mojo;
use Data::Dumper;
use File::Basename 'dirname';
use File::Spec;

use lib join '/', File::Spec->splitdir(dirname(__FILE__)), 'testlib';

use_ok('Wigeon');
use_ok('Wigeon::User');
use_ok('Gadwall::Users');
use_ok('Gadwall::Validator');
use_ok('Gadwall::Util', qw(bcrypt));

# Make sure both imported and non-imported forms of bcrypt work

ok(Gadwall::Util::bcrypt('s3kr1t', '$2a$08$Xk7taVTzcF/jXEXwX0fnYuc/ZRr9jDQSTpGKzJKDU2UsSE7emt3gC') eq '$2a$08$Xk7taVTzcF/jXEXwX0fnYuc/ZRr9jDQSTpGKzJKDU2UsSE7emt3gC', "Bcrypt");
ok(bcrypt('s3kr1t', '$2a$08$Xk7taVTzcF/jXEXwX0fnYuc/ZRr9jDQSTpGKzJKDU2UsSE7emt3gC') eq '$2a$08$Xk7taVTzcF/jXEXwX0fnYuc/ZRr9jDQSTpGKzJKDU2UsSE7emt3gC', "Bcrypt imported");

# Test the bit-twiddling code for role checking in ::User

my $x = bless {roles => 1<<6|1<<3}, "Wigeon::User";
ok($x->has_role('bitcounter'), 'has_role bitcounter');
ok($x->has_role('birdwatcher'), 'has_role birdwatcher');
ok(!$x->has_role('bearfighter'), '!has_role bearfighter');
ok(!$x->has_any_role('admin','cook'), "!has_any_roles admin,cook");
is_deeply([$x->roles()], [qw(birdwatcher bitcounter)], "list roles");
$x = bless {roles => 1}, "Wigeon::User";
ok($x->has_role("admin"), 'has_role admin');
is_deeply([$x->roles()], [qw(admin)], "list roles");

# Test the validator with a complex set of fields and values

my $v = Gadwall::Validator->new({
    a => {},
    b => {validate => qr/^[0-9]+$/},
    c => {validate => qr/^[a-z]+$/, required => 1},
    d => {
        validate => sub{
            my %v = @_;
            return (d => $v{d}-1)
                if $v{d} =~ Gadwall::Validator->patterns('nznumber');
        }},
    e => {validate => qr/^[a-z]+$/},
    f => {multiple => 1, validate => qr/^\d+$/, required => 1},
    g => {multiple => 1, validate => qr/^\d+$/, fields => [qw/G H/]},
    h => {multiple => 1, required => 1},
    i => {fields => [qw/I J/], required => 1},
    j => {fields => [qw/I J/]},
    k => {fields => [qw/J K/]},
    l => {
        fields => qr/^_/,
        validate => sub {
            my %v = @_;
            return (l => $v{_l}.$v{_m});
        }},
    m => { required => 1, validate => Gadwall::Validator->patterns('date') },
    n => { validate => Gadwall::Validator->patterns('numeric2') },
    o => { validate => Gadwall::Validator->patterns('numeric2') },
    p => { validate => Gadwall::Validator->patterns('time') },
    q => { multiple => 1, required => 1 },
    r => { multiple => 1, required => 1, validate => sub {@_} },
    s => { multiple => 1, required => 1, validate => sub {@_} },
    t => { required => 1 }
});
ok($v);

my $r = $v->validate({
    a => 1, b => 'a', c => " ", d => 3, e => "  foo  ", f => [1," 2 "],
    G => [1,2,3], H => 4, I => 3, J => undef, K => "	", _l => "foo",
    _m => "bar", m => "2011-01-33", n => "3.53", o => 13, p => "13:21",
    q => 0, r => 2, s => [0,1], t => 0
}, all => 1);
ok($r eq 'invalid', 'validation status');

is_deeply(
    $v->errors, {
        b => "This field is invalid", c => "This field is required",
        g => "Invalid field specification (#B)",
        h => "This field is required", i => "This field is required",
        m => "This field is invalid"
    }, "validation errors"
);
is_deeply(
    {$v->values}, {
        a => 1, d => 2, e => "foo", f => [1,2], j => 3, l => "foobar",
        n => "3.53", o => 13, p => "13:21", q => [0], r => [2], s => [0,1],
        t => 0
    }, "validated values"
);

# Test the application itself

$ENV{MOJO_MODE} = "testing";
my $client = Mojo::UserAgent->new(app => "Wigeon");
my $t = Test::Mojo->new(app => "Wigeon", ua => $client);
$t->ua->test_server('http');

$t->get_ok('/nonesuch')
    ->status_is(404);

$t->get_ok('/')
    ->status_is(200)
    ->content_type_is('text/plain')
    ->content_is("Quack!");

$t->get_ok('/die')
    ->status_is(302)
    ->content_type_is("text/plain")
    ->content_is("Redirecting to https");

my $loc = $t->tx->res->headers->location();
ok $loc =~ /^https:\/\//, 'redirected to ' . $loc;

$t->get_ok('/startup')
    ->status_is(200)
    ->content_type_is('text/plain')
    ->content_is("Welcome!");

$t->get_ok('/from-template')
    ->status_is(200)
    ->content_type_is("text/html;charset=UTF-8")
    ->text_is('html head title' => 'Foo!')
    ->text_like('html body' => qr/Foo bar!/);

$t->get_ok('/users-only', {"X-Bypass-Security" => 1})
    ->status_is(302)
    ->content_type_is("text/plain")
    ->content_is("Redirecting to https");

$loc = $t->tx->res->headers->location();
ok $loc =~ /^https:\/\//, 'redirected to ' . $loc;

$client = Mojo::UserAgent->new(app => "Wigeon");
$t = Test::Mojo->new(app => "Wigeon", ua => $client);
$t->ua->test_server('https');

$t->get_ok('/die')
    ->status_is(500)
    ->content_type_is('text/html;charset=UTF-8')
    ->content_is("ouch\n");

$t->get_ok('/users-only')
    ->status_is(403)
    ->content_type_is("text/html;charset=UTF-8")
    ->text_is('html body form label', 'Login:');

my $token = $t->tx->res->dom('input[name="__token"]')->[0]->attrs->{value};
ok($token, "CSRF token");

$t->post_form_ok('/login', {__login => "dummy", __passwd => "user", __token => $token})
    ->status_is(200)
    ->content_type_is("text/html;charset=UTF-8")
    ->text_like('#msg', qr/Incorrect username or password/);

$t->post_form_ok('/login', {__login => "bar", __passwd => "s3kr1t", __token => $token})
    ->status_is(302)
    ->content_type_is("text/plain")
    ->content_is("Redirecting to /users-only");

$t->get_ok('/my-token')
    ->status_is(200)
    ->content_type_is("text/plain");

my $newtoken = $t->tx->res->body;
ok($newtoken ne $token, "CSRF token changed");
$token = $newtoken;

$t->get_ok('/users-only')
    ->status_is(200)
    ->content_type_is("text/plain")
    ->content_is("This is not a bar");

$t->get_ok('/my-email')
    ->status_is(200)
    ->content_type_is("text/plain")
    ->content_is('ams@toroid.org');

$t->get_ok('/my-roles')
    ->status_is(200)
    ->content_type_is("text/plain")
    ->content_is("birdwatcher:bearfighter:bitcounter");

$t->get_ok('/birdwatchers-only')
    ->status_is(200)
    ->content_type_is("text/plain")
    ->content_is("This is not a baz");

$t->post_form_ok('/users/create', {
        email => 'foo@example.org', pass1 => 's3kr1t', pass2 => 's3kr1t',
        is_admin => 1, is_backstabber => 1, __token => $token
    })
    ->status_is(200)
    ->content_type_is("application/json")
    ->json_content_is({status => "ok", message => "User created"});

$t->get_ok('/users/list?id=2')
    ->status_is(200)
    ->content_type_is("application/json")
    ->json_content_is({
            status => "ok",
            table => { name => "users", key => "user_id", page => 1, limit => 0, total => 1 },
            users => [{
                user_id=>2, email=>'foo@example.org', login=>undef,
                is_backstabber=>1, is_admin=>1,is_active=>1,
                roles => [qw/Administrator backstabber/]
            }]
        });

$t->post_form_ok('/su', {user_id => 2, __token => $token})
    ->status_is(302)
    ->content_type_is("text/plain")
    ->content_is("Redirecting to /");

$t->get_ok('/my-email')
    ->status_is(200)
    ->content_type_is("text/plain")
    ->content_is('foo@example.org');

$t->get_ok('/my-roles')
    ->status_is(200)
    ->content_type_is("text/plain")
    ->content_is("admin:backstabber");

$t->get_ok('/birdwatchers-only')
    ->status_is(403)
    ->content_type_is("text/plain")
    ->content_is("Permission denied");

$t->get_ok('/logout')
    ->status_is(302)
    ->content_type_is("text/plain")
    ->content_is("Redirecting to /");

$t->get_ok('/my-email')
    ->status_is(200)
    ->content_type_is("text/plain")
    ->content_is('ams@toroid.org');

$t->get_ok('/my-roles')
    ->status_is(200)
    ->content_type_is("text/plain")
    ->content_is("birdwatcher:bearfighter:bitcounter");

$t->get_ok('/birdwatchers-only')
    ->status_is(200)
    ->content_type_is("text/plain")
    ->content_is("This is not a baz");

$t->get_ok('/never')
    ->status_is(403)
    ->content_type_is("text/plain")
    ->content_is("Permission denied");

$t->post_form_ok('/users/1/password', {
        password => "s3kr1t", pass1 => "secret", pass2 => "secret",
        __token => $token
    })
    ->status_is(200)
    ->content_type_is("application/json")
    ->json_content_is({status => "ok", message => "Password changed"});

$t->get_ok('/logout')
    ->status_is(200)
    ->content_type_is("text/html;charset=UTF-8")
    ->text_like('#msg', qr/You have been logged out/);

$t->get_ok('/users-only')
    ->status_is(403)
    ->content_type_is("text/html;charset=UTF-8")
    ->text_is('html body form label', 'Login:');

$newtoken = $t->tx->res->dom('input[name="__token"]')->[0]->attrs->{value};
ok($newtoken ne $token, "New CSRF token");

$t->post_form_ok('/login', {__login => "bar", __passwd => "s3kr1t", __token => $token})
    ->status_is(403)
    ->content_type_is("text/plain")
    ->content_is("Permission denied");

$token = $newtoken;

$t->post_form_ok('/login', {__login => "bar", __passwd => "s3kr1t", __token => $token})
    ->status_is(200)
    ->content_type_is("text/html;charset=UTF-8")
    ->text_like('#msg', qr/Incorrect username or password/);

$t->post_form_ok('/login', {__login => "bar", __passwd => "secret", __token => $token})
    ->status_is(302)
    ->content_type_is("text/plain")
    ->content_is("Redirecting to /users-only");

$t->get_ok('/my-token')
    ->status_is(200)
    ->content_type_is("text/plain");

$newtoken = $t->tx->res->body;
ok($newtoken ne $token, "CSRF token changed");
$token = $newtoken;

$t->get_ok('/sprockets')
    ->status_is(200)
    ->content_type_is('application/json')
    ->json_content_is({
            status => "ok",
            table => { name => "sprockets", key => "sprocket_id", page => 1, limit => 0, total => 3 },
            sprockets => [
                {colour => "blue", teeth => 256, sprocket_name => "c", sprocket_id => 3},
                {colour => "green", teeth => 64, sprocket_name => "b", sprocket_id => 2},
                {colour => "red", teeth => 42, sprocket_name => "a", sprocket_id => 1}
            ]
        });

$t->get_ok('/sprockets/list?id=1')
    ->status_is(200)
    ->content_type_is('application/json')
    ->json_content_is({
            status => "ok",
            table => { name => "sprockets", key => "sprocket_id", page => 1, limit => 0, total => 1 },
            sprockets => [
                {colour => "red", teeth => 42, sprocket_name => "a", sprocket_id => 1}
            ]
        });

$t->post_form_ok('/sprockets/create', {sprocket_name => "d", colour => "red", teeth => 128, __token => $token})
    ->status_is(200)
    ->content_type_is('application/json')
    ->content_is(qq!{"status":"ok","message":"Sprocket created"}!);

$t->get_ok('/sprockets/list?id=4')
    ->status_is(200)
    ->content_type_is('application/json')
    ->json_content_is({
            status => "ok",
            table => { name => "sprockets", key => "sprocket_id", page => 1, limit => 0, total => 1 },
            sprockets => [
                {colour => "red", teeth => 128, sprocket_name => "d", sprocket_id => 4}
            ]
        });

$t->post_form_ok('/sprockets/4/update', {sprocket_name => "q", colour => "black", __token => $token})
    ->status_is(200)
    ->content_type_is('application/json')
    ->content_is(qq!{"errors":{"colour":"This field is invalid"},"status":"error","message":"Please correct the following errors"}!);

$t->post_form_ok('/sprockets/4/update', {sprocket_name => "e", colour => "blue", teeth => 128, __token => $token})
    ->status_is(200)
    ->content_type_is('application/json')
    ->content_is(qq!{"status":"ok","message":"Sprocket updated"}!);

$t->get_ok('/sprockets/list?id=4')
    ->status_is(200)
    ->content_type_is('application/json')
    ->json_content_is({
            status => "ok",
            table => { name => "sprockets", key => "sprocket_id", page => 1, limit => 0, total => 1 },
            sprockets => [
                {colour => "blue", teeth => 128, sprocket_name => "e", sprocket_id => 4}
            ]
        });

$t->get_ok('/sprockets/list?p=2;n=2')
    ->status_is(200)
    ->content_type_is('application/json')
    ->json_content_is({
            status => "ok",
            table => { name => "sprockets", key => "sprocket_id", page => 2, limit => 2, total => 4 },
            sprockets => [
                {colour => "green", teeth => 64, sprocket_name => "b", sprocket_id => 2},
                {colour => "red", teeth => 42, sprocket_name => "a", sprocket_id => 1}
            ]
        });

$t->post_form_ok('/sprockets/4/delete', {__token => $token})
    ->status_is(200)
    ->content_type_is('application/json')
    ->content_is(qq!{"status":"ok","message":"Sprocket deleted"}!);

$t->get_ok('/sprockets/list?id=4')
    ->status_is(200)
    ->content_type_is('application/json')
    ->json_content_is({
            status => "ok",
            table => { name => "sprockets", key => "sprocket_id", page => 1, limit => 0, total => 0 },
            sprockets => []
        });

$t->get_ok('/widgets/sprocket_colours')
    ->status_is(200)
    ->content_type_is('text/plain')
    ->content_is("red green");

$t->get_ok('/sprockets/approximate_blueness?sprocket_id=1')
    ->status_is(200)
    ->content_type_is('text/plain')
    ->content_is("not blue");

$t->get_ok('/sprockets/approximate_blueness?sprocket_id=2')
    ->status_is(200)
    ->content_type_is('text/plain')
    ->content_is("maybe blue");

$t->get_ok('/widgets/sprocket_redness?sprocket_id=1')
    ->status_is(200)
    ->content_type_is('text/plain')
    ->content_is("red");

$t->get_ok('/widgets/sprocket_redness?sprocket_id=2')
    ->status_is(200)
    ->content_type_is('text/plain')
    ->content_is("not red");

$t->get_ok('/logout')
    ->status_is(200)
    ->content_type_is("text/html;charset=UTF-8")
    ->text_like('#msg', qr/You have been logged out/);

$t->get_ok('/shutdown')
    ->status_is(200)
    ->content_type_is('text/plain')
    ->content_is("Goodbye!");

done_testing();
