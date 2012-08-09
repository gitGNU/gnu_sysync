

sub _generate_user_line
{
    my ($user, $what) = @_;

    my $gid      = $user->{gid} || $user->{uid};
    my $fullname = $user->{fullname} || $user->{username};

    my $password = '*';

    if ($user->{password})
    {
        $password = $user->{password};
    }
    else
    {
        my $p = _get_file_contents("$sysdir/users/$user->{username}.passwd");

        $password = $p if $p;
    }

    my $line = q[];
    if ($what eq 'passwd')
    {
        $line = join(':', $user->{username}, 'x', $user->{uid}, $gid,
                     $fullname, $user->{homedir}, $user->{shell});
    }
    elsif ($what eq 'shadow')
    {
        my $password = $user->{disabled} ? '!' : $password;
        $line = join(':', $user->{username}, $password, 15198, 0, 99999, 7, '','','');
    }

    return $line;
}

sub _generate_group_line
{
    my $group    = shift;

    my $users = join(',', @{$group->{users} || []}) || '';
    return join(':', $group->{groupname}, 'x', $group->{gid}, $users);
}



sub _get_host_ent
{
    my $host = shift;

    return unless "$sysdir/hosts/$host.conf";

    
    my $data = _grab_host_users_groups($host);
    my @users = @{$data->{users} || []};
    my @groups = @{$data->{groups} || []};

    my $passwd = join("\n", map { _generate_user_line($_, 'passwd') } @users) . "\n";
    my $shadow = join("\n", map { _generate_user_line($_, 'shadow') } @users) . "\n";
    my $group  = join("\n", map { _generate_group_line($_) } @groups) . "\n";

    my @ssh_keys;
    for my $user (@users)
    {
        next unless $user->{ssh_keys};

        my $keys = join("\n", @{$user->{ssh_keys} || []});
        $keys .= "\n" if $keys;

        next unless $keys;

        push @ssh_keys, {
            username => $user->{username},
            keys     => $keys,
            uid      => $user->{uid},
        };
    }

    return {
        passwd   => $passwd,
        shadow   => $shadow,
        group    => $group,
        ssh_keys => \@ssh_keys,
    };
}


