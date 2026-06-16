FROM debian:trixie-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        apache2 \
        libcgi-pm-perl \
        libhtml-template-perl \
        libjson-xs-perl \
        libwww-perl \
    && a2enmod cgid headers negotiation rewrite \
    && printf "ServerName localhost\n" > /etc/apache2/conf-available/servername.conf \
    && a2enconf servername \
    && rm -rf /var/lib/apt/lists/*

COPY apache/000-default.conf /etc/apache2/sites-available/000-default.conf

ENV PERL5LIB=/var/www/html

WORKDIR /var/www/html

EXPOSE 80

CMD ["apachectl", "-D", "FOREGROUND"]
