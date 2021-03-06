FROM debian:latest

MAINTAINER Benoît "XtremXpert" Vézina  <xtremxpert@xtremxpert.com>

# Set noninteractive mode for apt-get
ENV DEBIAN_FRONTEND=noninteractive

# Update & install
RUN apt-get update \
  && apt-get -y install \
    ca-certificates \
    postfix \ 
    postfix-mysql \
    postfix-pcre \
    python-pip \
    rsyslog \
    supervisor \
  && pip install envtpl
# Add files
#ADD assets/install.sh /opt/install.sh
COPY rootfs /
RUN chmod +x /usr/local/bin/*
VOLUME /etc/letsencrypt
EXPOSE 25 465 587
# Run
CMD /usr/local/bin/startup
