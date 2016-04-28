#!/bin/bash
set -e

#judgement
if [[ -a /etc/supervisor/conf.d/supervisord.conf ]]; then
  exit 0
fi

#supervisor
cat > /etc/supervisor/conf.d/supervisord.conf <<EOF
[supervisord]
nodaemon=true

[program:postfix]
command=/opt/postfix.sh

[program:rsyslog]
command=/usr/sbin/rsyslogd -n -c3
EOF

############
#  postfix
############
cat >> /opt/postfix.sh <<EOF
#!/bin/bash
service postfix start
tail -f /var/log/mail.log
EOF

chmod +x /opt/postfix.sh
#postconf -e myhostname=$maildomain
postconf -F '*/*/chroot = n'
############
postconf -e 'home_mailbox = Maildir/'
postconf -e 'smtpd_banner = $myhostname Tagazok !'
postconf -e 'mail_name = PiouPiou'
postconf -e 'mail_version = 6.6.6'
postconf -e 'inet_interfaces = all'
postconf -e 'inet_protocols = ipv4'
postconf -e 'myhostname = poste.xtremxpert.com'
postconf -e 'mydomain = xtremxpert.com'
postconf -e 'myorigin = xtremxpert.com'
postconf -e 'mydestination = poste.xtremxpert.com, xtremxpert.com, localhost, localhost.localdomain'
postconf -e 'mynetworks = 127.0.0.0/8,192.99.24.64/28'
postconf -e 'relay_domains = xtremxpert.com'
postconf -e 'mailbox_size_limit = 0'
postconf -e 'recipient_delimiter = +'
postconf -e 'virtual_transport = lmtp:dovecot:10026'
postconf -e 'message_size_limit = 134217728'
############
# MySQL
# Configuration to use the table 
# create from postfixadmin
############
postconf -e 'virtual_mailbox_base = /var/vmail'
postconf -e 'virtual_mailbox_maps = mysql:/etc/postfix/mysql_virtual_mailbox_maps.cf, mysql:/etc/postfix/mysql_virtual_mailbox_domainaliases_maps.cf'
postconf -e 'virtual_uid_maps = static:150'
postconf -e 'virtual_gid_maps = static:8'
postconf -e 'virtual_alias_maps = mysql:/etc/postfix/mysql_virtual_alias_maps.cf, mysql:/etc/postfix/mysql_virtual_alias_domainaliases_maps.cf'
postconf -e 'virtual_mailbox_domains = mysql:/etc/postfix/mysql_virtual_domains_maps.cf'
############
# Lien Postfix - MySQL
# Configuration to use the tables 
# for domains alias
############
cat >> /etc/postfix/mysql_virtual_alias_domainaliases_maps.cf <<EOF
user = mailserveruser
password = mailserverpass
hosts = mariadb
dbname = mailserver
query = SELECT goto FROM alias,alias_domain
  WHERE alias_domain.alias_domain = '%d'
  AND alias.address=concat('%u', '@', alias_domain.target_domain)
  AND alias.active = 1
EOF
############
# Lien Postfix - MySQL
# Configuration to use the tables 
# for alias
############
cat >> /etc/postfix/mysql_virtual_alias_maps.cf <<EOF
user = mailserveruser
password = mailserverpass
hosts = mariadb
dbname = mailserver
table = alias
select_field = goto
where_field = address
additional_conditions = and active = '1'
EOF
############
# Lien Postfix - MySQL
# Configuration to use the tables 
# for Domains
############
cat >> /etc/postfix/mysql_virtual_domains_maps.cf <<EOF
user = mailserveruser
password = mailserverpass
hosts = mariadb
dbname = mailserver
table = domain
select_field = domain
where_field = domain
additional_conditions = and backupmx = '0' and active = '1'
EOF
############
# Lien Postfix - MySQL
# Configuration to use the tables 
# for Domains
############
cat >> /etc/postfix/mysql_virtual_mailbox_domainaliases_maps.cf <<EOF
user = mailserveruser
password = mailserverpass
hosts = mariadb
dbname = mailserver
query = SELECT maildir FROM mailbox, alias_domain
  WHERE alias_domain.alias_domain = '%d'
  AND mailbox.username=concat('%u', '@', alias_domain.target_domain )
  AND mailbox.active = 1
EOF
############
# Lien Postfix - MySQL
# Configuration to use the tables 
# for Mailbox
############
cat >> /etc/postfix/mysql_virtual_mailbox_maps.cf <<EOF
user = mailserveruser
password = mailserverpass
hosts = mariadb
dbname = mailserver
table = mailbox
select_field = CONCAT(domain, '/', local_part)
where_field = username
additional_conditions = and active = '1'
EOF
############
# SASL SUPPORT FOR CLIENTS
# The following options set parameters needed by Postfix to enable
# Cyrus-SASL support for authentication of mail clients.
############
# /etc/postfix/main.cf
#postconf -e smtpd_sasl_auth_enable=yes
#postconf -e broken_sasl_auth_clients=yes
#postconf -e smtpd_recipient_restrictions=permit_sasl_authenticated,reject_unauth_destination
# smtpd.conf
#cat >> /etc/postfix/sasl/smtpd.conf <<EOF
#pwcheck_method: auxprop
#auxprop_plugin: sasldb
#mech_list: PLAIN LOGIN CRAM-MD5 DIGEST-MD5 NTLM
#EOF
# sasldb2
#echo $smtp_user | tr , \\n > /tmp/passwd
#while IFS=':' read -r _user _pwd; do
#  echo $_pwd | saslpasswd2 -p -c -u $maildomain $_user
#done < /tmp/passwd
#chown postfix.sasl /etc/sasldb2

############
# Enable TLS
############
############
# SUBMISSION
# Activate submission port as an alternative to send mail
# Will accept only secure
############
postconf -M smtp/inet="smtp   inet   n   -   -   -   -   smtpd"
postconf -M smtps/inet="smtps   inet   n   -   -   -   -   smtpd"
postconf -M submission/inet="submission   inet   n   -   -   -   -   smtpd"
postconf -P "submission/inet/syslog_name=postfix/submission"
# FIXME Re-add DKIM
#-o smtpd_milters=inet:127.0.0.1:8891
#postconf -p "submission/inet/smtpd_tls_wrappermode=no"
postconf -P "submission/inet/smtpd_tls_security_level=encrypt"
postconf -P "submission/inet/smtpd_sasl_auth_enable=yes"
postconf -P "submission/inet/smtpd_recipient_restrictions=permit_mynetworks,permit_sasl_authenticated,reject"
postconf -P "submission/inet/milter_macro_daemon_name=ORIGINATING"
#postconf -P "submission/inet/smtpd_sasl_type=dovecot"
#postconf -P "submission/inet/smtpd_sasl_path=private/auth"
#postconf -P "submission/inet/smtpd_etrn_restrictions=reject"
#postconf -P "submission/inet/smtpd_sasl_security_options=noanonymous"
#postconf -P "submission/inet/smtpd_sasl_local_domain=$myhostname"
#postconf -P "submission/inet/smtpd_client_restrictions=permit_sasl_authenticated,reject"


#if [[ -n "$(find /etc/postfix/certs -iname *.crt)" && -n "$(find /etc/postfix/certs -iname *.key)" ]]; then
  # /etc/postfix/main.cf
#  postconf -e smtpd_tls_cert_file=$(find /etc/postfix/certs -iname *.crt)
#  postconf -e smtpd_tls_key_file=$(find /etc/postfix/certs -iname *.key)
#  chmod 400 /etc/postfix/certs/*.*
  # /etc/postfix/master.cf
#  postconf -M submission/inet="submission   inet   n   -   n   -   -   smtpd"
#  postconf -P "submission/inet/syslog_name=postfix/submission"
#  postconf -P "submission/inet/smtpd_tls_security_level=encrypt"
#  postconf -P "submission/inet/smtpd_sasl_auth_enable=yes"
#  postconf -P "submission/inet/milter_macro_daemon_name=ORIGINATING"
#  postconf -P "submission/inet/smtpd_recipient_restrictions=permit_sasl_authenticated,reject_unauth_destination"
#fi

#############
#  opendkim
#############

#if [[ -z "$(find /etc/opendkim/domainkeys -iname *.private)" ]]; then
#  exit 0
#fi
#cat >> /etc/supervisor/conf.d/supervisord.conf <<EOF

#[program:opendkim]
#command=/usr/sbin/opendkim -f
#EOF
# /etc/postfix/main.cf
#postconf -e milter_protocol=2
#postconf -e milter_default_action=accept
#postconf -e smtpd_milters=inet:localhost:12301
#postconf -e non_smtpd_milters=inet:localhost:12301

#cat >> /etc/opendkim.conf <<EOF
#AutoRestart             Yes
#AutoRestartRate         10/1h
#UMask                   002
#Syslog                  yes
#SyslogSuccess           Yes
#LogWhy                  Yes

#Canonicalization        relaxed/simple

#ExternalIgnoreList      refile:/etc/opendkim/TrustedHosts
#InternalHosts           refile:/etc/opendkim/TrustedHosts
#KeyTable                refile:/etc/opendkim/KeyTable
#SigningTable            refile:/etc/opendkim/SigningTable

#Mode                    sv
#PidFile                 /var/run/opendkim/opendkim.pid
#SignatureAlgorithm      rsa-sha256

#UserID                  opendkim:opendkim

#Socket                  inet:12301@localhost
#EOF
#cat >> /etc/default/opendkim <<EOF
#SOCKET="inet:12301@localhost"
#EOF

#cat >> /etc/opendkim/TrustedHosts <<EOF
#127.0.0.1
#localhost
#192.168.0.1/24

#*.$maildomain
#EOF
#cat >> /etc/opendkim/KeyTable <<EOF
#mail._domainkey.$maildomain $maildomain:mail:$(find /etc/opendkim/domainkeys -iname *.private)
#EOF
#cat >> /etc/opendkim/SigningTable <<EOF
#*@$maildomain mail._domainkey.$maildomain
#EOF
#chown opendkim:opendkim $(find /etc/opendkim/domainkeys -iname *.private)
#chmod 400 $(find /etc/opendkim/domainkeys -iname *.private)
