package Perinci::Sub::To::CLIDocData;

our $DATE = '2014-12-09'; # DATE
our $VERSION = '0.14'; # VERSION

use 5.010001;
use strict;
use warnings;

use Perinci::Object;
use Perinci::Sub::Util qw(err);

our %SPEC;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(gen_cli_doc_data_from_meta);

sub _has_cats {
    for my $spec (@{ $_[0] }) {
        for (@{ $spec->{tags} // [] }) {
            my $tag_name = ref($_) ? $_->{name} : $_;
            if ($tag_name =~ /^category:/) {
                return 1;
            }
        }
    }
    0;
}

sub _add_category_from_spec {
    my ($thing, $spec, $noun, $has_cats) = @_;
    my $cat;
    my $raw_cat = '';
    for (@{ $spec->{tags} // [] }) {
        my $tag_name = ref($_) ? $_->{name} : $_;
        if ($tag_name =~ /^category:(.+)/) {
            $raw_cat = $1;
            $cat = ucfirst($1) . " " . $noun;
            last;
        }
    }
    $cat //= $has_cats ? "General $noun" : ucfirst($noun); # XXX translatable?
    $thing->{category} = $cat;
    $thing->{raw_category} = $raw_cat;
}

sub _add_default_from_arg_spec {
    my ($opt, $arg_spec) = @_;
    if (exists $arg_spec->{default}) {
        $opt->{default} = $arg_spec->{default};
    } elsif ($arg_spec->{schema} && exists($arg_spec->{schema}[1]{default})) {
        $opt->{default} = $arg_spec->{schema}[1]{default};
    }
}

sub _dash_prefix {
    length($_[0]) > 1 ? "--$_[0]" : "-$_[0]";
}

sub _fmt_opt {
    my $spec = shift;
    my @ospecs = @_;
    my @res;
    my $i = 0;
    for my $ospec (@ospecs) {
        my $j = 0;
        my $parsed = $ospec->{parsed};
        for (@{ $parsed->{opts} }) {
            my $opt = _dash_prefix($_);
            if ($i==0 && $j==0) {
                if ($parsed->{type}) {
                    if ($spec->{'x.schema.entity'}) {
                        $opt .= "=".$spec->{'x.schema.entity'};
                    } else {
                        $opt .= "=$parsed->{type}";
                    }
                }
                # mark required option with a '*'
                $opt .= "*" if $spec->{req} && !$ospec->{is_base64} &&
                    !$ospec->{is_json} && !$ospec->{is_yaml};
            }
            push @res, $opt;
            $j++;
        }
        $i++;
    }
    join ", ", @res;
}

$SPEC{gen_cli_doc_data_from_meta} = {
    v => 1.1,
    summary => 'From Rinci function metadata, generate structure convenient '.
        'for producing CLI documentation (help/usage/POD)',
    description => <<'_',

This function calls `Perinci::Sub::GetArgs::Argv`'s
`gen_getopt_long_spec_from_meta()` (or receive its result as an argument, if
passed, to avoid calling the function twice) and post-processes it: produce
command usage line, format the options, include information from metadata, group
the options by category. It also selects examples in the `examples` property
which are applicable to CLI environment and format them.

The resulting data structure is convenient to use when one wants to produce a
documentation for CLI program (including help/usage message and POD).

_
    args => {
        meta => {
            schema => 'hash*', # XXX rifunc
            req => 1,
            pos => 0,
        },
        meta_is_normalized => {
            schema => 'bool*',
        },
        common_opts => {
            summary => 'Will be passed to gen_getopt_long_spec_from_meta()',
            schema  => 'hash*',
        },
        ggls_res => {
            summary => 'Full result from gen_getopt_long_spec_from_meta()',
            schema  => 'array*', # XXX envres
            description => <<'_',

If you already call `Perinci::Sub::GetArgs::Argv`'s
`gen_getopt_long_spec_from_meta()`, you can pass the _full_ enveloped result
here, to avoid calculating twice. What will be useful for the function is the
extra result in result metadata (`func.*` keys in `$res->[3]` hash).

_
        },
        per_arg_json => {
            schema => 'bool',
            summary => 'Pass per_arg_json=1 to Perinci::Sub::GetArgs::Argv',
        },
        per_arg_yaml => {
            schema => 'bool',
            summary => 'Pass per_arg_json=1 to Perinci::Sub::GetArgs::Argv',
        },
        lang => {
            schema => 'str*',
        },
    },
    result => {
        schema => 'hash*',
    },
};
sub gen_cli_doc_data_from_meta {
    my %args = @_;

    my $lang = $args{lang};
    my $meta = $args{meta} or return [400, 'Please specify meta'];
    my $common_opts = $args{common_opts};
    unless ($args{meta_is_normalized}) {
        require Perinci::Sub::Normalize;
        $meta = Perinci::Sub::Normalize::normalize_function_metadata($meta);
    }
    my $ggls_res = $args{ggls_res} // do {
        require Perinci::Sub::GetArgs::Argv;
        Perinci::Sub::GetArgs::Argv::gen_getopt_long_spec_from_meta(
            meta=>$meta, meta_is_normalized=>1, common_opts=>$common_opts,
            per_arg_json => $args{per_arg_json},
            per_arg_yaml => $args{per_arg_yaml},
        );
    };
    $ggls_res->[0] == 200 or return $ggls_res;

    my $args_prop = $meta->{args} // {};
    my $clidocdata = {};

    # generate usage line
    {
        my @args;
        my %args_prop = %$args_prop; # copy because we want to iterate & delete
        my $max_pos = -1;
        for (values %args_prop) {
            $max_pos = $_->{pos}
                if defined($_->{pos}) && $_->{pos} > $max_pos;
        }
        my $pos = 0;
        while ($pos <= $max_pos) {
            my ($arg, $arg_spec);
            for (keys %args_prop) {
                $arg_spec = $args_prop{$_};
                if (defined($arg_spec->{pos}) && $arg_spec->{pos}==$pos) {
                    $arg = $_;
                    last;
                }
            }
            $pos++;
            next unless defined($arg);
            if ($arg_spec->{req}) {
                push @args, "<$arg>";
            } else {
                push @args, "[$arg]";
            }
            push @args, "..." if $arg_spec->{greedy};
            delete $args_prop{$arg};
        }
        unshift @args, "[options]" if keys(%args_prop) || keys(%$common_opts); # XXX translatable?
        $clidocdata->{usage_line} = "[[prog]]".
            (@args ? " ".join(" ", @args) : "");
    }

    # generate list of options
    my %opts;
    {
        my $has_cats = _has_cats([values %$args_prop]);

        my $ospecs = $ggls_res->[3]{'func.specmeta'};
        # separate groupable aliases because they will be merged with the
        # argument options
        my (@k, @k_aliases);
      OSPEC1:
        for (sort keys %$ospecs) {
            my $ospec = $ospecs->{$_};
            {
                last unless $ospec->{is_alias};
                next if $ospec->{is_code};
                my $arg_spec = $args_prop->{$ospec->{arg}};
                my $alias_spec = $arg_spec->{cmdline_aliases}{$ospec->{alias}};
                next if $alias_spec->{summary};
                push @k_aliases, $_;
                next OSPEC1;
            }
            push @k, $_;
        }

        my %negs; # key=arg, only show one negation form for each arg option

      OSPEC2:
        while (@k) {
            my $k = shift @k;
            my $ospec = $ospecs->{$k};
            my $ok;

            if ($ospec->{is_alias} || defined($ospec->{arg})) {
                my $arg_spec;
                my $alias_spec;
                my $opt;

                if ($ospec->{is_alias}) {
                    # non-groupable alias

                    $arg_spec = $args_prop->{ $ospec->{arg} };
                    $alias_spec = $arg_spec->{cmdline_aliases}{$ospec->{alias}};
                    my $rimeta = rimeta($alias_spec);
                    $ok = _fmt_opt($arg_spec, $ospec);
                    $opt = {
                        opt_parsed => $ospec->{parsed},
                        orig_opt => $k,
                        is_alias => 1,
                        alias_for => $ospec->{alias_for},
                        summary => $rimeta->langprop({lang=>$lang}, 'summary') //
                            "Alias for "._dash_prefix($ospec->{parsed}{opts}[0]),
                        description =>
                        $rimeta->langprop({lang=>$lang}, 'description'),
                    };
                } else {
                    # an option for argument

                    $arg_spec = $args_prop->{$ospec->{arg}};
                    my $rimeta = rimeta($arg_spec);
                    $opt = {
                        opt_parsed => $ospec->{parsed},
                        orig_opt => $k,
                    };

                    # for bool, only display either the positive (e.g. --bool) or
                    # the negative (e.g. --nobool) depending on the default
                    if (defined($ospec->{is_neg})) {
                        my $default = $arg_spec->{default} //
                            $arg_spec->{schema}[1]{default};
                        next OSPEC2 if  $default && !$ospec->{is_neg};
                        next OSPEC2 if !$default &&  $ospec->{is_neg};
                        if ($ospec->{is_neg}) {
                            next OSPEC2 if $negs{$ospec->{arg}}++;
                        }
                    }

                    if ($ospec->{is_neg}) {
                        # for negative option, use negative summary instead of
                        # regular (positive sentence) summary
                        $opt->{summary} =
                            $rimeta->langprop({lang=>$lang}, 'summary.alt.bool.not');
                    } elsif (($ospec->{parsed}{type}//'') eq 's@') {
                        # for array of string that can be specified via multiple
                        # --opt, show singular version of summary if available.
                        # otherwise show regular summary.
                        $opt->{summary} =
                            $rimeta->langprop({lang=>$lang}, 'summary.alt.numnoun.singular') //
                                $rimeta->langprop({lang=>$lang}, 'summary');
                    } else {
                        $opt->{summary} =
                            $rimeta->langprop({lang=>$lang}, 'summary');
                    }
                    $opt->{description} =
                        $rimeta->langprop({lang=>$lang}, 'description');

                    # find aliases that can be grouped together with this option
                    my @aliases;
                    my $j = $#k_aliases;
                    while ($j >= 0) {
                        my $aospec = $ospecs->{ $k_aliases[$j] };
                        {
                            last unless $aospec->{arg} eq $ospec->{arg};
                            push @aliases, $aospec;
                            splice @k_aliases, $j, 1;
                        }
                        $j--;
                    }

                    $ok = _fmt_opt($arg_spec, $ospec, @aliases);
                }

                $opt->{arg_spec} = $arg_spec;
                $opt->{alias_spec} = $alias_spec if $alias_spec;

                # include keys from func.specmeta
                for (qw/arg fqarg is_base64 is_json is_yaml/) {
                    $opt->{$_} = $ospec->{$_} if defined $ospec->{$_};
                }

                # include keys from arg_spec
                for (qw/req pos greedy is_password links tags/) {
                    $opt->{$_} = $arg_spec->{$_} if defined $arg_spec->{$_};
                }

                _add_category_from_spec($opt, $arg_spec, "options", $has_cats);
                _add_default_from_arg_spec($opt, $arg_spec);

                $opts{$ok} = $opt;

            } else {
                # option from common_opts

                $ok = _fmt_opt($common_opts, $ospec);
                my $co = $common_opts->{$ospec->{common_opt}};
                my $rimeta = rimeta($co);
                $opts{$ok} = {
                    opt_parsed => $ospec->{parsed},
                    orig_opt => $k,
                    category => $has_cats ? "General options" : "Options", # XXX translatable?
                    summary => $rimeta->langprop({lang=>$lang}, 'summary'),
                    (schema => $co->{schema}) x !!$co->{schema},
                    description =>
                        $rimeta->langprop({lang=>$lang}, 'description'),
                };

            }
        }

        # link ungrouped alias to its main opt
      OPT1:
        for my $k (keys %opts) {
            my $opt = $opts{$k};
            next unless $opt->{is_alias} || $opt->{is_base64} ||
                $opt->{is_json} || $opt->{is_yaml};
            for my $k2 (keys %opts) {
                my $arg_opt = $opts{$k2};
                next if $arg_opt->{is_alias} || $arg_opt->{is_base64} ||
                    $arg_opt->{is_json} || $arg_opt->{is_yaml};
                next unless defined($arg_opt->{arg}) &&
                    $arg_opt->{arg} eq $opt->{arg};
                $opt->{main_opt} = $k2;
                next OPT1;
            }
        }

    }
    $clidocdata->{opts} = \%opts;

    # filter and format examples
    my @examples;
    {
        my $examples = $meta->{examples} // [];
        my $has_cats = _has_cats($examples);

        for my $eg (@$examples) {
            my $rimeta = rimeta($eg);
            my $argv;
            my $cmdline;
            if (defined($eg->{src})) {
                # we only show shell command examples
                if ($eg->{src_plang} =~ /^(sh|bash)$/) {
                    $cmdline = $eg->{src};
                } else {
                    next;
                }
            } else {
                require String::ShellQuote;
                if ($eg->{argv}) {
                    $argv = $eg->{argv};
                } else {
                    require Perinci::Sub::ConvertArgs::Argv;
                    my $res = Perinci::Sub::ConvertArgs::Argv::convert_args_to_argv(
                        args => $eg->{args}, meta => $meta);
                    return err($res, 500, "Can't convert args to argv")
                        unless $res->[0] == 200;
                    $argv = $res->[2];
                }
                $cmdline = "[[prog]]";
                for my $arg (@$argv) {
                    $arg = String::ShellQuote::shell_quote($arg);
                    $cmdline .= " $arg"; # XXX markup with color?
                }
            }
            my $egdata = {
                cmdline      => $cmdline,
                summary      => $rimeta->langprop({lang=>$lang}, 'summary'),
                description  => $rimeta->langprop({lang=>$lang}, 'description'),
                example_spec => $eg,
            };
            # XXX show result from $eg
            _add_category_from_spec($egdata, $eg, "examples", $has_cats);
            push @examples, $egdata;
        }
    }
    $clidocdata->{examples} = \@examples;

    [200, "OK", $clidocdata];
}

1;
# ABSTRACT: Generate data structure convenient for producing CLI help/usage

__END__

=pod

=encoding UTF-8

=head1 NAME

Perinci::Sub::To::CLIDocData - Generate data structure convenient for producing CLI help/usage

=head1 VERSION

This document describes version 0.14 of Perinci::Sub::To::CLIDocData (from Perl distribution Perinci-Sub-To-CLIDocData), released on 2014-12-09.

=head1 SYNOPSIS

 use Perinci::Sub::To::CLIDocData qw(gen_cli_doc_data_from_meta);
 my $clidocdata = gen_cli_doc_data_from_meta(meta => $meta);

Sample function metadata (C<$meta>):

 {
   args => {
     bool1 => {
                cmdline_aliases => { z => { summary => "This is summary for option `-z`" } },
                schema => "bool",
                summary => "Another bool option",
                tags => ["category:cat1"],
              },
     flag1 => {
                cmdline_aliases => { f => {} },
                schema => ["bool", "is", 1],
                tags => ["category:cat1"],
              },
     str1  => {
                pos => 0,
                req => 1,
                schema => "str*",
                summary => "A required option as well as positional argument",
              },
   },
   examples => [
     {
       argv    => ["a value", "--bool1"],
       summary => "Summary for an example",
       test    => 0,
     },
   ],
   summary => "Function summary",
   v => 1.1,
 }

Sample result:

 do {
   my $a = [
     200,
     "OK",
     {
       examples => [
         {
           category     => "Examples",
           cmdline      => "[[prog]] 'a value' --bool1",
           description  => undef,
           example_spec => {
                             argv    => ["'a value'", "--bool1"],
                             summary => "Summary for an example",
                             test    => 0,
                           },
           raw_category => "",
           summary      => "Summary for an example",
         },
       ],
       opts => {
         "--bool1" => {
           arg          => "bool1",
           arg_spec     => {
                             cmdline_aliases => { z => { summary => "This is summary for option `-z`" } },
                             schema => ["bool", {}, {}],
                             summary => "Another bool option",
                             tags => ["category:cat1"],
                           },
           category     => "Cat1 options",
           description  => undef,
           fqarg        => "bool1",
           opt_parsed   => { opts => ["bool1"] },
           orig_opt     => "bool1",
           raw_category => "cat1",
           summary      => "Another bool option",
           tags         => 'fix',
         },
         "--flag1, -f" => {
           arg          => "flag1",
           arg_spec     => {
                             cmdline_aliases => { f => {} },
                             schema => ["bool", { is => 1 }, {}],
                             tags => ["category:cat1"],
                           },
           category     => "Cat1 options",
           description  => undef,
           fqarg        => "flag1",
           opt_parsed   => { opts => ["flag1"] },
           orig_opt     => "flag1",
           raw_category => "cat1",
           summary      => undef,
           tags         => 'fix',
         },
         "--str1=s*" => {
           arg => "str1",
           arg_spec => {
             pos => 0,
             req => 1,
             schema => ["str", { req => 1 }, {}],
             summary => "A required option as well as positional argument",
           },
           category => "General options",
           description => undef,
           fqarg => "str1",
           opt_parsed => { desttype => "", opts => ["str1"], type => "s" },
           orig_opt => "str1=s",
           pos => 0,
           raw_category => "",
           req => 1,
           summary => "A required option as well as positional argument",
         },
         "-z" => {
           alias_for    => "bool1",
           alias_spec   => 'fix',
           arg          => "bool1",
           arg_spec     => 'fix',
           category     => "Cat1 options",
           description  => undef,
           fqarg        => "bool1",
           is_alias     => 1,
           main_opt     => "--bool1",
           opt_parsed   => { opts => ["z"] },
           orig_opt     => "z",
           raw_category => "cat1",
           summary      => "This is summary for option `-z`",
           tags         => 'fix',
         },
       },
       usage_line => "[[prog]] [options] <str1>",
     },
   ];
   $a->[2]{opts}{"--bool1"}{tags} = $a->[2]{opts}{"--bool1"}{arg_spec}{tags};
   $a->[2]{opts}{"--flag1, -f"}{tags} = $a->[2]{opts}{"--flag1, -f"}{arg_spec}{tags};
   $a->[2]{opts}{"-z"}{alias_spec} = $a->[2]{opts}{"--bool1"}{arg_spec}{cmdline_aliases}{z};
   $a->[2]{opts}{"-z"}{arg_spec} = $a->[2]{opts}{"--bool1"}{arg_spec};
   $a->[2]{opts}{"-z"}{tags} = $a->[2]{opts}{"--bool1"}{arg_spec}{tags};
   $a;
 }

For a more complete sample, see function metadata for C<demo_cli_opts> in
L<Perinci::Examples::CLI>.

=head1 FUNCTIONS


=head2 gen_cli_doc_data_from_meta(%args) -> [status, msg, result, meta]

From Rinci function metadata, generate structure convenient for producing CLI documentation (help/usage/POD).

This function calls C<Perinci::Sub::GetArgs::Argv>'s
C<gen_getopt_long_spec_from_meta()> (or receive its result as an argument, if
passed, to avoid calling the function twice) and post-processes it: produce
command usage line, format the options, include information from metadata, group
the options by category. It also selects examples in the C<examples> property
which are applicable to CLI environment and format them.

The resulting data structure is convenient to use when one wants to produce a
documentation for CLI program (including help/usage message and POD).

Arguments ('*' denotes required arguments):

=over 4

=item * B<common_opts> => I<hash>

Will be passed to gen_getopt_long_spec_from_meta().

=item * B<ggls_res> => I<array>

Full result from gen_getopt_long_spec_from_meta().

If you already call C<Perinci::Sub::GetArgs::Argv>'s
C<gen_getopt_long_spec_from_meta()>, you can pass the I<full> enveloped result
here, to avoid calculating twice. What will be useful for the function is the
extra result in result metadata (C<func.*> keys in C<< $res-E<gt>[3] >> hash).

=item * B<lang> => I<str>

=item * B<meta>* => I<hash>

=item * B<meta_is_normalized> => I<bool>

=item * B<per_arg_json> => I<bool>

Pass per_arg_json=1 to Perinci::Sub::GetArgs::Argv.

=item * B<per_arg_yaml> => I<bool>

Pass per_arg_json=1 to Perinci::Sub::GetArgs::Argv.

=back

Return value:

Returns an enveloped result (an array).

First element (status) is an integer containing HTTP status code
(200 means OK, 4xx caller error, 5xx function error). Second element
(msg) is a string containing error message, or 'OK' if status is
200. Third element (result) is optional, the actual result. Fourth
element (meta) is called result metadata and is optional, a hash
that contains extra information.

 (hash)

=head1 SEE ALSO

L<Perinci::CmdLine>, L<Perinci::CmdLine::Lite>

L<Pod::Weaver::Plugin::Rinci>

=head1 HOMEPAGE

Please visit the project's homepage at L<https://metacpan.org/release/Perinci-Sub-To-CLIDocData>.

=head1 SOURCE

Source repository is at L<https://github.com/perlancar/perl-Perinci-Sub-To-CLIOptSpec>.

=head1 BUGS

Please report any bugs or feature requests on the bugtracker website L<https://rt.cpan.org/Public/Dist/Display.html?Name=Perinci-Sub-To-CLIDocData>

When submitting a bug or request, please include a test-file or a
patch to an existing test-file that illustrates the bug or desired
feature.

=head1 AUTHOR

perlancar <perlancar@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by perlancar@cpan.org.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
