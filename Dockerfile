# Dockerfile
FROM ubuntu:trusty

RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

ARG OPENRESTY_VERSION
ARG OPENRESTY_VERSION_ID
ENV OPENRESTY_NAME ngx_openresty-$OPENRESTY_VERSION
ENV OPENRESTY_FILE $OPENRESTY_NAME.tar.gz

# Required system packages
RUN apt-get update \
    && apt-get install -y \
        wget \
        unzip \
        build-essential \
        ruby-dev \
        libreadline6-dev \
        libncurses5-dev \
        perl \
        libpcre3-dev \
        libssl-dev \
    && apt-get clean
RUN gem install --no-ri --no-rdoc fpm

RUN mkdir /build /build/root
WORKDIR /build

# Download packages
RUN wget https://openresty.org/download/$OPENRESTY_FILE \
    && tar xfz $OPENRESTY_FILE
RUN wget http://zlib.net/zlib-1.2.8.tar.gz \
    && tar xfz zlib-1.2.8.tar.gz
RUN wget https://www.openssl.org/source/openssl-1.0.2e.tar.gz \
    && tar xfz openssl-1.0.2e.tar.gz

# Compile and install openresty
RUN cd /build/$OPENRESTY_NAME \
    && ./configure \
        --with-http_ssl_module \
        --with-http_stub_status_module \
        --with-http_gzip_static_module \
        --with-debug \
        --with-pcre-jit \
        --with-zlib=/build/zlib-1.2.8 \
        --with-openssl=/build/openssl-1.0.2e \
        --with-cc-opt='-O2 -fstack-protector --param=ssp-buffer-size=4 -Wformat -Werror=format-security -D_FORTIFY_SOURCE=2' \
        --with-ld-opt='-Wl,-Bsymbolic-functions -Wl,-z,relro' \
        --prefix=/usr/share/nginx \
        --sbin-path=/usr/sbin/nginx \
        --conf-path=/etc/nginx/nginx.conf \
        --http-log-path=/var/log/nginx/access.log \
        --error-log-path=/var/log/nginx/error.log \
        --lock-path=/var/lock/nginx.lock \
        --pid-path=/run/nginx.pid \
        --http-client-body-temp-path=/var/lib/nginx/body \
        --http-fastcgi-temp-path=/var/lib/nginx/fastcgi \
        --http-proxy-temp-path=/var/lib/nginx/proxy \
        --http-scgi-temp-path=/var/lib/nginx/scgi \
        --http-uwsgi-temp-path=/var/lib/nginx/uwsgi \
        --user=www-data \
        --group=www-data \
    && make -j4 \
    && make install DESTDIR=/build/root

COPY scripts/* nginx-scripts/
COPY conf/* nginx-conf/

# Add extras to the build root
RUN cd /build/root \
    && mkdir \
        etc/init.d \
        etc/logrotate.d \
        etc/nginx/sites-available \
        etc/nginx/sites-enabled \
        var/lib \
        var/lib/nginx \
    && mv usr/share/nginx/bin/resty usr/sbin/resty && rm -rf usr/share/nginx/bin \
    && mv usr/share/nginx/nginx/html usr/share/nginx/html && rm -rf usr/share/nginx/nginx \
    && rm etc/nginx/*.default \
    && cp /build/nginx-scripts/init etc/init.d/nginx \
    && chmod +x etc/init.d/nginx \
    && cp /build/nginx-conf/logrotate etc/logrotate.d/nginx \
    && cp /build/nginx-conf/nginx.conf etc/nginx/nginx.conf \
    && cp /build/nginx-conf/default etc/nginx/sites-available/default

# Build deb
RUN fpm -s dir -t deb \
    -n nginx-openresty \
    -v $OPENRESTY_VERSION_ID \
    -C /build/root \
    -p openresty_VERSION_ARCH.deb \
    --description 'a high performance web server and a reverse proxy server' \
    --url 'http://openresty.org/' \
    --category httpd \
    --maintainer 'Anton Ovchinnikov <anton.ovchi2nikov@gmail.com>' \
    --depends wget \
    --depends unzip \
    --depends libncurses5 \
    --depends libreadline6 \
    --deb-build-depends build-essential \
    --replaces 'nginx-full' \
    --provides 'nginx-full' \
    --conflicts 'nginx-full' \
    --replaces 'nginx-common' \
    --provides 'nginx-common' \
    --conflicts 'nginx-common' \
    --after-install nginx-scripts/postinstall \
    --before-install nginx-scripts/preinstall \
    --after-remove nginx-scripts/postremove \
    --before-remove nginx-scripts/preremove \
    etc run usr var

