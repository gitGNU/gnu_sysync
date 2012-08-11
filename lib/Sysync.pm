package Sysync;
use strict;
use Digest::MD5 qw(md5_hex);

=head2 METHODS

=head3 new

Creates a new Sysync object.

=cut

sub new
{
    my ($class, $params) = @_;
    my $self = {
        sysdir      => $params->{sysdir},
        stagedir    => ($params->{stagedir} || "$params->{sysdir}/stage"),
        salt_prefix => (exists($params->{salt_prefix}) ? $params->{salt_prefix} : '$6$'),
    };

    bless($self, $class);

    return $self;
}

=head3 sysdir

Returns the base system directory for sysync.

=cut

sub sysdir { shift->{sysdir} }

=head3 stagedir

=cut

sub stagedir { $_[0]->{stagedir} || join('/', $_[0]->sysdir, 'stage' ) }

=head3 get_user_password

=cut

sub get_user_password { die 'needs implemented' }

=head3 grab_users_from_group

=cut

sub grab_users_from_group { die 'needs implemented' }

=head3 grab_all_groups

Returns array of all groups.

=cut

sub grab_all_groups { die 'needs implemented' }

=head3 generate_user_line

Generate a line for both the user and shadow file.

=cut

sub generate_user_line
{
    my ($self, $user, $what) = @_;

    my $gid      = $user->{gid} || $user->{uid};
    my $fullname = $user->{fullname} || $user->{username};

    my $password = '*';

    if ($user->{password})
    {
        $password = $user->{password};
    }
    else
    {
        my $p = $self->get_user_password($user->{username});

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

=head3 generate_group_line

Generate a line for the group file.

=cut

sub generate_group_line
{
    my ($self, $group) = @_;

    my $users = join(',', @{$group->{users} || []}) || '';
    return join(':', $group->{groupname}, 'x', $group->{gid}, $users);
}

=head3 is_valid_host

Returns true if host is valid.

=cut

sub is_valid_host { die 'needs implemented' }

=head3 get_host_ent

For a generate all of the password data, including ssh keys, for a specific host.

=cut

sub get_host_ent
{
    my ($self, $host) = @_;

    return unless $self->is_valid_host($host);
    
    my $data   = $self->grab_host_users_groups($host);
    my @users  = @{$data->{users} || []};
    my @groups = @{$data->{groups} || []};

    my $passwd = join("\n", map { $self->generate_user_line($_, 'passwd') } @users) . "\n";
    my $shadow = join("\n", map { $self->generate_user_line($_, 'shadow') } @users) . "\n";
    my $group  = join("\n", map { $self->generate_group_line($_) } @groups) . "\n";

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

=head3 get_hosts

=cut

sub get_hosts { die 'needs implemented' }

=head3 update_all_hosts

Iterate through every host and build password files.

=cut

sub update_all_hosts
{
    my ($self, %params) = @_;

    # grab list of hosts along with image name
    my $hosts = $params{hosts} || $self->get_hosts;

    # first, build staging directories
    my @hosts = keys %{ $hosts->{hosts} || {} };

    my $stagedir = $self->stagedir;

    my $r = 0;

    for my $host (@hosts)
    {
        next unless $self->is_valid_host($host);

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
        my $ent_data = $self->get_host_ent($host);

        next unless $ent_data;

        for my $key (@{ $ent_data->{ssh_keys} || [] })
        {
            my $username = $key->{username};
            my $uid      = $key->{uid};
            my $text     = $key->{keys};

            if ($self->write_file_contents("$stagedir/$host/etc/ssh/authorized_keys/$username", $text))
            {
                chmod 0600, "$stagedir/$host/etc/ssh/authorized_keys/$username";
                chown $uid, 0, "$stagedir/$host/etc/ssh/authorized_keys/$username";
                $r++;
            }
        }

        if ($self->write_file_contents("$stagedir/$host/etc/passwd", $ent_data->{passwd}))
        {
            chmod 0644, "$stagedir/$host/etc/passwd";
            chown 0, 0, "$stagedir/$host/etc/passwd";
            $r++;
        }

        if ($self->write_file_contents("$stagedir/$host/etc/group", $ent_data->{group}))
        {
            chmod 0644, "$stagedir/$host/etc/group";
            chown 0, 0, "$stagedir/$host/etc/group";
            $r++;
        }

        if ($self->write_file_contents("$stagedir/$host/etc/shadow", $ent_data->{shadow}))
        {
            chmod 0640, "$stagedir/$host/etc/shadow";
            chown 0, 42, "$stagedir/$host/etc/shadow";
            $r++;
        }
    }

    return $r;
}

=head3 write_file_contents

=cut

sub write_file_contents
{
    my ($self, $file, $data) = @_;

    # check to see if this differs

    if (-e $file)
    {
        if (md5_hex($data) eq md5_hex($self->read_file_contents($file)))
        {
            return;
        }
    }

    $self->log("writing: $file");

    open(F, "> $file") or die $!;
    print F $data;
    close(F);

    return 1;
}

=head3 read_file_contents

=cut

sub read_file_contents
{
    my ($self, $file) = @_;

    open(my $fh, $file);
    my @content = <$fh>;
    close($fh);

    return join('', @content);
}

1;


=head1 COPYRIGHT

2012 Ohio-Pennsylvania Software, LLC.

=head1 LICENSE

 Copyright (C) 2012 Ohio-Pennsylvania Software, LLC.

 This file is part of Sysync.
 
 Sysync is free software: you can redistribute it and/or modify
 it under the terms of the GNU Affero General Public License as
 published by the Free Software Foundation, either version 3 of the
 License, or (at your option) any later version.
 
 Sysync is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU Affero General Public License for more details.
 
 You should have received a copy of the GNU Affero General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>.

=head1 AUTHOR

Michael J. Flickinger, C<< <mjflick@gnu.org> >>

=cut

