#!/bin/bash
set -e

#judgement
if [[ -a /etc/supervisor/conf.d/supervisord.conf ]]; then
  exit 0
fi
export FQDN
export DOMAIN
export VMAILUID
export VMAILGID
export DBHOST
export DBNAME
export DBUSER
export CAFILE
export CERTFILE
export KEYFILE
export FULLCHAIN

FQDN=$(hostname --fqdn)
DOMAIN=$(hostname --domain)
VMAILUID=${VMAILUID:-1024}
VMAILGID=${VMAILGID:-1024}
DBHOST=${DBHOST:-mariadb}
DBNAME=${DBNAME:-postfix}
DBUSER=${DBUSER:-postfix}
DISABLE_CLAMAV=${DISABLE_CLAMAV:-false}
DISABLE_SPAMASSASSIN=${DISABLE_SPAMASSASSIN:-false}
OPENDKIM_KEY_LENGTH=${OPENDKIM_KEY_LENGTH:-2048}
ADD_DOMAINS=${ADD_DOMAINS:-}

if [ -z "$DBPASS" ]; then
  echo "Mariadb database password must be set !"
  exit 1
fi

# SSL certificates
LETS_ENCRYPT_LIVE_PATH=/etc/letsencrypt/live/"$FQDN"

if [ -d "$LETS_ENCRYPT_LIVE_PATH" ]; then
  FULLCHAIN="$LETS_ENCRYPT_LIVE_PATH"/fullchain.pem
  CAFILE="$LETS_ENCRYPT_LIVE_PATH"/chain.pem
  CERTFILE="$LETS_ENCRYPT_LIVE_PATH"/cert.pem
  KEYFILE="$LETS_ENCRYPT_LIVE_PATH"/privkey.pem

  # When using https://github.com/JrCs/docker-nginx-proxy-letsencrypt
  # and https://github.com/jwilder/nginx-proxy there is only key.pem and fullchain.pem
  # so we look for key.pem and extract cert.pem and chain.pem
  if [ ! -e "$KEYFILE" ]; then
    KEYFILE="$LETS_ENCRYPT_LIVE_PATH"/key.pem
  fi

  if [ ! -e "$KEYFILE" ]; then
    echo "No keyfile found in $LETS_ENCRYPT_LIVE_PATH !"
    exit 1
  fi

  if [ ! -e "$CAFILE" ] || [ ! -e "$CERTFILE" ]; then
    if [ ! -e "$FULLCHAIN" ]; then
      echo "No fullchain found in $LETS_ENCRYPT_LIVE_PATH !"
      exit 1
    fi

    awk -v path="$LETS_ENCRYPT_LIVE_PATH" 'BEGIN {c=0;} /BEGIN CERT/{c++} { print > path"/cert" c ".pem"}' < "$FULLCHAIN"
    mv "$LETS_ENCRYPT_LIVE_PATH"/cert1.pem "$CERTFILE"
    mv "$LETS_ENCRYPT_LIVE_PATH"/cert2.pem "$CAFILE"
  fi

else
  FULLCHAIN=/var/mail/ssl/selfsigned/cert.pem
  CAFILE=
  CERTFILE=/var/mail/ssl/selfsigned/cert.pem
  KEYFILE=/var/mail/ssl/selfsigned/privkey.pem

  if [ ! -e "$CERTFILE" ] || [ ! -e "$KEYFILE" ]; then
    mkdir -p /var/mail/ssl/selfsigned/
    openssl req -new -newkey rsa:4096 -days 3658 -sha256 -nodes -x509 \
      -subj "/C=FR/ST=France/L=Paris/O=Mailserver certificate/OU=Mail/CN=*.${DOMAIN}/emailAddress=admin@${DOMAIN}" \
      -keyout "$KEYFILE" \
      -out "$CERTFILE"
  fi
fi

# Diffie-Hellman parameters
if [ ! -e /var/mail/ssl/dhparams/dh2048.pem ] || [ ! -e /var/mail/ssl/dhparams/dh512.pem ]; then
  mkdir -p /var/mail/ssl/dhparams/
  openssl dhparam -out /var/mail/ssl/dhparams/dh2048.pem 2048
  openssl dhparam -out /var/mail/ssl/dhparams/dh512.pem 512
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
#  postfix service
############
cat >> /opt/postfix.sh <<EOF
#!/bin/bash
service postfix start
tail -f /var/log/mail.log
EOF

chmod +x /opt/postfix.sh

postconf -F '*/*/chroot = n'
############
postconf -e 'home_mailbox = Maildir/'
postconf -e 'smtpd_banner = $myhostname Tagazok !'
postconf -e 'mail_name = PiouPiou'
postconf -e 'mail_version = 6.6.6'
postconf -e 'inet_interfaces = all'
postconf -e 'inet_protocols = ipv4'
postconf -e 'myhostname = {{ FQDN }}'
postconf -e 'mydomain = xtremxpert.com'
postconf -e 'myorigin = {{ FQDN }}'
postconf -e 'mydestination = localhost localhost.$mydomain'
postconf -e 'mynetworks = 127.0.0.0/8,192.99.24.64/28,10.42.0.0/16,172.17.0.0/16'
postconf -e 'allow_percent_hack   = no'
postconf -e 'delay_warning_time   = 4h'
postconf -e 'mailbox_command      = procmail -a "$EXTENSION"'
postconf -e 'disable_vrfy_command = yes'
postconf -e 'mailbox_size_limit = 0'
postconf -e 'recipient_delimiter = +'
postconf -e 'virtual_transport = virtual'
postconf -e 'message_size_limit = 502400000'
postconf -e 'mailbox_size_limit   = 1024000000'
postconf -e 'virtual_mailbox_limit = 1024000000'
postconf -e 'error_notice_recipient     = admin@{{ DOMAIN }}'

############
# MySQL
# Configuration to use the table 
# create from postfixadmin
############
postconf -e 'virtual_uid_maps = static:{{ VMAILUID }}'
postconf -e 'virtual_gid_maps = static:{{ VMAILGID }}'
postconf -e 'virtual_minimum_uid = {{ VMAILUID }}'
postconf -e 'virtual_mailbox_base = /var/vmail'
postconf -e 'virtual_transport = lmtp:inet:dovecot:10026'

########################
# Vérifier SQL
########################
postconf -e 'virtual_mailbox_domains = mysql:/etc/postfix/mysql_virtual_domains_maps.cf'
postconf -e 'virtual_mailbox_maps = mysql:/etc/postfix/mysql_virtual_mailbox_maps.cf, mysql:/etc/postfix/mysql_virtual_mailbox_domainaliases_maps.cf'
postconf -e 'virtual_alias_maps = mysql:/etc/postfix/mysql_virtual_alias_maps.cf, mysql:/etc/postfix/mysql_virtual_alias_domainaliases_maps.cf'

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
####################
## TLS PARAMETERS ##
####################
# /etc/postfix/main.cf
# Outgoing
postconf -e 'smtp_tls_loglevel = 2'
postconf -e 'smtp_tls_security_level = may'
postconf -e 'smtp_tls_CAfile = {{ CAFILE }}'
postconf -e 'smtp_tls_protocols = !SSLv2, !SSLv3'
postconf -e 'smtp_tls_mandatory_protocols = !SSLv2, !SSLv3'
postconf -e 'smtp_tls_note_starttls_offer = yes'

# Ingoing
postconf -e 'smtpd_tls_loglevel = 2'
postconf -e 'smtpd_tls_auth_only = yes'
postconf -e 'smtpd_tls_security_level = may'
postconf -e 'smtpd_tls_protocols = !SSLv2, !SSLv3'
postconf -e 'smtpd_tls_mandatory_protocols = !SSLv2, !SSLv3'
postconf -e 'smtpd_tls_exclude_ciphers = aNULL,eNULL,EXPORT,DES,3DES,RC2,RC4,MD5,PSK,SRP,DSS,AECDH,ADH'
postconf -e 'smtpd_tls_CAfile = $smtp_tls_CAfile'
postconf -e 'smtpd_tls_cert_file = {{ CERTFILE }}'
postconf -e 'smtpd_tls_key_file = {{ KEYFILE }}'
postconf -e 'smtpd_tls_dh1024_param_file   = /var/mail/ssl/dhparams/dh2048.pem'
postconf -e 'smtpd_tls_dh512_param_file    = /var/mail/ssl/dhparams/dh512.pem'
postconf -e 'tls_preempt_cipherlist = yes'
postconf -e 'lmtp_tls_session_cache_database  = btree:${data_directory}/lmtp_scache'

#####################
## SASL PARAMETERS ##
#####################
postconf -e 'smtpd_sasl_auth_enable = yes'
postconf -e 'smtpd_sasl_type = dovecot'
#postconf -e 'smtpd_sasl_path = private/auth'
postconf -e 'smtpd_sasl_path = inet:dovecot:12345'
postconf -e 'smtpd_sasl_local_domain = $mydomain'
postconf -e 'smtpd_sasl_authenticated_header = yes'
postconf -e 'smtpd_sender_login_maps  = mysql:/etc/postfix/mysql/mysql-sender-login-maps.cf'
postconf -e 'broken_sasl_auth_clients = yes'

#####################
## RESTRICTION     ##
#####################
postconf -e 'smtpd_relay_restrictions= \
    permit_mynetworks, \
    permit_sasl_authenticated, \
    reject_unauth_destination'

postconf -e 'smtpd_sender_restrictions= \
    reject_non_fqdn_sender, \
    reject_unknown_sender_domain, \
    reject_sender_login_mismatch, \
    reject_rhsbl_sender dbl.spamhaus.org'

postconf -e 'smtpd_recipient_restrictions= \
    permit_mynetworks, \
    permit_sasl_authenticated, \
    reject_unknown_recipient_domain, \
    reject_non_fqdn_recipient, \
    reject_unlisted_recipient, \
    reject_rbl_client zen.spamhaus.org'

postconf -e 'smtpd_helo_required = yes'
postconf -e 'smtpd_helo_restrictions =
    permit_mynetworks, \
    permit_sasl_authenticated, \
    reject_invalid_helo_hostname, \
    reject_non_fqdn_helo_hostname'

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

