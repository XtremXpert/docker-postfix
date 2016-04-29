FROM ubuntu:14.04

MAINTAINER Benoît "XtremXpert" Vézina  <xtremxpert@xtremxpert.com>

# Set noninteractive mode for apt-get
ENV DEBIAN_FRONTEND=noninteractive

# Update & install
RUN apt-get update \
  && apt-get -y install \
    supervisor \
    postfix \ 
    postfix-pcre \
    postfix-mysql \
    ca-certificates
# Add files
ADD assets/install.sh /opt/install.sh

RUN useradd -m -d /var/vmail -s /bin/false -u 150 -g mail vmail \
  && chown vmail:mail /var/vmail/ \
  && chmod 2770 /var/vmail/ \

# Run
CMD /opt/install.sh;/usr/bin/supervisord -c /etc/supervisor/supervisord.conf
