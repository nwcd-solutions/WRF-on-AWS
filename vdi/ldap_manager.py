import argparse
import hashlib
import os
import shutil
import sys
from base64 import b64encode as encode

import ldap

sys.path.append(os.path.dirname(__file__))
#import configuration
from cryptography.hazmat.primitives import serialization as crypto_serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.backends import default_backend as crypto_default_backend
import subprocess
import datetime

def run_command(cmd):
        exit(1)


def find_ids():
            'used_gid': used_gid}


def create_home(username):
        return e


def create_group(username, gid_number):
        return e


def create_user(username, password, sudoers, email=False, uid=False, gid=False):
    dn_user = "uid=" + username + ",ou=people," + ldap_base
    enc_passwd = bytes(password, 'utf-8')
    salt = os.urandom(16)
    sha = hashlib.sha1(enc_passwd)
    sha.update(salt)
    digest = sha.digest()
    b64_envelop = encode(digest + salt)
    passwd = '{{SSHA}}{}'.format(b64_envelop.decode('utf-8'))

    attrs = [
        ('objectClass', ['top'.encode('utf-8'),
                         'person'.encode('utf-8'),
                         'posixAccount'.encode('utf-8'),
                         'shadowAccount'.encode('utf-8'),
                         'inetOrgPerson'.encode('utf-8'),
                         'organizationalPerson'.encode('utf-8')]),
        ('uid', [str(username).encode('utf-8')]),
        ('uidNumber', [str(uid).encode('utf-8')]),
        ('gidNumber', [str(gid).encode('utf-8')]),
        ('cn', [str(username).encode('utf-8')]),
        ('sn', [str(username).encode('utf-8')]),
        ('loginShell', ['/bin/bash'.encode('utf-8')]),
        ('homeDirectory', (str(user_home) + '/' + str(username)).encode('utf-8')),
        ('userPassword', [passwd.encode('utf-8')])
    ]

    if email is not False:
        attrs.append(('mail', [email.encode('utf-8')]))

    try:
        con.add_s(dn_user, attrs)
        if sudoers is True:
            sudo = add_sudo(username)
            if sudo is True:
                print('Added user as sudoers')
            else:
                print('Unable to add user as sudoers: ' +str (sudo))
        return True
    except Exception as e:
        print('Unable to create new user: ' +str(e))
        return e


def add_sudo(username):
        return e


def delete_user(username):
        return e


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    subparser = parser.add_subparsers(dest="command")
    subparser_add_user = subparser.add_parser("add-user")
    subparser_add_user.add_argument('-u', '--username', nargs='?', required=True, help='LDAP username')
    subparser_add_user.add_argument('-p', '--password', nargs='?', required=True, help='User password')
    subparser_add_user.add_argument('-e', '--email', nargs='?', help='User email')
    subparser_add_user.add_argument('--uid', nargs='?', help='Specify custom Uid')
    subparser_add_user.add_argument('--gid', nargs='?', help='Specific custom Gid')
    subparser_add_user.add_argument('--admin', action='store_const', const=True, help='If flag is specified, user will be added to sudoers group')

    subparser_delete_user = subparser.add_parser("delete-user")
    subparser_delete_user.add_argument('-u', '--username', nargs='?', required=True, help='LDAP username')

    arg = parser.parse_args()
    ldap_action = arg.command
    # Soca Parameters
    #aligo_configuration = configuration.get_aligo_configuration()
    #ldap_base = aligo_configuration['LdapBase']
    ldap_base=""
    ldap_host=""
    user_home = '/data/home'
    slappasswd = '/sbin/slappasswd'
    root_dn = 'CN=admin,' + ldap_base
    root_pw = open('/root/OpenLdapAdminPassword.txt', 'r').read()
    ldap_args = '-ZZ -x -H "ldap://' + aligo_configuration['LdapHost'] + '" -D ' + root_dn + ' -y ' + root_pw
    con = ldap.initialize('ldap://' + aligo_configuration['LdapHost'])
    con.simple_bind_s(root_dn, root_pw)

    if ldap_action == 'delete-user':
        delete = delete_user(str(arg.username))

    elif ldap_action == 'add-user':
        if arg.email is not None:
            email = arg.email
        else:
            email = False

        # Get next available group/user ID
        ldap_ids = find_ids()
        if arg.gid is None:
            gid = ldap_ids['next_gid']
        else:
            gid = int(arg.gid)

        if arg.uid is None:
            uid = ldap_ids['next_uid']
        else:
            uid = int(arg.uid)

        add_user = create_user(str(arg.username), str(arg.password), arg.admin, email, uid, gid)
        if add_user is True:
            print('Created User: ' + str(arg.username) + ' id: ' + str(uid))
        else:
            print('Unable to create user:' + str(arg.username))
            sys.exit(1)

        add_group = create_group(str(arg.username), gid)
        if add_group is True:
            print('Created group successfully')
        else:
            print('Unable to create group:' + str(arg.username))
            sys.exit(1)

        add_home = create_home(str(arg.username))
        if add_home is True:
            print('Home directory created correctly')
        else:
            print('Unable to create Home structure:' + str(add_home))
            sys.exit(1)

    else:
        exit(1)

    con.unbind_s()
