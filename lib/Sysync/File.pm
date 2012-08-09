
### 
### _grab_host_users
###
sub _grab_host_users_groups
{
    my $host = shift;

    my $default_host_config = {};
    if (-e "$sysdir/hosts/default.conf")
    {
        $default_host_config = Load(_get_file_contents("$sysdir/hosts/default.conf"));
    }

    my $host_config = {};
    if (-e "$sysdir/hosts/$host.conf")
    {
        $host_config = Load(_get_file_contents("$sysdir/hosts/$host.conf"));
    }

    my (%host_users, %host_groups);
    # merge default users and host users via config

    $host_users{$_->{username}} = $_ for (@{ $default_host_config->{users} || [ ] });
    $host_users{$_->{username}} = $_ for (@{ $host_config->{users} || [ ] });

    $host_groups{$_->{groupname}} = $_ for (@{ $default_host_config->{groups} || [ ] });
    $host_groups{$_->{groupname}} = $_ for (@{ $host_config->{groups} || [ ] });

    my $user_groups = $host_config->{user_groups} || $default_host_config->{user_groups};

    for my $group (@{$user_groups || []})
    {
        my @users;
        if ($group eq 'all')
        {
            @users = _grab_all_users();
        }
        else
        {
            @users = _grab_users_from_group($group);
        }

        for my $username (@users)
        {
            my $user = _grab_user($username);
            next unless $user;

            $host_users{$username} = $user;
        }
    }

    my @users = sort { $a->{uid} <=> $b->{uid} }
        map { $host_users{$_} } keys %host_users;

    # add all groups with applicable users
    for my $group (_grab_all_groups())
    {
        # trust what we have if something is degined already
        next if $host_groups{$group};

        my $group = Load(_get_file_contents("$sysdir/groups/$group.conf"));
        $host_groups{$group->{groupname}} = $group;
    }

    # add magical per-user groups
    for my $user (@users)
    {
        unless ($host_groups{$user->{username}})
        {
            $host_groups{$user->{username}} = {
                gid => $user->{uid},
                groupname => $user->{username},
                users => [ ],
            };
        }
    }

    my @groups = sort { $a->{gid} <=> $b->{gid} }
        map { $host_groups{$_} } keys %host_groups;

    return {
        users => \@users,
        groups => \@groups,
    };
}

sub _grab_user
{
    my $user = shift;

    return unless -e "$sysdir/users/$user.conf";

    my $user_conf = Load(_get_file_contents("$sysdir/users/$user.conf"));

    return $user_conf;
}


sub _grab_all_users
{
    my @users;
    opendir(DIR, "$sysdir/users");
    while (my $file = readdir(DIR))
    {
        if ($file =~ /(.*?)\.conf$/)
        {            
            push @users, $1;
        }
    }
    closedir(DIR);
    return @users;
}

sub _grab_all_groups
{
    my @groups;
    opendir(DIR, "$sysdir/groups");
    while (my $file = readdir(DIR))
    {
        if ($file =~ /(.*?)\.conf$/)
        {            
            push @groups, $1;
        }
    }
    closedir(DIR);
    return @groups;
}

sub _grab_users_from_group
{
    my $group = shift;

    return () unless -e "$sysdir/groups/$group.conf";

    my $group_conf = Load(_get_file_contents("$sysdir/groups/$group.conf"));

    return () unless $group_conf->{users} and ref($group_conf->{users}) eq 'ARRAY';

    return @{ $group_conf->{users} };
}
