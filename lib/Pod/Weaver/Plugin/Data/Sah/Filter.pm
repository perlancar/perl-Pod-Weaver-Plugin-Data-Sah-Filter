package Pod::Weaver::Plugin::Data::Sah::Filter;

use 5.010001;
use Moose;
with 'Pod::Weaver::Role::AddTextToSection';
with 'Pod::Weaver::Role::Section';

use Data::Dmp;
use File::Temp;

# AUTHORITY
# DATE
# DIST
# VERSION

sub _process_filter_module {
    no strict 'refs'; ## no critic: TestingAndDebugging::ProhibitNoStrict

    my ($self, $document, $input, $package) = @_;

    my $zilla = $input->{zilla};

    my $filename = $input->{filename};

    require Require::Hook::Source::DzilBuild;
    local @INC = (Require::Hook::Source::DzilBuild->new(zilla => $input->{zilla}, debug=>1), @INC);

    my ($rule_cat, $rule_desc, $meta);
    {
        my $package_pm = $package;
        $package_pm =~ s!::!/!g;
        $package_pm .= ".pm";

        # force reload
        (my $package_pm = "$package.pm") =~ s!::!/!g;
        delete $INC{$package_pm};

        { no warnings 'redefine'; require $package_pm; }

        {
            no strict 'refs'; ## no critic: TestingAndDebugging::ProhibitNoStrict
            $meta = $package->meta;
            #use DD; print "VERSION: "; dd ${"$package\::VERSION"}; print "meta: "; dd $meta;
        }
        $package =~ /\AData::Sah::Filter::\w+::(\w+)::(\w+)\z/
            or $self->log_fatal("Invalid module name $package, please use Data::Sah::Filter::<LANG>::<CATEGORY>::<DESCRIPTION>");
        $rule_cat  = $1;
        $rule_desc = $2;
    }

    # add Synopsis section
    {
        my @pod;
        my $type = $meta->{target_type} // "str";
        my $filter = ["$rule_cat\::$rule_desc"];
        my $schema = [$type, "prefilters" => [$filter]];

        push @pod, "=head2 Using in Sah schema's C<prefilters> (or C<postfilters>) clause\n\n",
            " ", dmp($schema), "\n\n";

        push @pod, "=head2 Using with L<Data::Sah>:\n\n",
            " use Data::Sah qw(gen_validator);\n",
            " \n",
            " my \$schema = ", dmp($schema), ";\n",
            " my \$validator = gen_validator(\$schema);\n",
            " if (\$validator->(\$some_data)) { print 'Valid!' }\n\n";

        push @pod, "=head2 Using with L<Data::Sah:Filter> directly:\n\n",
            " use Data::Sah::Filter qw(gen_filter);\n\n",
            " my \$filter = gen_filter([", dmp($filter), "]);\n";
        if ($meta->{might_fail}) {
            push @pod,
                " # \$errmsg will be empty/undef when filtering succeeds\n",
                " my (\$errmsg, \$filtered_value) = \$filter->(\$some_data);\n\n";
        } else {
            push @pod, " my \$filtered_value = \$filter->(\$some_data);\n\n";
        }

        if ($meta->{examples} && @{ $meta->{examples} }) {
            require Data::Sah::Filter;
            require Data::Cmp;
            push @pod, "=head2 Sample data and filtering results\n\n";
            for my $eg (@{ $meta->{examples} }) {
                my $filter_rule = ["$rule_cat\::$rule_desc", $eg->{filter_args} // {}];
                my $filter_code = Data::Sah::Filter::gen_filter(filter_names=>[$filter_rule]);
                my ($actual_errmsg, $actual_filtered_value);
                if ($meta->{might_fail}) {
                    ($actual_errmsg, $actual_filtered_value) = @{ $filter_code->($eg->{value}) };
                } else {
                    $actual_filtered_value = $filter_code->($eg->{value});
                    $actual_errmsg = undef;
                }
                my $correct_filtered_value = exists($eg->{filtered_value}) ?
                    $eg->{filtered_value} : $eg->{value};
                push @pod, " ", dmp($eg->{value}), " #",
                    ($eg->{filter_args} ? " filtered with args ".dmp($eg->{filter_args}).", " : " "),
                    ($actual_errmsg ? "INVALID ($actual_errmsg)" : "valid"), ", ",
                    (Data::Cmp::cmp_data($eg->{value}, $actual_filtered_value) == 0 ? "unchanged" : "becomes ".dmp($actual_filtered_value)), "\n";
            }
            push @pod, "\n";
        }

        $self->add_text_to_section(
            $document, join("", @pod), 'SYNOPSIS',
            {
                after_section => ['VERSION', 'NAME'],
                before_section => 'DESCRIPTION',
                ignore => 1,
            });
    }

    # add Description section
    {
        last unless $meta->{description};

        require Markdown::To::POD;
        my @pod;
        push @pod, Markdown::To::POD::markdown_to_pod($meta->{description}), "\n\n";

        $self->add_text_to_section(
            $document, join("", @pod), 'DESCRIPTION',
            {
                after_section => ['VERSION', 'NAME', 'SYNOPSIS'],
                ignore => 1,
            });
    }

    #
    $self->log(["Generated POD for '%s'", $filename]);
}

sub _list_my_filter_modules {
    my ($self, $input) = @_;

    my @res;
    for my $file (@{ $input->{zilla}->files }) {
        my $name = $file->name;
        next unless $name =~ m!^lib/Data/Sah/Filter/!;
        $name =~ s!^lib/!!; $name =~ s/\.pm$//; $name =~ s!/!::!g;
        push @res, $name;
    }
    @res;
}

sub _process_filterbundle_module {
    no strict 'refs'; ## no critic: TestingAndDebugging::ProhibitNoStrict

    my ($self, $document, $input, $package) = @_;

    my $filename = $input->{filename};

    # XXX handle dynamically generated module (if there is such thing in the
    # future)
    local @INC = ("lib", @INC);

    {
        my $package_pm = $package;
        $package_pm =~ s!::!/!g;
        $package_pm .= ".pm";
        require $package_pm;
    }

    # add list of Bencher::Scenario::* modules to Description
    {
        my @pod;
        my @filter_mods = $self->_list_my_filter_modules($input);
        push @pod, "This distribution contains the following L<Sah> filter rule modules:\n\n";
        push @pod, "=over\n\n";
        push @pod, "=item * L<$_>\n\n" for @filter_mods;
        push @pod, "=back\n\n";

        $self->add_text_to_section(
            $document, join("", @pod), 'DESCRIPTION',
            {
                after_section => ['SYNOPSIS'],
                top => 1,
            });
    }

    $self->log(["Generated POD for '%s'", $filename]);
}

sub weave_section {
    my ($self, $document, $input) = @_;

    my $filename = $input->{filename};

    my $package;
    if ($filename =~ m!^lib/(Data/Sah/Filter/.+)\.pm$!) {
        {
            $package = $1 // $2;
            $package =~ s!/!::!g;
            $self->_process_filter_module($document, $input, $package);
        }
    }
    if ($filename =~ m!^lib/(Data/Sah/FilterBundle/.+)\.pm$!) {
        {
            # since this PW plugin might be called more than once, we avoid
            # duplicate processing via a state variable
            state %mem;
            last if $mem{$filename}++;
            $package = $1;
            $package =~ s!/!::!g;
            $self->_process_filterbundle_module($document, $input, $package);
        }
    }
}

1;
# ABSTRACT: Plugin to use when building Data::Sah::Filter::* or Data::Sah::FilterBundle::* distribution

=for Pod::Coverage .*

=head1 SYNOPSIS

In your F<weaver.ini>:

 [-Data::Sah::Filter]

=head1 DESCRIPTION

This plugin is to be used when building C<Data::Sah::Filter::*> or
C<Data::Sah::FilterBundle::*> distribution. Currently it does the following:

For each C<lib/Data/Sah/Filter/*> module file:

=over

=item * Add a Synopsis section (if doesn't already exist) containing an example on how to use the Sah filter rule module in a Sah schema

=back

For each C<lib/Data/Sah/FilterBundle/*> module file:

=over

=item * Add list of filter rule modules at the beginning of Description section

=back


=head1 CONFIGURATION


=head1 SEE ALSO

L<Data::Sah::Filter>

L<Dist::Zilla::Plugin::Data::Sah::Filter>

L<Sah>
