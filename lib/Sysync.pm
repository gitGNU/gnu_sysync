

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


sub _update_all_hosts
{
    # grab list of hosts along with image name
    my $hosts = shift || Load(_get_file_contents("$sysdir/hosts.conf")) || {};

    # first, build staging directories
    my @hosts = keys %{ $hosts->{hosts} || {} };

    my $r = 0;

    for my $host (@hosts)
    {
        next unless -e "$sysdir/hosts/$host.conf";

        unless (-d "$stagedir/$host")
        {
            mkdir "$stagedir/$host";
            chmod 0755, "$stagedir/$host";
            chown 0, 0, "$stagedir/$host";
            _log("Creating $stagedir/$host");
            $r++;
        }

        unless (-d "$stagedir/$host/etc")
        {
            mkdir "$stagedir/$host/etc";
            chmod 0755, "$stagedir/$host/etc";
            chown 0, 0, "$stagedir/$host/etc";
            _log("Creating $stagedir/$host/etc");
            $r++;
        }

        unless (-d "$stagedir/$host/etc/ssh")
        {
            mkdir "$stagedir/$host/etc/ssh";
            chmod 0755, "$stagedir/$host/etc/ssh";
            chown 0, 0, "$stagedir/$host/etc/ssh";
            _log("Creating $stagedir/$host/etc/ssh");
            $r++;
        }

        unless (-d "$stagedir/$host/etc/ssh/authorized_keys")
        {
            mkdir "$stagedir/$host/etc/ssh/authorized_keys";
            chmod 0755, "$stagedir/$host/etc/ssh/authorized_keys";
            chown 0, 0, "$stagedir/$host/etc/ssh/authorized_keys";
            _log("Creating $stagedir/$host/etc/ssh/authorized_keys");
            $r++;
        }

        # write host files
        my $ent_data = _get_host_ent($host);

        next unless $ent_data;

        for my $key (@{ $ent_data->{ssh_keys} || [] })
        {
            my $username = $key->{username};
            my $uid      = $key->{uid};
            my $text     = $key->{keys};

            if (_write_file_contents("$stagedir/$host/etc/ssh/authorized_keys/$username", $text))
            {
                chmod 0600, "$stagedir/$host/etc/ssh/authorized_keys/$username";
                chown $uid, 0, "$stagedir/$host/etc/ssh/authorized_keys/$username";
                $r++;
            }
        }

        if (_write_file_contents("$stagedir/$host/etc/passwd", $ent_data->{passwd}))
        {
            chmod 0644, "$stagedir/$host/etc/passwd";
            chown 0, 0, "$stagedir/$host/etc/passwd";
            $r++;
        }

        if (_write_file_contents("$stagedir/$host/etc/group", $ent_data->{group}))
        {
            chmod 0644, "$stagedir/$host/etc/group";
            chown 0, 0, "$stagedir/$host/etc/group";
            $r++;
        }

        if (_write_file_contents("$stagedir/$host/etc/shadow", $ent_data->{shadow}))
        {
            chmod 0640, "$stagedir/$host/etc/shadow";
            chown 0, 42, "$stagedir/$host/etc/shadow";
            $r++;
        }
    }

    return $r;
}
