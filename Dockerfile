FROM ubuntu:14.04

MAINTAINER Benoît "XtremXpert" Vézina  <xtremxpert@xtremxpert.com>

# Set noninteractive mode for apt-get
ENV DEBIAN_FRONTEND=noninteractive
  db_host=mariadb
  db_user=mailserveruser
  db_pass=mailserverpass
  db_name=mailserver

# Update & install
RUN apt-get update \
  && apt-get -y install \
    supervisor \
    postfix \ 
    postfix-pcre \
    postfix-mysql \
    ca-certificates
# Add files
ADD config/ /etc/postfix/
ADD assets/install.sh /opt/install.sh

# Run
CMD /opt/install.sh;/usr/bin/supervisord -c /etc/supervisor/supervisord.conf
