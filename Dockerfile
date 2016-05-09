FROM ubuntu:latest

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
    ca-certificates \
  && pip install envtpl \
# Add files
ADD assets/install.sh /opt/install.sh

VOLUME /etc/letsencrypt
EXPOSE 25 465 587
# Run
CMD /usr/local/bin/startup
